# Custom WebSocket Implementation Plan v2

> **STATUS: ✅ ENGINE READY - NAVIGATOR IMPLEMENTATION NEXT**
>
> **Key Learning**: The missing piece was `turbo_stream_from` - without it, WebSocket connections never open. Now that we have a working Rails engine with proper Turbo Streams compatibility, creating a Go version is straightforward.
>
> **Proof of Concept**: Working Rails engine at `/Users/rubys/git/turbo_cable`
> **Test Application**: `/Users/rubys/tmp/counter` (turbo-cable-engine branch)

## Executive Summary

The `turbo_cable` Rails engine is complete and tested. It provides drop-in Turbo Streams compatibility using custom WebSocket infrastructure with 79-85% memory savings vs Action Cable.

**Next steps**: Integrate with Navigator for production deployment.

### Why This Works

The key insights that made this successful:

1. **`turbo_stream_from` is essential** - Creates markers that JavaScript discovers
2. **`prepend` overrides turbo-rails** - Ensures our broadcast methods are used instead of Action Cable
3. **broadcast_* methods render partials** - Exactly the same way Turbo does
4. **Protocol is simple** - Just Turbo Stream HTML over WebSocket

### Memory Savings (Same as Original Plan)

| Configuration | Memory | Savings vs Current |
|---------------|--------|-------------------|
| Current (Action Cable) | 169MB | baseline |
| **Custom WebSocket** | **25-35MB** | **134-144MB (79-85%)** |

---

## Part 1: TurboCable Rails Engine (✅ COMPLETE)

**Location**: `/Users/rubys/git/turbo_cable`

The Rails engine is complete and tested. Key components:

- **lib/turbo_cable/rack_handler.rb** - RFC 6455 WebSocket server via Rack hijack
- **lib/turbo_cable/broadcastable.rb** - All broadcast_* methods for models
- **app/helpers/turbo_cable/streams_helper.rb** - turbo_stream_from helper
- **lib/generators/turbo_cable/install** - One-command installation
- **Stimulus controller** - Client-side WebSocket management

**Installation**:
```bash
# Add to Gemfile
gem 'turbo_cable', path: '/Users/rubys/git/turbo_cable'  # or github: 'rubys/turbo_cable'

# Install
bundle install
rails generate turbo_cable:install
```

**Key Implementation Detail**: Uses `prepend` (not `include`) in the engine to override turbo-rails's broadcast methods, ensuring our HTTP POST broadcasts are used instead of Action Cable.

**Verified Working**: Tested in `/Users/rubys/tmp/counter` (turbo-cable-engine branch)

---

## Part 2: Navigator Go Implementation

**Estimated time**: 2-3 days

Now that we have the Ruby implementation working, the Go version follows the same patterns.

### Phase 2.1: Navigator WebSocket Handler

**File**: `navigator/internal/cable/handler.go`

Port the logic from `lib/turbo_cable/rack_handler.rb`:

```go
package cable

import (
    "context"
    "encoding/json"
    "log/slog"
    "net/http"
    "sync"

    "github.com/gorilla/websocket"
)

// Message types (same as Ruby implementation)
type Message struct {
    Type   string          `json:"type"`
    Stream string          `json:"stream,omitempty"`
    Data   json.RawMessage `json:"data,omitempty"`
}

// Handler manages WebSocket connections
type Handler struct {
    connections   map[*Connection]bool
    connectionsMu sync.RWMutex
    streams       map[string]map[*Connection]bool
    streamsMu     sync.RWMutex
    upgrader      websocket.Upgrader
    logger        *slog.Logger
}

// ServeHTTP handles /cable WebSocket upgrades
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    // Upgrade to WebSocket
    // Handle subscribe/unsubscribe messages
    // Same protocol as Ruby implementation
}

// HandleBroadcast handles POST to /_broadcast
func (h *Handler) HandleBroadcast(w http.ResponseWriter, r *http.Request) {
    // Read JSON: {stream: "...", data: "..."}
    // Broadcast to all subscribed connections
    // Same as Ruby implementation
}
```

**Estimated**: ~250 lines (similar to Ruby implementation)

### Phase 2.2: Integration with Navigator

**navigator/cmd/navigator/main.go**:

```go
import "github.com/rubys/navigator/internal/cable"

// In ServerLifecycle.Run():
cableHandler := cable.NewHandler(slog.Default())

// Add to shutdown:
defer func() {
    if err := cableHandler.Shutdown(ctx); err != nil {
        slog.Error("Cable shutdown failed", "error", err)
    }
}()

// Pass to server
handler := server.CreateHandler(
    l.cfg,
    l.appManager,
    l.basicAuth,
    l.idleManager,
    cableHandler, // <-- WebSocket handler
    // ...
)
```

**navigator/internal/server/handler.go**:

```go
// Add WebSocketHandler interface
type WebSocketHandler interface {
    ServeHTTP(w http.ResponseWriter, r *http.Request)
    HandleBroadcast(w http.ResponseWriter, r *http.Request)
}

// In ServeHTTP, route requests:
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

### Phase 2.3: Testing

**navigator/internal/cable/handler_test.go**:

Same tests as Ruby implementation:
1. WebSocket handshake
2. Subscribe/unsubscribe
3. Broadcasting
4. Concurrent connections
5. Stream routing
6. Graceful shutdown

**Estimated**: ~400 lines of tests

---

## Part 3: Showcase Application Migration

**Estimated time**: 1 day

### Phase 3.1: Development Environment

**Option A: Use turbo_cable gem (Ruby only)**

```ruby
# Gemfile
gem 'turbo_cable', path: '/path/to/turbo_cable' # or from rubygems

# Terminal
bundle install
rails generate turbo_cable:install
```

**No other changes needed!** The gem provides:
- ✅ Rack middleware
- ✅ Broadcastable methods in ApplicationRecord
- ✅ `turbo_stream_from` helper
- ✅ JavaScript controller
- ✅ `data-controller="turbo-streams"` on body

### Phase 3.2: Production Environment (Navigator)

**Option B: Use Navigator's Go implementation**

1. **Update config/navigator.yml**:
   ```yaml
   # No changes needed!
   # Navigator automatically handles /cable and /_broadcast
   ```

2. **Set environment variable**:
   ```ruby
   # config/application.rb or initializer
   # Tell TurboCable to broadcast to Navigator
   ENV['TURBO_CABLE_BROADCAST_URL'] = 'http://localhost:3000/_broadcast'
   ```

3. **Update broadcast method** (if needed):
   ```ruby
   # lib/turbo_cable/broadcastable.rb
   def broadcast_turbo_stream(stream_name, html)
     url = ENV.fetch('TURBO_CABLE_BROADCAST_URL',
                     "http://localhost:#{ENV.fetch('PORT', 3000)}/_broadcast")
     # ... rest of method
   end
   ```

### Phase 3.3: Verify Functionality

Test all channels:
1. ✅ Current heat counter updates
2. ✅ Live score updates
3. ✅ Multiple clients receive updates
4. ✅ Auto-reconnection works
5. ✅ Memory usage is 25-35MB

---

## Protocol Specification

### WebSocket Messages

**Client → Server**:

```json
// Subscribe
{
  "type": "subscribe",
  "stream": "counter_updates"
}

// Unsubscribe
{
  "type": "unsubscribe",
  "stream": "counter_updates"
}

// Pong (response to ping)
{
  "type": "pong"
}
```

**Server → Client**:

```json
// Subscribed confirmation
{
  "type": "subscribed",
  "stream": "counter_updates"
}

// Message (Turbo Stream HTML)
{
  "type": "message",
  "stream": "counter_updates",
  "data": "<turbo-stream action=\"replace\" target=\"counter-value\">...</turbo-stream>"
}

// Ping (keep-alive)
{
  "type": "ping"
}
```

### HTTP Broadcast Endpoint

**POST /_broadcast**:

```json
{
  "stream": "counter_updates",
  "data": "<turbo-stream action=\"replace\" target=\"counter-value\">...</turbo-stream>"
}
```

**Response**: 200 OK

---

## Key Differences from Original Plan

### What Changed:

1. **Ruby Implementation First**: Start with working Rails engine before Go
2. **turbo_stream_from Helper**: Essential for bootstrapping connections
3. **Full Turbo Streams API**: Support all broadcast_* methods
4. **Simpler Protocol**: Just send Turbo Stream HTML, no complex JSON
5. **No Client Changes**: Views stay identical to Action Cable

### What Stayed the Same:

1. **Zero Dependencies**: Only stdlib (+ gorilla/websocket for Go)
2. **Simple Protocol**: JSON messages over WebSocket
3. **Memory Savings**: 134-144MB reduction per region
4. **Dev/Prod Parity**: Same code everywhere

---

## Implementation Order

### ✅ Phase 1: Rails Engine (COMPLETE)
1. ✅ Create engine structure
2. ✅ Port working code from counter app
3. ✅ Test with counter app
4. ✅ Document (README)
5. ⏭️ Publish gem (optional - can publish to GitHub or RubyGems later)

### Phase 2: Test in Showcase Dev (4 hours)
1. Add `gem 'turbo_cable', path: '/Users/rubys/git/turbo_cable'` to Gemfile
2. Run `rails generate turbo_cable:install`
3. Restart server
4. Verify current heat and scores work
5. Check memory usage

### Phase 3: Navigator Integration (2-3 days)
1. Implement Go WebSocket handler in `navigator/internal/cable/`
2. Add routes for /cable and /_broadcast in Navigator
3. Write tests
4. Integration testing

### Phase 4: Test in Showcase Production (1 day)
1. Deploy Navigator with WebSocket support
2. Configure Rails to broadcast to Navigator (`TURBO_CABLE_BROADCAST_URL`)
3. Verify all channels work
4. Monitor memory usage
5. Performance testing

### Phase 5: Rollout (1 week)
1. Deploy to staging
2. Monitor for issues
3. Deploy to production regions
4. Verify memory savings (target: 134-144MB reduction)
5. Document operational procedures

**Total estimated time**: 1-2 weeks (Phase 1 complete, ~1 week remaining)

---

## Success Criteria

### ✅ Rails Engine (Complete)
- ✅ Rails engine created and tested
- ✅ Install with single command: `rails generate turbo_cable:install`
- ✅ Views identical to Action Cable
- ✅ Models use same broadcast_* API
- ✅ Zero external dependencies (only Ruby stdlib)
- ✅ Comprehensive README documentation

### 🔲 Integration Testing (Next)
- 🔲 Current heat updates work in showcase app
- 🔲 Live scores update work in showcase app
- 🔲 Multiple clients receive updates simultaneously
- 🔲 Auto-reconnection after disconnect

### 🔲 Navigator Go Implementation (Future)
- 🔲 Go WebSocket handler in Navigator
- 🔲 Routes for /cable and /_broadcast
- 🔲 Integration tests passing

### 🔲 Production Deployment (Future)
- 🔲 Memory usage: 25-35MB (down from 169MB)
- 🔲 Dev/prod behavior identical
- 🔲 Easy to debug and maintain
- 🔲 Deployed to all production regions

---

## Rollback Plan

If issues arise:

### Development:
```ruby
# Gemfile
# gem 'turbo_cable' # Comment out
gem 'turbo-rails' # Already there

# Revert layout
# Remove data-controller="turbo-streams" from body tag

# Restart server
```

### Production:
1. Remove TurboCable gem
2. Restore Action Cable process in Navigator config
3. Redeploy
4. Action Cable resumes as before

---

## Next Steps

1. **Create turbo_cable engine** from counter app code
2. **Test in showcase dev** environment
3. **Implement Navigator Go handler** (straightforward port)
4. **Deploy to staging** for validation
5. **Roll out to production** incrementally

---

## Appendix: Code Locations

### TurboCable Engine (Production Ready)
- **Repository**: `/Users/rubys/git/turbo_cable`
- **Key Files**:
  - `lib/turbo_cable/rack_handler.rb` - WebSocket server (187 lines)
  - `lib/turbo_cable/broadcastable.rb` - Broadcast methods (95 lines)
  - `app/helpers/turbo_cable/streams_helper.rb` - turbo_stream_from helper (14 lines)
  - `lib/generators/turbo_cable/install/templates/turbo_streams_controller.js` - Client (170 lines)
  - `lib/turbo_cable/engine.rb` - Railtie integration
  - `README.md` - Full documentation

### Test Application
- **Repository**: `/Users/rubys/tmp/counter`
- **Branches**:
  - `main` - Action Cable implementation
  - `custom-websocket` - Manual WebSocket implementation (proof of concept)
  - `turbo-cable-engine` - Using turbo_cable gem (recommended)

### Installation in Any Rails App:
```bash
# Add to Gemfile
gem 'turbo_cable', path: '/Users/rubys/git/turbo_cable'
# Or from GitHub (once pushed):
# gem 'turbo_cable', github: 'rubys/turbo_cable'

# Install
bundle install
rails generate turbo_cable:install
```
