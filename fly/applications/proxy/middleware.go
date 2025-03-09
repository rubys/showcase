package main

import (
	"log"
	"net/http"
	"time"
)

// LoggingMiddleware is a middleware that logs request details
type LoggingMiddleware struct {
	next http.Handler
}

// NewLoggingMiddleware creates a new logging middleware
func NewLoggingMiddleware(next http.Handler) *LoggingMiddleware {
	return &LoggingMiddleware{next: next}
}

// ServeHTTP implements the http.Handler interface
func (m *LoggingMiddleware) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Log the request details
	start := time.Now()
	log.Printf("REQUEST: [%s] %s %s - From: %s - User-Agent: %s",
		r.Method,
		r.URL.Path,
		r.Proto,
		r.RemoteAddr,
		r.UserAgent(),
	)

	// Create a response wrapper to capture status code
	rw := &responseWriter{
		ResponseWriter: w,
		statusCode:     http.StatusOK, // Default to 200 OK
	}

	// Call the next handler
	m.next.ServeHTTP(rw, r)

	// Log the response details
	duration := time.Since(start)
	log.Printf("RESPONSE: [%s] %s - Status: %d - Duration: %v",
		r.Method,
		r.URL.Path,
		rw.statusCode,
		duration,
	)
}

// responseWriter is a wrapper for http.ResponseWriter that captures the status code
type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

// WriteHeader captures the status code before writing it
func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}
