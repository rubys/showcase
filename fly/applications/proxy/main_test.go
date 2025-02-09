package main

import (
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
		// Get all Authorization headers from the request
		authHeaders := r.Header.Values("Authorization")
		
		// Verify we only have one Authorization header
		if len(authHeaders) != 1 {
			t.Errorf("Expected exactly one Authorization header, got %d", len(authHeaders))
		}
		
		w.WriteHeader(http.StatusOK)
	}))
	defer testServer.Close()

	// Create a test request with duplicate Authorization headers
	req := httptest.NewRequest("GET", "/test", nil)
	req.Header.Add("Authorization", "Bearer token1")
	req.Header.Add("Authorization", "Bearer token2")

	// Create a response recorder
	rr := httptest.NewRecorder()

	// Create and run our proxy
	target, _ := url.Parse(testServer.URL)
	proxy := httputil.NewSingleHostReverseProxy(target)
	defaultDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		defaultDirector(req)
		authHeaders := req.Header.Values("Authorization")
		if len(authHeaders) > 1 {
			req.Header.Del("Authorization")
			req.Header.Set("Authorization", authHeaders[0])
		}
	}

	proxy.ServeHTTP(rr, req)

	// Check response status
	if status := rr.Code; status != http.StatusOK {
		t.Errorf("Handler returned wrong status code: got %v want %v", status, http.StatusOK)
	}
}

func TestLocationHeaderRewrite(t *testing.T) {
	// Create a test server that returns a redirect
	testServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Location", "https://smooth.fly.dev/some/path")
		w.WriteHeader(http.StatusTemporaryRedirect)
	}))
	defer testServer.Close()

	// Create a test request
	req := httptest.NewRequest("GET", "/test", nil)

	// Create a response recorder
	rr := httptest.NewRecorder()

	// Create and run our proxy
	target, _ := url.Parse(testServer.URL)
	proxy := httputil.NewSingleHostReverseProxy(target)
	
	// Set up the director
	defaultDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		defaultDirector(req)
	}

	// Set up the response modifier
	proxy.ModifyResponse = func(resp *http.Response) error {
		if resp.StatusCode >= 300 && resp.StatusCode < 400 {
			location := resp.Header.Get("Location")
			if location != "" {
				newLocation := strings.Replace(location, "smooth.fly.dev", "smooth-proxy.fly.dev", 1)
				resp.Header.Set("Location", newLocation)
			}
		}
		return nil
	}

	proxy.ServeHTTP(rr, req)

	// Check response status
	if status := rr.Code; status != http.StatusTemporaryRedirect {
		t.Errorf("Handler returned wrong status code: got %v want %v", 
			status, http.StatusTemporaryRedirect)
	}

	// Check Location header
	location := rr.Header().Get("Location")
	expectedLocation := "https://smooth-proxy.fly.dev/some/path"
	if location != expectedLocation {
		t.Errorf("Wrong Location header: got %v want %v", 
			location, expectedLocation)
	}
}

