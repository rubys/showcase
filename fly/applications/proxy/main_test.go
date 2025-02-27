package main

import (
	"bytes"
	"log"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"net/url"
	"strings"
	"testing"
)

func TestProxyHeaderDeduplication(t *testing.T) {
	// Create a test server that will act as our target
	testServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Test Origin header rewriting
		if origin := r.Header.Get("Origin"); origin != "" {
			expectedOrigin := "https://smooth.fly.dev"
			if origin != expectedOrigin {
				t.Errorf("Expected Origin header to be %q, got %q", expectedOrigin, origin)
			}
		}

		// Test Host header
		expectedHost := "smooth.fly.dev"
		if r.Host != expectedHost {
			t.Errorf("Expected Host header to be %q, got %q", expectedHost, r.Host)
		}

		// Test Authorization header deduplication
		authHeaders := r.Header.Values("Authorization")
		if len(authHeaders) != 1 {
			t.Errorf("Expected exactly one Authorization header, got %d", len(authHeaders))
		}

		// Send redirect response to test Location header rewriting
		w.Header().Set("Location", "https://smooth.fly.dev/redirected")
		w.WriteHeader(http.StatusFound)
	}))
	defer testServer.Close()

	// Parse the test server URL
	targetURL, err := url.Parse(testServer.URL)
	if err != nil {
		t.Fatal(err)
	}

	proxy := &httputil.ReverseProxy{
		Director: NewDirector(targetURL),
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

	// Create a test request with duplicate headers
	req := httptest.NewRequest("GET", targetURL.String()+"/test", nil)
	req.Header.Add("Authorization", "Bearer token1")
	req.Header.Add("Authorization", "Bearer token2")
	req.Header.Set("Origin", "http://original-site.com")
	req.RemoteAddr = "192.168.1.1:12345"

	// Record the response
	w := httptest.NewRecorder()
	proxy.ServeHTTP(w, req)

	resp := w.Result()
	if resp.Header.Get("Location") != "https://smooth-proxy.fly.dev/redirected" {
		t.Errorf("Expected Location header to be rewritten to smooth-proxy.fly.dev, got %q", resp.Header.Get("Location"))
	}
}

// TestLoggingMiddleware verifies that the logging middleware properly logs request and response information
func TestLoggingMiddleware(t *testing.T) {
	// Create a handler that returns a 200 status
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Wrap it with our logging middleware
	loggingHandler := NewLoggingMiddleware(handler)

	// Create a test request
	req := httptest.NewRequest("GET", "http://example.com/test-path", nil)
	req.Header.Set("User-Agent", "test-agent")
	req.RemoteAddr = "192.168.1.1:12345"

	// Capture log output
	var buf bytes.Buffer
	log.SetOutput(&buf)
	defer log.SetOutput(nil) // Reset log output

	// Record the response
	w := httptest.NewRecorder()
	loggingHandler.ServeHTTP(w, req)

	// Check the response
	resp := w.Result()
	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status code %d, got %d", http.StatusOK, resp.StatusCode)
	}

	// Verify log output contains expected information
	logOutput := buf.String()
	
	// Check request logging
	if !strings.Contains(logOutput, "REQUEST: [GET] /test-path HTTP/1.1") {
		t.Errorf("Expected request method and path to be logged, got: %s", logOutput)
	}
	if !strings.Contains(logOutput, "From: 192.168.1.1:12345") {
		t.Errorf("Expected client IP to be logged, got: %s", logOutput)
	}
	if !strings.Contains(logOutput, "User-Agent: test-agent") {
		t.Errorf("Expected User-Agent to be logged, got: %s", logOutput)
	}

	// Check response logging
	if !strings.Contains(logOutput, "RESPONSE: [GET] /test-path - Status: 200") {
		t.Errorf("Expected response status to be logged, got: %s", logOutput)
	}
	if !strings.Contains(logOutput, "Duration:") {
		t.Errorf("Expected response duration to be logged, got: %s", logOutput)
	}
}
