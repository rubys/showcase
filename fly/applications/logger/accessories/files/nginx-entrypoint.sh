#!/bin/sh
# nginx startup script with automatic self-signed certificate generation

CERT_DIR="/etc/nginx/certs"
CERT_FILE="$CERT_DIR/self-signed.crt"
KEY_FILE="$CERT_DIR/self-signed.key"

# Create certificates directory
mkdir -p "$CERT_DIR"

# Install openssl if not present
if ! command -v openssl &> /dev/null; then
    echo "Installing openssl..."
    apk add --no-cache openssl
fi

# Generate self-signed certificate if it doesn't exist
if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "Generating self-signed certificate for nginx HTTPS..."
    
    openssl req -x509 -newkey rsa:4096 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -sha256 -days 3650 -nodes \
        -subj "/C=US/ST=CA/L=SF/O=Showcase/OU=Logging/CN=65.109.81.136" \
        -addext "subjectAltName=IP:65.109.81.136,DNS:hub.showcase.party"
    
    # Set appropriate permissions
    chmod 600 "$KEY_FILE"
    chmod 644 "$CERT_FILE"
    
    echo "Certificate generated successfully:"
    echo "  Certificate: $CERT_FILE"
    echo "  Private key: $KEY_FILE"
else
    echo "Using existing certificate: $CERT_FILE"
fi

# Start nginx
echo "Starting nginx with HTTP/2 and SSL..."
exec nginx -g "daemon off;"