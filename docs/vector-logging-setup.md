# Vector Logging Setup for Navigator/Showcase

## Overview

This document describes the setup for centralized logging from Fly.io machines running Navigator to a Hetzner aggregation server using Vector's native protocol. Vector is deployed as part of the logger Kamal application on Hetzner.

## Architecture

```
[Fly Machines with Navigator] → [Vector Agent] → Native Protocol → [Hetzner Server (logger.showcase.party)] → [Vector in Docker] → [Daily Log Files]
```

## 1. Navigator Configuration (Fly Machines)

### Update navigator.yml

```yaml
# Enable Vector integration in Navigator
logging:
  format: json        # Use JSON for structured logs
  file: /var/log/navigator/{{app}}.log
  vector:
    enabled: true
    socket: /tmp/navigator-vector.sock
    config: /etc/vector/navigator-vector.toml
```

### Create Vector Agent Config

File: `/etc/vector/navigator-vector.toml`

```toml
# Source - Receive from Navigator's Unix socket
[sources.navigator_socket]
type = "socket"
mode = "unix"
path = "/tmp/navigator-vector.sock"

# Sink - Send to Hetzner with authentication
[sinks.hetzner]
type = "vector"
inputs = ["navigator_socket"]
address = "logger.showcase.party:9000"
version = "2"
compression = true
buffer.type = "disk"
buffer.max_size = 268435488  # 256MB
buffer.when_full = "drop_newest"
healthcheck.enabled = true
# Authentication using existing Rails master key
tls.enabled = true
tls.verify_certificate = true
auth.strategy = "bearer"
auth.token = "${RAILS_MASTER_KEY}"  # Already set in Fly secrets
```

### Dockerfile Updates

```dockerfile
# Install Vector alongside Navigator
RUN curl -L https://repositories.timber.io/public/vector/cfg/setup/script.deb.sh | bash && \
    apt-get install -y vector

# Copy Vector config
COPY navigator-vector.toml /etc/vector/navigator-vector.toml
```

## 2. Hetzner Aggregator Setup (Kamal Deployment)

Vector is deployed as part of the logger application using Kamal. This approach:
- Runs Vector inside a Docker container managed by Kamal
- Shares the same deployment pipeline as the logger application
- Automatically manages SSL certificates via kamal-proxy
- Provides easy updates and rollbacks

### Logger Application Structure

```
fly/applications/logger/
├── Dockerfile         # Used by Kamal (includes Vector)
├── Dockerfile.fly     # Used by Fly.io (original, no Vector)
├── deploy.yml         # Kamal configuration
├── vector.toml        # Vector configuration
├── entrypoint.sh      # Starts both logger app and Vector
└── .kamal/
    └── secrets        # Contains EXPECTED_RAILS_MASTER_KEY
```

### Vector Aggregator Config (Integrated with Logger App)

File: `fly/applications/logger/vector.toml`

```toml
# Source - Receive via Vector's native protocol
[sources.vector_receiver]
type = "vector"
address = "0.0.0.0:9000"
version = "2"
connection_limit = 200  # Support up to 200 concurrent connections
keepalive.enabled = true
keepalive.time_secs = 60
# No TLS needed - runs inside Docker container
# Port 9000 is exposed by Kamal deployment
auth.strategy = "bearer"
auth.token = "${EXPECTED_RAILS_MASTER_KEY}"  # Set in Kamal secrets

# Transform - Extract date from timestamp
[transforms.add_date]
type = "remap"
inputs = ["vector_receiver"]
source = '''
.date = format_timestamp!(.["@timestamp"], "%Y-%m-%d")
'''

# Sink - Write to daily log file
[sinks.daily_logs]
type = "file"
inputs = ["add_date"]
path = "/logs/showcase/{{ date }}.log"  # Uses Kamal volume mount
encoding.codec = "json"
compression = "gzip"

# Optional: Separate error logs
[sinks.errors]
type = "file"
inputs = ["add_date"]
path = "/var/log/showcase/errors-{{ date }}.log"
encoding.codec = "json"
condition = '.stream == "stderr" || .level == "error" || .level == "ERROR"'

# Optional: Metrics for monitoring
[sinks.metrics]
type = "prometheus_exporter"
inputs = ["add_date"]
address = "127.0.0.1:9598"
default_namespace = "vector"
```

### Kamal Configuration

File: `fly/applications/logger/deploy.yml` (key sections):

```yaml
# Deploy to these servers.
servers:
  web:
    hosts:
      - 65.109.81.136
    options:
      add-host: host.docker.internal:host-gateway
      publish:
        - "9000:9000"  # Vector port for log aggregation

# Inject ENV variables into containers (secrets come from .kamal/secrets).
env:
  clear:
    KAMAL_HETZNER: 1
  secret:
    - HTPASSWD
    - EXPECTED_RAILS_MASTER_KEY

# Use a persistent storage volume.
volumes:
  - /home/rubys/logs:/logs
```

### Entrypoint Script

File: `fly/applications/logger/entrypoint.sh`:

```bash
#!/bin/bash
set -e

# Start Vector in the background
echo "Starting Vector log aggregator..."
vector --config /etc/vector/vector.toml &
VECTOR_PID=$!

# Start the main application
echo "Starting logger application..."
exec thrust bun run start
```

### Authentication Setup

Update `fly/applications/logger/.kamal/secrets`:

```bash
# Add your Rails master key here for Vector authentication
EXPECTED_RAILS_MASTER_KEY=your-actual-rails-master-key-here
```

## 3. SSL/TLS Setup (Automatic via Kamal-Proxy)

SSL certificates are automatically managed by kamal-proxy for the `logger.showcase.party` domain. No manual certificate management is required.

### How it works:
- Kamal-proxy automatically obtains Let's Encrypt certificates
- Certificates are stored in Docker volumes
- Auto-renewal is handled by kamal-proxy
- Vector runs inside the container without needing direct TLS (port 9000 is exposed by Docker)

## 4. System Tuning

### Kernel Parameters for High Connection Count

File: `/etc/sysctl.d/99-vector.conf`

```conf
# Increase max file descriptors
fs.file-max = 100000
fs.nr_open = 100000

# Network tuning for many connections
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 2048
net.core.netdev_max_backlog = 5000

# TCP keepalive settings
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# Increase network buffers
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
```

Apply settings:

```bash
sysctl -p /etc/sysctl.d/99-vector.conf
```

## 5. Log Rotation

File: `/etc/logrotate.d/showcase`

```logrotate
/var/log/showcase/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 vector vector
    sharedscripts
    postrotate
        # Optional: Upload to S3 for long-term storage
        if [ -f /usr/local/bin/upload-showcase-logs.sh ]; then
            /usr/local/bin/upload-showcase-logs.sh
        fi
    endscript
}

/var/log/showcase/errors-*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 vector vector
}
```

## 6. Monitoring Scripts

### Connection Monitor (Updated for Kamal/Docker)

File: `/usr/local/bin/check-vector-connections.sh`

```bash
#!/bin/bash
# Monitor Vector connections

echo "=== Vector Connection Status ==="
echo "Timestamp: $(date)"
echo

# Count established connections
CONNECTIONS=$(netstat -tn | grep :9000 | grep ESTABLISHED | wc -l)
echo "Active Vector connections: $CONNECTIONS"

# Show connections by source IP
echo -e "\nConnections by source:"
netstat -tn | grep :9000 | grep ESTABLISHED | \
  awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn

# Check Vector health
if systemctl is-active --quiet vector; then
    echo -e "\nVector service: Running"
else
    echo -e "\nVector service: NOT RUNNING"
fi

# Check disk usage  
echo -e "\nDisk usage:"
df -h /home/rubys/logs

# Show latest logs size
echo -e "\nToday's log size:"
ls -lh /home/rubys/logs/showcase/$(date +%Y-%m-%d).log* 2>/dev/null || echo "No logs yet today"

# Error count
if [ -f "/home/rubys/logs/showcase/errors-$(date +%Y-%m-%d).log" ]; then
    ERROR_COUNT=$(wc -l < "/home/rubys/logs/showcase/errors-$(date +%Y-%m-%d).log")
    echo -e "\nErrors today: $ERROR_COUNT"
fi

# Check Vector container status
echo -e "\nVector container status:"
docker ps | grep showcase-logger
```

Make executable:

```bash
chmod +x /usr/local/bin/check-vector-connections.sh
```

### Daily Stats Script

File: `/usr/local/bin/showcase-log-stats.sh`

```bash
#!/bin/bash
# Daily statistics for showcase logs

DATE=${1:-$(date +%Y-%m-%d)}
LOG_FILE="/var/log/showcase/${DATE}.log"

echo "=== Showcase Log Statistics for $DATE ==="
echo

if [ ! -f "$LOG_FILE" ] && [ ! -f "${LOG_FILE}.gz" ]; then
    echo "No logs found for $DATE"
    exit 1
fi

# Use zcat if file is compressed
if [ -f "${LOG_FILE}.gz" ]; then
    CAT="zcat ${LOG_FILE}.gz"
else
    CAT="cat ${LOG_FILE}"
fi

echo "Total log entries:"
$CAT | wc -l

echo -e "\nLog entries by source:"
$CAT | jq -r '.source' 2>/dev/null | sort | uniq -c | sort -rn | head -20

echo -e "\nLog entries by tenant:"
$CAT | jq -r '.tenant // "none"' 2>/dev/null | sort | uniq -c | sort -rn | head -20

echo -e "\nLog entries by stream:"
$CAT | jq -r '.stream' 2>/dev/null | sort | uniq -c | sort -rn

echo -e "\nLog entries by hour:"
$CAT | jq -r '.["@timestamp"]' 2>/dev/null | cut -dT -f2 | cut -d: -f1 | sort | uniq -c

echo -e "\nFile size:"
ls -lh "${LOG_FILE}"* 2>/dev/null
```

Make executable:

```bash
chmod +x /usr/local/bin/showcase-log-stats.sh
```

## 7. Firewall Configuration

### Hetzner Robot Firewall (Recommended)

For Hetzner Robot servers, configure firewall rules in the Robot console:

#### Option 1: Restrict to Fly.io IP ranges (Most Secure)
```
Name: Vector-Fly-Logs
Direction: In
Port: 9000
Protocol: TCP
Source IPs: 
- 66.241.124.0/24
- 66.241.125.0/24
- 66.51.124.0/24
- 66.51.125.0/24
- 161.35.39.0/24
- 149.248.212.0/24
```

#### Option 2: Allow from anywhere (For testing)
```
Name: Vector-Logs
Direction: In
Port: 9000
Protocol: TCP
Source IPs: 0.0.0.0/0
```

#### Steps to configure in Hetzner Robot:
1. Go to your server in Robot console
2. Click "Firewall" 
3. Click "Add Rule"
4. Fill in the rule details above
5. Activate the firewall

#### Get Current Fly.io IP Ranges:
```bash
# Query Fly.io API for current IP ranges
curl -s https://api.fly.io/v1/platform/regions | jq -r '.data[].ipv4_cidr' | sort -u
```

### Alternative: UFW (If not using Robot firewall)

```bash
# Allow Vector port only from Fly.io IP ranges
# Note: Get current Fly.io IP ranges from their API

# Basic UFW setup
ufw allow 22/tcp  # SSH
ufw allow 9000/tcp  # Vector
ufw enable
```

**Recommendation**: Start with Option 2 (allow all) for initial testing, then restrict to Fly.io ranges once Vector is working properly.

## 8. Deployment

### Deploy Logger Application with Vector to Hetzner

```bash
# Navigate to logger application directory
cd fly/applications/logger

# Update the RAILS_MASTER_KEY in .kamal/secrets
vim .kamal/secrets
# Replace 'your-actual-rails-master-key-here' with your actual Rails master key

# Deploy with Kamal
kamal deploy

# Check deployment status
kamal app logs
kamal app details
```

### Verify Vector is Running

```bash
# Check if Vector port is exposed
kamal app exec 'netstat -tlnp | grep 9000'

# Check Vector logs
kamal app exec 'ps aux | grep vector'

# View Vector startup logs
kamal app logs | grep -i vector
```

## 9. Testing and Verification

### Test Vector Connection from Fly

```bash
# On a Fly machine
flyctl ssh console

# Check if Vector is running
ps aux | grep vector

# Check Vector logs
journalctl -u vector -n 50

# Test connectivity to Hetzner
nc -zv logger.showcase.party 9000
```

### Test on Hetzner

```bash
# Check Vector is receiving connections
kamal app exec 'netstat -tn | grep :9000'

# Monitor incoming logs in real-time
tail -f /home/rubys/logs/showcase/$(date +%Y-%m-%d).log | jq '.'

# Check for errors
tail -f /home/rubys/logs/showcase/errors-$(date +%Y-%m-%d).log | jq '.'

# View Vector's own logs inside the container
kamal app logs | grep vector

# Check container status
docker ps | grep showcase-logger
```

## 9. Troubleshooting

### Common Issues and Solutions

1. **No connections showing**
   - Check firewall rules
   - Verify TLS certificates are valid
   - Ensure RAILS_MASTER_KEY matches on both sides

2. **High memory usage**
   - Reduce buffer sizes in Vector config
   - Check for backpressure (slow disk I/O)

3. **Missing logs**
   - Check Navigator's Vector socket is created
   - Verify Vector agent is running on Fly machines
   - Check authentication token matches

4. **Connection refused**
   - Ensure Vector is listening: `netstat -tlnp | grep 9000`
   - Check TLS certificate validity: `openssl s_client -connect logger.showcase.party:9000`

### Debug Commands

```bash
# Check Vector configuration is valid
vector validate /etc/vector/vector.toml

# Run Vector in debug mode (temporarily)
systemctl stop vector
RUST_LOG=debug vector --config /etc/vector/vector.toml

# Check system limits
ulimit -n  # Should show 65535 or higher
```

## 10. Capacity Planning

### Expected Load

- **Connections**: 20-50 concurrent (typical), up to 200 (configured limit)
- **Log volume**: ~1-10 GB/day depending on traffic
- **Disk space**: 30 days × 10 GB = 300 GB recommended
- **Network**: 100-200 Mbps typical, 500 Mbps peak

### Recommended Hetzner Server Specs

For typical deployment (5-10 regions, 3-5 machines per region):
- **CPU**: 4 cores
- **RAM**: 4 GB
- **Disk**: 500 GB SSD
- **Network**: 1 Gbps

### Monitoring Alerts

Set up alerts for:
- Disk usage > 80%
- Connection count > 150
- Vector service down
- Error rate > 100/minute
- No logs received for > 5 minutes

## 11. Security Considerations

1. **Authentication**: Uses RAILS_MASTER_KEY as bearer token
2. **Encryption**: TLS 1.2+ for all connections
3. **Firewall**: Restrict port 9000 to Fly.io IPs only
4. **File permissions**: Logs readable only by vector user
5. **Log retention**: 30 days on disk, then archive to S3
6. **No PII in logs**: Ensure Navigator doesn't log sensitive data

## 12. Next Steps

1. **Set up S3 archival** for long-term storage
2. **Add search interface** (Grafana Loki or similar)
3. **Create dashboards** for log visualization
4. **Set up alerting** for error patterns
5. **Implement log sampling** if volume becomes too high

## Appendix: Quick Setup Script

```bash
#!/bin/bash
# quick-setup-vector-hetzner.sh

set -e

echo "Setting up Vector log aggregator on Hetzner..."

# Install Vector
curl -L https://repositories.timber.io/public/vector/cfg/setup/bash.rpm.sh | bash
apt-get update
apt-get install -y vector certbot

# Create directories and user
useradd -r -s /bin/false vector || true
mkdir -p /var/log/showcase
chown -R vector:vector /var/log/showcase

# Get SSL certificate
read -p "Enter domain (e.g., logger.showcase.party): " DOMAIN
read -p "Enter email for Let's Encrypt: " EMAIL
certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL"

# Get Rails master key
read -s -p "Enter RAILS_MASTER_KEY: " RAILS_KEY
echo
echo "EXPECTED_RAILS_MASTER_KEY=$RAILS_KEY" > /etc/vector/environment
chmod 600 /etc/vector/environment

# Apply system tuning
cat > /etc/sysctl.d/99-vector.conf << 'EOF'
fs.file-max = 100000
net.core.somaxconn = 1024
net.ipv4.tcp_keepalive_time = 60
EOF
sysctl -p /etc/sysctl.d/99-vector.conf

# Create Vector config (you'll need to add the content)
echo "Please create /etc/vector/vector.toml with the configuration from this document"
echo "Then run: systemctl enable --now vector"

echo "Setup complete!"
```

---

*Last updated: 2025-01-11*
*Version: 1.0*