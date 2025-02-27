package main

import (
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
)

const (
	targetHost         = "https://smooth.fly.dev"
	proxyHost          = "smooth-proxy.fly.dev"
	originalTargetHost = "smooth.fly.dev"
	defaultPort        = "8080"
)

// NoForwardingTransport is a custom transport that prevents automatic header forwarding
type NoForwardingTransport struct {
	transport http.RoundTripper
}

// RoundTrip implements the RoundTripper interface
func (t *NoForwardingTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	// Use the wrapped transport to perform the actual request
	return t.transport.RoundTrip(req)
}

// NewDirector creates a director function for the reverse proxy
func NewDirector(target *url.URL) func(req *http.Request) {
	targetQuery := target.RawQuery
	return func(req *http.Request) {
		// Store original host for potential redirect rewriting
		req.Header.Set("X-Original-Host", req.Host)

		// Set the Host header to the target host
		req.Host = originalTargetHost

		// Set Origin to match target host
		if req.Header.Get("Origin") != "" {
			req.Header.Set("Origin", "https://"+originalTargetHost)
		}

		// Remove duplicate Authorization headers
		if len(req.Header["Authorization"]) > 1 {
			auth := req.Header["Authorization"][0]
			req.Header.Del("Authorization")
			req.Header.Add("Authorization", auth)
		}

		// Update the request URL
		req.URL.Scheme = target.Scheme
		req.URL.Host = target.Host
		if targetQuery == "" || req.URL.RawQuery == "" {
			req.URL.RawQuery = targetQuery + req.URL.RawQuery
		} else {
			req.URL.RawQuery = targetQuery + "&" + req.URL.RawQuery
		}

		// Set X-Forwarded headers
		clientIP := req.RemoteAddr
		if colon := strings.LastIndex(clientIP, ":"); colon != -1 {
			clientIP = clientIP[:colon]
		}

		// Set standard proxy headers
		req.Header.Set("X-Real-IP", clientIP)
		req.Header.Set("X-Forwarded-For", clientIP)
		req.Header.Set("X-Forwarded-Proto", req.URL.Scheme)
		req.Header.Set("X-Forwarded-Host", req.Host)
		req.Header.Set("X-Forwarded-Server", proxyHost)
	}
}

func main() {
	// Get port from environment variable or use default
	port := os.Getenv("PORT")
	if port == "" {
		port = defaultPort
	}
	listenAddr := ":" + port

	// Parse the target URL
	target, err := url.Parse(targetHost)
	if err != nil {
		log.Fatal(err)
	}

	// Create the reverse proxy
	proxy := &httputil.ReverseProxy{
		Director: NewDirector(target),
		Transport: &NoForwardingTransport{
			transport: http.DefaultTransport,
		},
		ModifyResponse: func(resp *http.Response) error {
			if location := resp.Header.Get("Location"); location != "" {
				if strings.Contains(location, originalTargetHost) {
					newLocation := strings.Replace(location, originalTargetHost, proxyHost, 1)
					resp.Header.Set("Location", newLocation)
				}
			}
			return nil
		},
	}

	// Wrap the proxy with our logging middleware
	loggingHandler := NewLoggingMiddleware(proxy)

	// Start the server
	server := &http.Server{
		Addr:    listenAddr,
		Handler: loggingHandler,
	}

	log.Printf("Starting proxy server on %s\n", listenAddr)
	if err := server.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}
