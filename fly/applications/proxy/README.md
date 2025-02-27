# Smooth Proxy

A specialized proxy server designed to work around iOS 17's WebKit bug with duplicate Authorization headers ([Apple Developer Forums Thread](https://forums.developer.apple.com/forums/thread/771315)) while also ensuring proper header handling for Rails CSRF origin validation.

## Background

### iOS WebKit Bug
iOS 17's WebKit has a bug where it sometimes sends duplicate Authorization headers, which can cause issues with backend services. This proxy automatically deduplicates these headers, ensuring only one Authorization header reaches the target service.

### Rails Origin Validation
Rails applications validate the Origin header against the request's base URL for CSRF protection. This proxy ensures proper header handling by:
- Setting the Host header to match the target service
- Setting the Origin header to match the target service
- Properly forwarding and managing X-Forwarded-* headers

## Features

- Forwards all requests to smooth.fly.dev
- Removes duplicate Authorization headers (iOS 17 WebKit bug fix)
- Sets proper Host and Origin headers for Rails CSRF validation
- Manages forwarding headers:
  - X-Real-IP
  - X-Forwarded-For
  - X-Forwarded-Proto
  - X-Forwarded-Server
- Rewrites Location headers in redirects
- **Request logging for monitoring and debugging:**
  - Logs all incoming requests with method, path, protocol, client IP, and user agent
  - Logs all responses with method, path, status code, and response time
  - Helps track potential issues and monitor traffic patterns

## Usage

The proxy runs on port 3000 by default but can be configured with the PORT environment variable:

```bash
# Run on default port 3000
go run main.go

# Run on custom port
PORT=8080 go run main.go
```

### Testing

You can verify the proxy's behavior using curl:

```bash
# Test duplicate Authorization headers (iOS WebKit bug fix)
curl -v -H "Authorization: Bearer token1" -H "Authorization: Bearer token2" \
  http://localhost:3000/your-path

# Test Origin header handling (Rails CSRF validation)
curl -v -H "Origin: http://localhost:3000" http://localhost:3000/your-path

# Test redirect handling
curl -v -L http://localhost:3000/your-path

# Test request logging
curl -H "User-Agent: MyCustomAgent" http://localhost:3000/your-path
# Check server logs for output like:
# REQUEST: [GET] /your-path HTTP/1.1 - From: 127.0.0.1:xxxxx - User-Agent: MyCustomAgent
# RESPONSE: [GET] /your-path - Status: 200 - Duration: xxxms
```

## Development

The proxy includes a test suite to verify its behavior:

```bash
go test -v
```

The test suite now includes verification of the logging middleware to ensure request and response details are properly captured.
