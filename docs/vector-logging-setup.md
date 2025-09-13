# Vector Logging Setup for Navigator/Showcase

## Overview

This document describes the setup for centralized logging from Fly.io machines running Navigator to a Hetzner aggregation server using Vector's native v2 protocol (gRPC). Vector runs as a Kamal accessory for clean container management.

## Architecture

```
[Fly Machines with Navigator] → [Vector Agent] → gRPC v2 Protocol → [65.109.81.136:9000] → [Vector Accessory] → [Daily Log Files]
```

## Key Benefits of Vector gRPC Protocol

- **High performance**: Binary protocol with compression and multiplexing
- **Reliable delivery**: Built-in acknowledgements and backpressure handling
- **Efficient**: Lower CPU and bandwidth usage compared to JSON over HTTP
- **Native streaming**: Bidirectional gRPC streams for optimal throughput
- **Container isolation**: Vector runs in its own Docker container via Kamal

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

# Sink - Send to Hetzner via gRPC v2
[sinks.hetzner]
type = "vector"
inputs = ["navigator_socket"]
address = "65.109.81.136:9000"
version = "2"
compression = true
buffer.type = "disk"
buffer.max_size = 268435488  # 256MB
buffer.when_full = "drop_newest"
healthcheck.enabled = true
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

## 2. Hetzner Aggregator Setup (Kamal Accessory)

Vector runs as a Kamal accessory, listening directly on port 9000 for gRPC connections:

### Vector Accessory Configuration

Configuration in `fly/applications/logger/deploy.yml`:

```yaml
accessories:
  vector:
    service: logger-vector
    image: timberio/vector:0.49.0-debian
    host: 65.109.81.136
    port: "9000:9000"
    volumes:
      - vector-data:/var/lib/vector
      - /home/rubys/logs:/logs
    env:
      secret:
        - RAILS_MASTER_KEY
    files:
      - accessories/files/vector.toml:/etc/vector/vector.toml
    cmd: --config /etc/vector/vector.toml
```

File: `fly/applications/logger/accessories/files/vector.toml`

```toml
# Source - Receive via Vector's native protocol v2 (gRPC)
[sources.vector_receiver]
type = "vector"
address = "0.0.0.0:9000"  # Listen directly on port 9000
version = "2"

# Transform - Extract date from timestamp
[transforms.add_date]
type = "remap"
inputs = ["vector_receiver"]
source = '''
.date = format_timestamp!(."@timestamp", "%Y-%m-%d")
'''

# Sink - Write to daily log file
[sinks.daily_logs]
type = "file"
inputs = ["add_date"]
path = "/logs/showcase/{{ date }}.log"  # Container path
encoding.codec = "json"
compression = "gzip"

# Optional: Filter for errors
[transforms.filter_errors]
type = "filter"
inputs = ["add_date"]
condition = '.stream == "stderr" || .level == "error" || .level == "ERROR"'

# Separate error logs
[sinks.errors]
type = "file"
inputs = ["filter_errors"]
path = "/logs/showcase/errors-{{ date }}.log"
encoding.codec = "json"
```

### Deploy Vector Accessory

```bash
# Deploy Vector accessory (run from your project directory)
cd fly/applications/logger

# Deploy Vector
kamal accessory boot vector -c deploy.yml

# Check status
kamal accessory details vector -c deploy.yml

# View logs
kamal accessory logs vector -c deploy.yml
```

## 3. Configuration Setup

### Secrets Configuration

The Vector accessory receives the RAILS_MASTER_KEY from your application:

- **Source**: `config/master.key` (your Rails application's master key)
- **Configuration**: `.kamal/secrets` extracts it with `$(cat ../../../config/master.key)`
- **Usage**: Available to Vector accessory as environment variable

Note: Currently the Vector receiver is configured without authentication for simplicity. For production use, you may want to add authentication or network-level security.

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

# Count established connections to Vector (port 9000)
VECTOR_CONNECTIONS=$(netstat -tn | grep :9000 | grep ESTABLISHED | wc -l)
echo "Active Vector connections: $VECTOR_CONNECTIONS"

# Show connections by source IP
echo -e "\nVector connections by source:"
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

### Local Vector Client Test

Install Vector locally for testing:

```bash
# Install Vector on macOS
curl --proto '=https' --tlsv1.2 -sSfL https://sh.vector.dev | bash -s -- -y
```

Use the included test configuration to verify connectivity:

```bash
# Run test with local Vector client (sends 10 demo events)
~/.vector/bin/vector --config test-vector-client.toml
```

Test configuration file (`test-vector-client.toml`):

```toml
# Source - Generate test events
[sources.demo]
type = "demo_logs"
format = "json"
interval = 1.0
count = 10

# Transform - Add test metadata
[transforms.add_metadata]
type = "remap"
inputs = ["demo"]
source = '''
.app = "test-vector-client"
.host = get_hostname!()
.test = true
."@timestamp" = now()
'''

# Sink - Send to Hetzner Vector via gRPC
[sinks.hetzner]
type = "vector"
inputs = ["add_metadata"]
address = "65.109.81.136:9000"
version = "2"
compression = true
buffer.type = "memory"
buffer.max_events = 500
buffer.when_full = "block"
healthcheck.enabled = true
acknowledgements.enabled = false
```

### Check Log Files

```bash
# SSH to the Hetzner server and check log files
ssh root@65.109.81.136

# Check today's log file (compressed)
today=$(date +%Y-%m-%d)
ls -la /home/rubys/logs/showcase/${today}.log

# View recent log entries (decompressed)
zcat /home/rubys/logs/showcase/${today}.log | tail -10
```

### Monitor Vector Performance

```bash
# Run the connection monitoring script
/usr/local/bin/check-vector-connections.sh

# Check Vector accessory logs
cd fly/applications/logger
kamal accessory logs vector -c deploy.yml --lines 100
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
```

### Remove Services

```bash
# Remove Vector accessory (if needed)
kamal accessory remove vector -c deploy.yml

# Clean up any orphaned resources
kamal prune all -c deploy.yml
```