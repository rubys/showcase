# Vector Logging Setup for Navigator/Showcase

## Overview

This document describes the setup for centralized logging from Fly.io machines running Navigator to a Hetzner aggregation server using Vector's native protocol. Both Vector and Traefik run as Kamal accessories for clean container management.

## Architecture

```
[Fly Machines with Navigator] → [Vector Agent] → Native Protocol → [hub.showcase.party:9000] → [Traefik Accessory] → [Vector Accessory] → [Daily Log Files]
```

## Key Benefits of Vector + Traefik Accessories

- **Easy deployments**: Both services managed through Kamal accessories
- **Automatic certificate handling**: Traefik handles TLS termination and renewal
- **Container isolation**: Vector runs in its own Docker container
- **Consistent deployment**: All infrastructure managed through accessories
- **Simplified architecture**: No system service configuration needed

## Prerequisites

### DNS Configuration

Add DNS record for the Vector endpoint:
```
hub.showcase.party → 65.109.81.136
```

### Firewall Configuration (Hetzner Robot)

Configure Hetzner Robot firewall rules to allow Vector traffic:

1. **Log in to Hetzner Robot console**
2. **Navigate to your server** → Firewall
3. **Add firewall rule**:
   - **Name**: Vector Logging
   - **IP Version**: IPv4
   - **Protocol**: TCP  
   - **Port**: 9000
   - **Source**: Any (0.0.0.0/0) or restrict to your Fly.io IP ranges
   - **Action**: Accept

4. **Apply the firewall template** to your server

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
address = "hub.showcase.party:9000"
version = "2"
compression = true
buffer.type = "disk"
buffer.max_size = 268435488  # 256MB
buffer.when_full = "drop_newest"
healthcheck.enabled = true
# Authentication using existing Rails master key
tls.enabled = true
auth.strategy = "bearer"
auth.token = "${RAILS_MASTER_KEY}"  # Already set in Fly secrets
```

### Dockerfile Updates

```dockerfile
# Install Vector alongside Navigator
RUN curl -1sLf 'https://repositories.timber.io/public/vector/cfg/setup/bash.deb.sh' | bash && \
    apt-get update && \
    apt-get install -y vector

# Copy Vector config
COPY navigator-vector.toml /etc/vector/navigator-vector.toml
```

## 2. Hetzner Aggregator Setup (Kamal Accessories)

Both Vector and Traefik run as Kamal accessories for clean management:

### Vector Accessory Configuration

File: `fly/applications/logger/accessories/vector.yml`

```yaml
service: logger-vector
image: timberio/vector:latest
host: 65.109.81.136
volumes:
  - vector-data:/var/lib/vector
  - /home/rubys/logs:/logs
env:
  secret:
    - RAILS_MASTER_KEY
files:
  - vector.toml:/etc/vector/vector.toml
```

File: `fly/applications/logger/accessories/files/vector.toml`

```toml
# Source - Receive via Vector's native protocol (no TLS - Traefik handles it)
[sources.vector_receiver]
type = "vector"
address = "0.0.0.0:9001"  # Listen inside container, Traefik proxies to this
version = "2"
connection_limit = 200  # Support up to 200 concurrent connections
keepalive.enabled = true
keepalive.time_secs = 60
# No TLS needed - Traefik terminates TLS and forwards plain TCP to Vector
# Authentication using Rails master key
auth.strategy = "bearer"
auth.token = "${RAILS_MASTER_KEY}"

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
path = "/logs/showcase/{{ date }}.log"  # Container path
encoding.codec = "json"
compression = "gzip"

# Optional: Separate error logs
[sinks.errors]
type = "file"
inputs = ["add_date"]
path = "/logs/showcase/errors-{{ date }}.log"
encoding.codec = "json"
condition = '.stream == "stderr" || .level == "error" || .level == "ERROR"'
```

### Traefik Accessory Configuration

File: `fly/applications/logger/accessories/traefik.yml`

```yaml
service: logger-traefik
image: traefik:v3.0
host: 65.109.81.136
env:
  clear:
    TRAEFIK_DOMAIN: hub.showcase.party
port: 9000
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
  - traefik-data:/data
options:
  network: kamal
cmd: >
  --api.dashboard=false
  --entrypoints.vector.address=:9000
  --providers.file.filename=/data/traefik.yml
  --certificatesresolvers.letsencrypt.acme.tlschallenge=true
  --certificatesresolvers.letsencrypt.acme.email=rubys@intertwingly.net
  --certificatesresolvers.letsencrypt.acme.storage=/data/acme.json
  --log.level=INFO
files:
  - traefik.yml:/data/traefik.yml
```

File: `fly/applications/logger/accessories/files/traefik.yml`

```yaml
tcp:
  routers:
    vector:
      rule: "HostSNI(`hub.showcase.party`)"
      service: vector-service
      tls:
        certResolver: letsencrypt
  services:
    vector-service:
      loadBalancer:
        servers:
          - address: "logger-vector:9001"  # Vector container listening on port 9001
```

### Deploy Both Accessories

```bash
# Deploy both accessories (run from your project directory)
cd fly/applications/logger

# Deploy Vector first
kamal accessory boot vector -c deploy.yml

# Deploy Traefik  
kamal accessory boot traefik -c deploy.yml

# Check status
kamal accessory details vector -c deploy.yml
kamal accessory details traefik -c deploy.yml

# View logs
kamal accessory logs vector -c deploy.yml
kamal accessory logs traefik -c deploy.yml
```

## 3. Authentication Setup

The RAILS_MASTER_KEY is automatically sourced from your Rails application:

- **Source**: `config/master.key` (your Rails application's master key)
- **Configuration**: `.kamal/secrets` extracts it with `$(cat ../../../config/master.key)`
- **Usage**: Vector accessory receives it as an environment variable
- **No manual setup needed** - already configured in the accessory files

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
/home/rubys/logs/showcase/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    sharedscripts
    postrotate
        # Optional: Upload to S3 for long-term storage
        if [ -f /usr/local/bin/upload-showcase-logs.sh ]; then
            /usr/local/bin/upload-showcase-logs.sh
        fi
    endscript
}

/home/rubys/logs/showcase/errors-*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
```

## 6. Monitoring Scripts

### Connection Monitor

File: `/usr/local/bin/check-vector-connections.sh`

```bash
#!/bin/bash
# Monitor Vector connections

echo "=== Vector Connection Status ==="
echo "Timestamp: $(date)"
echo

# Count established connections to Traefik (port 9000)
TRAEFIK_CONNECTIONS=$(netstat -tn | grep :9000 | grep ESTABLISHED | wc -l)
echo "Active Traefik connections: $TRAEFIK_CONNECTIONS"

# Check Vector container connections (internal to Docker)
echo "Vector container connections: $(docker exec logger-vector netstat -tn 2>/dev/null | grep :9001 | grep ESTABLISHED | wc -l 2>/dev/null || echo 'N/A')"

# Show connections by source IP
echo -e "\nTraefik connections by source:"
netstat -tn | grep :9000 | grep ESTABLISHED | \
  awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn

# Check Vector accessory health
echo -e "\nVector accessory status:"
docker ps --filter "name=logger-vector" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check disk usage for logs
echo -e "\nDisk usage:"
df -h /home/rubys/logs/showcase
```

Make executable:

```bash
chmod +x /usr/local/bin/check-vector-connections.sh
```

## 7. Testing the Setup

### Basic Connection Test

Use the included test script to verify connectivity:

```bash
# Test Vector connectivity from development machine
ruby test-vector.rb
```

### Check Log Files

```bash
# SSH to the Hetzner server and check log files
ssh root@65.109.81.136

# Check today's log file
today=$(date +%Y-%m-%d)
ls -la /home/rubys/logs/showcase/${today}.log*

# View recent log entries
tail -f /home/rubys/logs/showcase/${today}.log | jq .
```

### Monitor Vector Performance

```bash
# Run the connection monitoring script
/usr/local/bin/check-vector-connections.sh

# Check Vector accessory logs
cd fly/applications/logger
kamal accessory logs vector -c deploy.yml --lines 100

# Check Traefik accessory logs  
kamal accessory logs traefik -c deploy.yml --lines 100
```

## 8. Maintenance Commands

### Update Vector Version

```bash
cd fly/applications/logger

# Update image version in accessories/vector.yml, then:
kamal accessory reboot vector -c deploy.yml
```

### Restart Services

```bash
# Restart Vector accessory
kamal accessory restart vector -c deploy.yml

# Restart Traefik accessory  
kamal accessory restart traefik -c deploy.yml
```

### Remove Services

```bash
# Remove accessories (if needed)
kamal accessory remove vector -c deploy.yml
kamal accessory remove traefik -c deploy.yml
```