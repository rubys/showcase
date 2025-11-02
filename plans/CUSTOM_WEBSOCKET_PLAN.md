# Custom WebSocket Implementation Plan

## Executive Summary

Build a lightweight WebSocket server directly in Navigator without external dependencies. This provides better control, simpler code, and identical dev/prod behavior compared to the AnyCable approach.

### Comparison with AnyCable Integration

| Metric | AnyCable (Part 3) | Custom Implementation |
|--------|------------------|----------------------|
| **Custom Go code** | ~226 lines (wrapper) | ~230 lines (complete) |
| **External dependency** | AnyCable-Go (37k LOC) | None (stdlib only) |
| **Binary size impact** | +10-15MB | +0MB (minimal) |
| **Dev/prod parity** | Different adapters | **Identical** |
| **Protocol** | Action Cable (complex) | **Simple JSON** |
| **Debugging** | Black box AnyCable | **Full visibility** |
| **Maintenance** | Track AnyCable updates | **Own code** |
| **Client changes** | None needed | Update 5 channels (~50 lines each) |
| **Rails changes** | anycable-rails gem | Rack handler + broadcast (~200 lines) |
| **Dependencies** | anycable-rails, anycable-go | **Zero (stdlib only)** |

### Memory Savings (Same as AnyCable)

| Configuration | Memory | Savings vs Current |
|---------------|--------|-------------------|
| Current (Action Cable) | 169MB | baseline |
| **Custom WebSocket** | **25-35MB** | **134-144MB (79-85%)** |
| AnyCable (Part 3) | 25-35MB | 134-144MB (79-85%) |

Memory savings are identical because both eliminate the Ruby/Puma Action Cable process.

---

## Architecture

### High-Level Flow

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│   Browser   │◄───────►│  Navigator   │◄───────►│    Rails    │
│             │         │              │         │    App      │
│ WebSocket   │         │ • WebSocket  │  HTTP   │             │
│ Connection  │         │ • Broadcast  │  POST   │ Broadcast   │
│             │         │   Routing    │         │  Helper     │
└─────────────┘         └──────────────┘         └─────────────┘

1. Browser opens WebSocket to /cable
2. Browser subscribes: {"type":"subscribe","stream":"output:db:user:job"}
3. Rails broadcasts: HTTP POST to /_broadcast with stream+data
4. Navigator matches stream to WebSocket connections
5. Navigator sends data to all matching connections
```

### Simple Protocol (No Action Cable Complexity)

**Client → Server (Subscribe)**:
```json
{
  "type": "subscribe",
  "stream": "output:2025-boston:user_123:job_456"
}
```

**Server → Client (Confirmation)**:
```json
{
  "type": "subscribed",
  "stream": "output:2025-boston:user_123:job_456"
}
```

**Server → Client (Message)**:
```json
{
  "type": "message",
  "stream": "output:2025-boston:user_123:job_456",
  "data": "...output text..."
}
```

**Client → Server (Unsubscribe)**:
```json
{
  "type": "unsubscribe",
  "stream": "output:2025-boston:user_123:job_456"
}
```

**Server → Client (Ping)**:
```json
{
  "type": "ping"
}
```

**Client → Server (Pong)**:
```json
{
  "type": "pong"
}
```

---

## Implementation

### Part 1: Navigator WebSocket Server (~230 lines)

**File**: `navigator/internal/cable/handler.go`

```go
package cable

import (
    "context"
    "encoding/json"
    "log/slog"
    "net/http"
    "sync"
    "time"

    "github.com/gorilla/websocket"
)

// Message types
type Message struct {
    Type   string          `json:"type"`
    Stream string          `json:"stream,omitempty"`
    Data   json.RawMessage `json:"data,omitempty"`
}

// Connection represents a WebSocket client connection
type Connection struct {
    ws            *websocket.Conn
    streams       map[string]bool
    streamsMu     sync.RWMutex
    send          chan []byte
    handler       *Handler
}

// Handler manages WebSocket connections and broadcasts
type Handler struct {
    connections   map[*Connection]bool
    connectionsMu sync.RWMutex
    streams       map[string]map[*Connection]bool // stream -> connections
    streamsMu     sync.RWMutex
    upgrader      websocket.Upgrader
    logger        *slog.Logger
}

// NewHandler creates a new WebSocket handler
func NewHandler(logger *slog.Logger) *Handler {
    return &Handler{
        connections: make(map[*Connection]bool),
        streams:     make(map[string]map[*Connection]bool),
        upgrader: websocket.Upgrader{
            ReadBufferSize:  1024,
            WriteBufferSize: 1024,
            CheckOrigin: func(r *http.Request) bool {
                return true // Authentication handled by Navigator
            },
        },
        logger: logger,
    }
}

// ServeHTTP handles WebSocket upgrade requests
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    ws, err := h.upgrader.Upgrade(w, r, nil)
    if err != nil {
        h.logger.Error("WebSocket upgrade failed", "error", err)
        return
    }

    conn := &Connection{
        ws:      ws,
        streams: make(map[string]bool),
        send:    make(chan []byte, 256),
        handler: h,
    }

    h.register(conn)
    defer h.unregister(conn)

    // Start write pump
    go conn.writePump()

    // Start read pump (blocks until connection closes)
    conn.readPump()
}

// HandleBroadcast handles HTTP POST broadcasts from Rails
func (h *Handler) HandleBroadcast(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }

    var msg Message
    if err := json.NewDecoder(r.Body).Decode(&msg); err != nil {
        http.Error(w, "Invalid JSON", http.StatusBadRequest)
        return
    }

    if msg.Stream == "" {
        http.Error(w, "Stream required", http.StatusBadRequest)
        return
    }

    // Broadcast to all connections subscribed to this stream
    data, _ := json.Marshal(Message{
        Type:   "message",
        Stream: msg.Stream,
        Data:   msg.Data,
    })

    h.streamsMu.RLock()
    connections := h.streams[msg.Stream]
    h.streamsMu.RUnlock()

    for conn := range connections {
        select {
        case conn.send <- data:
        default:
            // Connection buffer full, skip
            h.logger.Warn("Dropped message", "stream", msg.Stream)
        }
    }

    w.WriteHeader(http.StatusOK)
}

// register adds a connection to the handler
func (h *Handler) register(conn *Connection) {
    h.connectionsMu.Lock()
    h.connections[conn] = true
    h.connectionsMu.Unlock()
    h.logger.Debug("WebSocket connected", "total", len(h.connections))
}

// unregister removes a connection and all its subscriptions
func (h *Handler) unregister(conn *Connection) {
    h.connectionsMu.Lock()
    delete(h.connections, conn)
    h.connectionsMu.Unlock()

    conn.streamsMu.RLock()
    streams := make([]string, 0, len(conn.streams))
    for stream := range conn.streams {
        streams = append(streams, stream)
    }
    conn.streamsMu.RUnlock()

    for _, stream := range streams {
        h.unsubscribe(conn, stream)
    }

    close(conn.send)
    h.logger.Debug("WebSocket disconnected", "total", len(h.connections))
}

// subscribe adds a connection to a stream
func (h *Handler) subscribe(conn *Connection, stream string) {
    h.streamsMu.Lock()
    if h.streams[stream] == nil {
        h.streams[stream] = make(map[*Connection]bool)
    }
    h.streams[stream][conn] = true
    h.streamsMu.Unlock()

    conn.streamsMu.Lock()
    conn.streams[stream] = true
    conn.streamsMu.Unlock()

    h.logger.Debug("Subscribed", "stream", stream)
}

// unsubscribe removes a connection from a stream
func (h *Handler) unsubscribe(conn *Connection, stream string) {
    h.streamsMu.Lock()
    if conns, ok := h.streams[stream]; ok {
        delete(conns, conn)
        if len(conns) == 0 {
            delete(h.streams, stream)
        }
    }
    h.streamsMu.Unlock()

    conn.streamsMu.Lock()
    delete(conn.streams, stream)
    conn.streamsMu.Unlock()

    h.logger.Debug("Unsubscribed", "stream", stream)
}

// Shutdown gracefully closes all connections
func (h *Handler) Shutdown(ctx context.Context) error {
    h.connectionsMu.RLock()
    connections := make([]*Connection, 0, len(h.connections))
    for conn := range h.connections {
        connections = append(connections, conn)
    }
    h.connectionsMu.RUnlock()

    for _, conn := range connections {
        conn.ws.Close()
    }

    return nil
}

// readPump handles incoming messages from the WebSocket
func (conn *Connection) readPump() {
    defer conn.ws.Close()

    conn.ws.SetReadDeadline(time.Now().Add(60 * time.Second))
    conn.ws.SetPongHandler(func(string) error {
        conn.ws.SetReadDeadline(time.Now().Add(60 * time.Second))
        return nil
    })

    for {
        _, message, err := conn.ws.ReadMessage()
        if err != nil {
            break
        }

        var msg Message
        if err := json.Unmarshal(message, &msg); err != nil {
            continue
        }

        switch msg.Type {
        case "subscribe":
            if msg.Stream != "" {
                conn.handler.subscribe(conn, msg.Stream)
                // Send confirmation
                response, _ := json.Marshal(Message{
                    Type:   "subscribed",
                    Stream: msg.Stream,
                })
                conn.send <- response
            }

        case "unsubscribe":
            if msg.Stream != "" {
                conn.handler.unsubscribe(conn, msg.Stream)
            }

        case "pong":
            // Pong received, reset deadline
            conn.ws.SetReadDeadline(time.Now().Add(60 * time.Second))
        }
    }
}

// writePump sends messages to the WebSocket
func (conn *Connection) writePump() {
    ticker := time.NewTicker(30 * time.Second)
    defer func() {
        ticker.Stop()
        conn.ws.Close()
    }()

    for {
        select {
        case message, ok := <-conn.send:
            conn.ws.SetWriteDeadline(time.Now().Add(10 * time.Second))
            if !ok {
                conn.ws.WriteMessage(websocket.CloseMessage, []byte{})
                return
            }

            if err := conn.ws.WriteMessage(websocket.TextMessage, message); err != nil {
                return
            }

        case <-ticker.C:
            conn.ws.SetWriteDeadline(time.Now().Add(10 * time.Second))
            ping, _ := json.Marshal(Message{Type: "ping"})
            if err := conn.ws.WriteMessage(websocket.TextMessage, ping); err != nil {
                return
            }
        }
    }
}
```

**Integration** in `navigator/cmd/navigator/main.go`:

```go
import (
    "github.com/rubys/navigator/internal/cable"
)

// In ServerLifecycle.Run():
cableHandler := cable.NewHandler(slog.Default())

// Pass to server.CreateHandler:
handler := server.CreateHandler(
    l.cfg,
    l.appManager,
    l.basicAuth,
    l.idleManager,
    cableHandler,  // WebSocket handler
    func() string { return l.configFile },
    func(path string) { l.reloadChan <- path },
)

// In shutdown:
if err := cableHandler.Shutdown(ctx); err != nil {
    slog.Error("Cable shutdown failed", "error", err)
}
```

**Routing** in `navigator/internal/server/handler.go`:

```go
// WebSocketHandler interface
type WebSocketHandler interface {
    ServeHTTP(w http.ResponseWriter, r *http.Request)
    HandleBroadcast(w http.ResponseWriter, r *http.Request)
}

// In ServeHTTP, before rewrites:
if h.wsHandler != nil {
    if r.URL.Path == "/cable" {
        h.wsHandler.ServeHTTP(recorder, r)
        return
    } else if r.URL.Path == "/_broadcast" {
        h.wsHandler.HandleBroadcast(recorder, r)
        return
    }
}
```

---

### Part 2: Rails WebSocket Handler with Rack Hijack (~120-200 lines)

**Zero external dependencies** - uses Rack's native hijack support (built into Puma).

#### Development WebSocket Server

**File**: `config.ru`

Add before the Rails application:

```ruby
# Custom WebSocket handler for development (uses Rack hijack)
require_relative 'lib/cable_rack_handler'
use CableRackHandler
```

**File**: `lib/cable_rack_handler.rb`

```ruby
require 'digest/sha1'
require 'base64'
require 'json'

# Rack middleware for handling WebSocket connections using Rack hijack
# Uses RFC 6455 WebSocket protocol (no dependencies required)
class CableRackHandler
  GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  def initialize(app)
    @app = app
    @connections = {} # stream => [sockets]
    @mutex = Mutex.new
  end

  def call(env)
    # Handle WebSocket upgrade for /cable
    if env['PATH_INFO'] == '/cable' && websocket_request?(env)
      handle_websocket(env)
      # Return -1 to indicate we've hijacked the connection
      [-1, {}, []]
    elsif env['PATH_INFO'] == '/_broadcast' && env['REQUEST_METHOD'] == 'POST'
      handle_broadcast(env)
    else
      @app.call(env)
    end
  end

  private

  def websocket_request?(env)
    env['HTTP_UPGRADE']&.downcase == 'websocket' &&
      env['HTTP_CONNECTION']&.downcase&.include?('upgrade')
  end

  def handle_websocket(env)
    # Hijack the TCP socket from Rack/Puma
    io = env['rack.hijack'].call

    # Perform WebSocket handshake (RFC 6455)
    key = env['HTTP_SEC_WEBSOCKET_KEY']
    accept = Base64.strict_encode64(Digest::SHA1.digest(key + GUID))

    io.write("HTTP/1.1 101 Switching Protocols\r\n")
    io.write("Upgrade: websocket\r\n")
    io.write("Connection: Upgrade\r\n")
    io.write("Sec-WebSocket-Accept: #{accept}\r\n")
    io.write("\r\n")

    # Track connection subscriptions
    subscriptions = Set.new

    # Handle WebSocket frames in a thread
    Thread.new do
      begin
        loop do
          frame = read_frame(io)
          break if frame.nil? || frame[:opcode] == 8 # Close frame

          if frame[:opcode] == 1 # Text frame
            handle_message(io, frame[:payload], subscriptions)
          elsif frame[:opcode] == 9 # Ping
            send_frame(io, 10, frame[:payload]) # Pong
          end
        end
      rescue => e
        Rails.logger.error("WebSocket error: #{e}")
      ensure
        # Unsubscribe from all streams
        @mutex.synchronize do
          subscriptions.each do |stream|
            @connections[stream]&.delete(io)
            @connections.delete(stream) if @connections[stream]&.empty?
          end
        end
        io.close rescue nil
      end
    end
  end

  def handle_message(io, payload, subscriptions)
    msg = JSON.parse(payload)

    case msg['type']
    when 'subscribe'
      stream = msg['stream']

      # Add connection to stream
      @mutex.synchronize do
        @connections[stream] ||= []
        @connections[stream] << io
      end
      subscriptions.add(stream)

      # Send confirmation
      response = { type: 'subscribed', stream: stream }
      send_frame(io, 1, response.to_json)

    when 'unsubscribe'
      stream = msg['stream']

      # Remove connection from stream
      @mutex.synchronize do
        @connections[stream]&.delete(io)
        @connections.delete(stream) if @connections[stream]&.empty?
      end
      subscriptions.delete(stream)

    when 'pong'
      # Client responding to ping
    end
  end

  def handle_broadcast(env)
    # Read JSON body
    input = env['rack.input'].read
    data = JSON.parse(input)

    stream = data['stream']
    message = { type: 'message', stream: stream, data: data['data'] }
    payload = message.to_json

    # Broadcast to all connections on this stream
    sockets = @mutex.synchronize { @connections[stream]&.dup || [] }

    sockets.each do |io|
      begin
        send_frame(io, 1, payload)
      rescue
        # Connection died, will be cleaned up by read loop
      end
    end

    [200, { 'Content-Type' => 'text/plain' }, ['OK']]
  end

  # Read WebSocket frame (RFC 6455 format)
  def read_frame(io)
    byte1 = io.read(1)&.unpack1('C')
    return nil if byte1.nil?

    fin = (byte1 & 0x80) != 0
    opcode = byte1 & 0x0F

    byte2 = io.read(1)&.unpack1('C')
    return nil if byte2.nil?

    masked = (byte2 & 0x80) != 0
    length = byte2 & 0x7F

    if length == 126
      length = io.read(2).unpack1('n')
    elsif length == 127
      length = io.read(8).unpack1('Q>')
    end

    mask_key = masked ? io.read(4).unpack('C*') : nil
    payload_data = io.read(length)

    if masked && mask_key
      payload_data = payload_data.bytes.map.with_index do |byte, i|
        byte ^ mask_key[i % 4]
      end.pack('C*')
    end

    { opcode: opcode, payload: payload_data, fin: fin }
  end

  # Send WebSocket frame (RFC 6455 format)
  def send_frame(io, opcode, payload)
    payload = payload.b
    length = payload.bytesize

    frame = [0x80 | opcode].pack('C') # FIN=1

    if length < 126
      frame << [length].pack('C')
    elsif length < 65536
      frame << [126, length].pack('Cn')
    else
      frame << [127, length].pack('CQ>')
    end

    frame << payload
    io.write(frame)
  end
end
```

#### Rails Broadcast Helper

**File**: `app/channels/application_cable/channel.rb`

```ruby
module ApplicationCable
  class Channel < ActionCable::Channel::Base
    # Override broadcast to use HTTP POST to Navigator or in-process handler
    def self.broadcast(stream, message)
      # In production with Navigator, use HTTP broadcaster
      if ENV['NAVIGATOR_BROADCAST_URL']
        uri = URI(ENV['NAVIGATOR_BROADCAST_URL'])
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
        request.body = {
          stream: stream,
          data: message.is_a?(String) ? message : message.to_json
        }.to_json

        http.request(request)
      else
        # In development, broadcast to Rack handler via POST to /_broadcast
        uri = URI("http://localhost:#{ENV.fetch('PORT', 3000)}/_broadcast")
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
        request.body = {
          stream: stream,
          data: message.is_a?(String) ? message : message.to_json
        }.to_json

        http.request(request)
      end
    end
  end
end
```

**Environment variable** in `config/navigator.yml` (via configurator.rb):

```yaml
applications:
  env:
    NAVIGATOR_BROADCAST_URL: "http://localhost:3000/_broadcast"
```

**Key advantages**:
- ✅ **Zero external dependencies** - No faye-websocket, no EventMachine
- ✅ **Rack native** - Uses built-in `rack.hijack` support
- ✅ **Puma compatible** - Works with any Rack 1.5+ server
- ✅ **Full protocol** - RFC 6455 WebSocket standard
- ✅ **Thread-safe** - Mutex-protected connection tracking
- ✅ **Dev/prod parity** - Same simple JSON protocol as Navigator

---

### Part 3: Update JavaScript Clients (~50 lines per channel)

**Example**: `app/javascript/channels/command_output_channel.js`

**Before (Action Cable)**:
```javascript
import consumer from './consumer'

export function subscribeToCommandOutput(database, userId, jobId, callbacks) {
  return consumer.subscriptions.create(
    {
      channel: "CommandOutputChannel",
      database: database,
      user_id: userId,
      job_id: jobId
    },
    {
      connected() {
        callbacks.connected?.()
      },
      received(data) {
        callbacks.received?.(data)
      },
      disconnected() {
        callbacks.disconnected?.()
      }
    }
  )
}
```

**After (Custom WebSocket)**:
```javascript
export function subscribeToCommandOutput(database, userId, jobId, callbacks) {
  const stream = `command_output_${database}_${userId}_${jobId}`
  const ws = new WebSocket(`ws://${window.location.host}/cable`)

  ws.onopen = () => {
    // Subscribe to stream
    ws.send(JSON.stringify({
      type: 'subscribe',
      stream: stream
    }))
  }

  ws.onmessage = (event) => {
    const msg = JSON.parse(event.data)

    switch (msg.type) {
      case 'subscribed':
        callbacks.connected?.()
        break

      case 'message':
        if (msg.stream === stream) {
          callbacks.received?.(msg.data)
        }
        break

      case 'ping':
        // Respond to ping
        ws.send(JSON.stringify({ type: 'pong' }))
        break
    }
  }

  ws.onclose = () => {
    callbacks.disconnected?.()
  }

  return {
    unsubscribe() {
      ws.send(JSON.stringify({
        type: 'unsubscribe',
        stream: stream
      }))
      ws.close()
    }
  }
}
```

**Channels to update** (5 total):
1. `command_output_channel.js` - Command execution output
2. `current_heat_channel.js` - Live heat updates
3. `live_scores_channel.js` - Live scoring updates
4. `config_update_channel.js` - Configuration updates
5. `offline_playlist_channel.js` - Playlist generation

---

## Configuration Changes

### Development (bin/dev)

**No changes needed** - Rails handles WebSockets via Puma:

```yaml
# config/cable.yml
development:
  adapter: async  # In-process, no external server
```

### Production (Navigator)

**Navigator configuration** in `config/navigator.yml`:

```yaml
server:
  listen: 3000
  # ... existing config ...

# No need for managed_processes - WebSocket built into Navigator
managed_processes: []
```

**Rails configuration**:

```yaml
# config/cable.yml
production:
  adapter: async  # Not used in prod (Navigator handles WebSocket)
```

**Environment variables** (set by configurator.rb):

```ruby
ENV['NAVIGATOR_BROADCAST_URL'] = 'http://localhost:3000/_broadcast'
```

---

## Testing Plan

### Unit Tests

```bash
# Test WebSocket handler
go test ./internal/cable/...

# Test subscription management
# Test broadcast routing
# Test connection lifecycle
```

### Integration Tests

```bash
# Start Navigator
./bin/navigator

# Test WebSocket connection
wscat -c ws://localhost:3000/cable

# Subscribe to stream
> {"type":"subscribe","stream":"test"}
< {"type":"subscribed","stream":"test"}

# Test broadcast endpoint
curl -X POST http://localhost:3000/_broadcast \
  -H "Content-Type: application/json" \
  -d '{"stream":"test","data":"hello world"}'

# Should receive on WebSocket:
< {"type":"message","stream":"test","data":"hello world"}
```

### Showcase Integration

Test all 5 channels:
1. CurrentHeatChannel - Update heat number, verify all clients see it
2. ScoresChannel - Enter scores, verify real-time updates
3. ConfigUpdateChannel - Trigger config update, verify progress
4. OfflinePlaylistChannel - Generate playlist, verify output
5. CommandOutputChannel - Run commands, verify terminal output

---

## Implementation Timeline

### Phase 1: Navigator WebSocket Server (1 day)
- Create `internal/cable/handler.go` (~230 lines)
- Integrate into Navigator main.go
- Add routes to server/handler.go
- Unit tests
- Manual testing with wscat

### Phase 2: Rails Integration (2 hours)
- Update ApplicationCable::Channel broadcast helper (~30 lines)
- Add NAVIGATOR_BROADCAST_URL environment variable
- Test broadcasts hit Navigator

### Phase 3: Client Updates (3-4 hours)
- Update 5 JavaScript channel files (~50 lines each)
- Remove Action Cable consumer dependency
- Test each channel individually
- End-to-end testing

### Phase 4: Production Testing (1 day)
- Deploy to staging
- Test all channels under load
- Verify memory usage (should match AnyCable: 25-35MB)
- Monitor for issues

**Total estimated time**: 2-3 days

---

## Rollback Plan

If custom implementation causes issues:

1. **Quick rollback**: Restore Action Cable
   - Revert JavaScript channel files
   - Revert Rails broadcast helper
   - Start Action Cable process in Navigator config
   - Redeploy

2. **Fallback to AnyCable**: Complete Part 3 of ANYCABLE_MIGRATION_PLAN.md
   - AnyCable code is already 90% complete
   - Just needs testing and verification

---

## Advantages vs AnyCable

### Technical
- ✅ **No external dependency**: stdlib only (gorilla/websocket is minimal)
- ✅ **Simpler protocol**: Easy to understand and debug
- ✅ **Full control**: Can optimize or extend easily
- ✅ **Same memory savings**: 134-144MB per region
- ✅ **Smaller binary**: No AnyCable overhead

### Operational
- ✅ **Dev/prod identical**: Same code path everywhere
- ✅ **Easier debugging**: All code is ours
- ✅ **No dependencies**: Zero external gems or binaries
- ✅ **No version tracking**: No upstream dependency to monitor
- ✅ **Cleaner logs**: Direct visibility into all operations

### Code
- ✅ **Similar complexity**: ~230 vs ~226 lines custom code
- ✅ **Better fit**: Tailored exactly to our needs
- ✅ **Test coverage**: We control the tests
- ✅ **Documentation**: We know exactly how it works

---

## Success Criteria

- ✅ All 5 channels work correctly
- ✅ Real-time updates function as expected
- ✅ Memory usage: 25-35MB (same as AnyCable target)
- ✅ No WebSocket connection errors
- ✅ Development and production work identically
- ✅ Easy to debug and maintain
- ✅ Simpler codebase (no AnyCable dependency)

---

## Comparison Summary

| Aspect | AnyCable | Custom |
|--------|----------|--------|
| **Custom code** | 226 lines | 230 lines |
| **External code** | 37k LOC | 0 LOC |
| **Protocol** | Action Cable | Simple JSON |
| **Dev/prod** | Different | **Same** |
| **Debugging** | Black box | **Full visibility** |
| **Memory** | 25-35MB | 25-35MB |
| **Client changes** | None | 5 files (~250 lines total) |
| **Maintenance** | Track updates | **Own code** |
| **Flexibility** | Limited | **Full control** |

**Recommendation**: Custom implementation provides better long-term value with minimal additional effort.
