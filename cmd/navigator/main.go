package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"log/slog"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/tg123/go-htpasswd"
	"gopkg.in/yaml.v3"
)

// RewriteRule represents a rewrite rule
type RewriteRule struct {
	Pattern     *regexp.Regexp
	Replacement string
	Flag        string   // redirect, last, fly-replay:region:status, etc.
	Methods     []string // Allowed methods for this rule
}

// AuthPattern represents an auth exclusion pattern
type AuthPattern struct {
	Pattern *regexp.Regexp
	Action  string // "off" or realm name
}

// DNSCacheEntry represents a cached DNS lookup result
type DNSCacheEntry struct {
	Available bool
	ExpiresAt time.Time
}

// DNSCache manages cached DNS availability results
type DNSCache struct {
	mutex sync.RWMutex
	cache map[string]*DNSCacheEntry
	ttl   time.Duration
}

// NewDNSCache creates a new DNS cache with specified TTL
func NewDNSCache(ttl time.Duration) *DNSCache {
	return &DNSCache{
		cache: make(map[string]*DNSCacheEntry),
		ttl:   ttl,
	}
}

// Get retrieves a cached DNS result if available and not expired
func (c *DNSCache) Get(region string) (bool, bool) {
	c.mutex.RLock()
	defer c.mutex.RUnlock()

	entry, exists := c.cache[region]
	if !exists {
		return false, false
	}

	if time.Now().After(entry.ExpiresAt) {
		// Entry expired, will be cleaned up later
		return false, false
	}

	return entry.Available, true
}

// Set stores a DNS result in the cache
func (c *DNSCache) Set(region string, available bool) {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	c.cache[region] = &DNSCacheEntry{
		Available: available,
		ExpiresAt: time.Now().Add(c.ttl),
	}
}

// Clear removes all cached entries
func (c *DNSCache) Clear() {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	c.cache = make(map[string]*DNSCacheEntry)
	slog.Debug("DNS cache cleared")
}

// CleanExpired removes expired entries from the cache
func (c *DNSCache) CleanExpired() {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	now := time.Now()
	for region, entry := range c.cache {
		if now.After(entry.ExpiresAt) {
			delete(c.cache, region)
		}
	}
}

// Config represents the parsed configuration
type Config struct {
	ServerName       string
	ListenPort       int
	MaxPoolSize      int
	DefaultUser      string
	DefaultGroup     string
	LogFile          string
	ErrorLog         string
	AccessLog        string
	AuthFile         string
	AuthRealm        string
	AuthExclude      []string
	AuthPatterns     []*AuthPattern
	RewriteRules     []*RewriteRule
	ProxyRoutes      map[string]*ProxyRoute
	Locations        map[string]*Location
	GlobalEnvVars    map[string]string
	ClientMaxBody    string
	PassengerRuby    string
	MinInstances     int
	PreloadBundler   bool
	IdleTimeout      time.Duration // Idle timeout for app processes
	StartPort        int           // Starting port for Rails apps
	StaticDirs       []*StaticDir  // Static directory mappings
	StaticExts       []string      // File extensions to serve statically
	TryFilesSuffixes []string      // Suffixes for try_files behavior
	PublicDir        string        // Default public directory
	MaintenancePage  string        // Path to maintenance page (e.g., "/503.html")
	ManagedProcesses []struct {    // Managed processes to start/stop with Navigator
		Name        string            `yaml:"name"`
		Command     string            `yaml:"command"`
		Args        []string          `yaml:"args"`
		WorkingDir  string            `yaml:"working_dir"`
		Env         map[string]string `yaml:"env"`
		AutoRestart bool              `yaml:"auto_restart"`
		StartDelay  int               `yaml:"start_delay"`
	}

	// Suspend configuration
	SuspendEnabled     bool
	SuspendIdleTimeout time.Duration
}

// StaticDir represents a static directory mapping
type StaticDir struct {
	URLPath   string // URL path prefix (e.g., "/assets/")
	LocalPath string // Local filesystem path (e.g., "public/assets/")
	CacheTTL  int    // Cache TTL in seconds
}

// ProxyRoute represents a route that proxies to another server
type ProxyRoute struct {
	Pattern        string
	ProxyPass      string
	SetHeaders     map[string]string
	SSLVerify      bool
	ExcludeMethods []string // Methods to exclude from proxying
}

// Location represents a Rails application location
type Location struct {
	Path             string
	Root             string
	EnvVars          map[string]string
	BaseURI          string
	MatchPattern     string // Pattern for matching request paths (e.g., "*/cable")
	StandaloneServer string // If set, proxy to this server instead of Rails app
}

// RailsApp represents a running Rails application
type RailsApp struct {
	Location   *Location
	Process    *exec.Cmd
	Port       int
	LastAccess time.Time
	Starting   bool
	mutex      sync.RWMutex
	ctx        context.Context
	cancel     context.CancelFunc
}

// YAMLConfig represents the new YAML configuration format
type YAMLConfig struct {
	Server struct {
		Listen    int    `yaml:"listen"`
		Hostname  string `yaml:"hostname"`
		RootPath  string `yaml:"root_path"`
		PublicDir string `yaml:"public_dir"`
	} `yaml:"server"`

	Pools struct {
		MaxSize     int `yaml:"max_size"`
		IdleTimeout int `yaml:"idle_timeout"`
		StartPort   int `yaml:"start_port"`
	} `yaml:"pools"`

	Auth struct {
		Enabled         bool     `yaml:"enabled"`
		Realm           string   `yaml:"realm"`
		HTPasswd        string   `yaml:"htpasswd"`
		PublicPaths     []string `yaml:"public_paths"`
		ExcludePatterns []struct {
			Pattern     string `yaml:"pattern"`
			Description string `yaml:"description"`
		} `yaml:"exclude_patterns"`
	} `yaml:"auth"`

	Routes struct {
		Redirects []struct {
			From string `yaml:"from"`
			To   string `yaml:"to"`
		} `yaml:"redirects"`
		Rewrites []struct {
			From string `yaml:"from"`
			To   string `yaml:"to"`
		} `yaml:"rewrites"`
		Proxies []struct {
			Path    string            `yaml:"path"`
			Target  string            `yaml:"target"`
			Headers map[string]string `yaml:"headers"`
		} `yaml:"proxies"`
		FlyReplay []struct {
			Path    string   `yaml:"path"`
			Region  string   `yaml:"region"`
			Status  int      `yaml:"status"`
			Methods []string `yaml:"methods"`
		} `yaml:"fly_replay"`
		ReverseProxies []struct {
			Path           string            `yaml:"path"`
			Target         string            `yaml:"target"`
			Headers        map[string]string `yaml:"headers"`
			ExcludeMethods []string          `yaml:"exclude_methods"`
		} `yaml:"reverse_proxies"`
	} `yaml:"routes"`

	Static struct {
		Directories []struct {
			Path  string `yaml:"path"`
			Root  string `yaml:"root"`
			Cache int    `yaml:"cache"`
		} `yaml:"directories"`
		Extensions []string `yaml:"extensions"`
		TryFiles   struct {
			Enabled  bool     `yaml:"enabled"`
			Suffixes []string `yaml:"suffixes"`
			Fallback string   `yaml:"fallback"`
		} `yaml:"try_files"`
	} `yaml:"static"`

	Applications struct {
		Env     map[string]string `yaml:"env"`
		Tenants []struct {
			Path                       string            `yaml:"path"`
			Root                       string            `yaml:"root"`
			Special                    bool              `yaml:"special"`
			MatchPattern               string            `yaml:"match_pattern"`
			StandaloneServer           string            `yaml:"standalone_server"`
			Env                        map[string]string `yaml:"env"`
			Var                        map[string]string `yaml:"var"`
			ForceMaxConcurrentRequests int               `yaml:"force_max_concurrent_requests"`
		} `yaml:"tenants"`
	} `yaml:"applications"`

	Process struct {
		Ruby           string `yaml:"ruby"`
		BundlerPreload bool   `yaml:"bundler_preload"`
		MinInstances   int    `yaml:"min_instances"`
	} `yaml:"process"`

	Logging struct {
		AccessLog string `yaml:"access_log"`
		ErrorLog  string `yaml:"error_log"`
		Level     string `yaml:"level"`
		Format    string `yaml:"format"`
	} `yaml:"logging"`

	Health struct {
		Endpoint string `yaml:"endpoint"`
		Timeout  int    `yaml:"timeout"`
		Interval int    `yaml:"interval"`
	} `yaml:"health"`

	Suspend struct {
		Enabled     bool `yaml:"enabled"`
		IdleTimeout int  `yaml:"idle_timeout"` // Seconds of inactivity before suspend
	} `yaml:"suspend"`

	ManagedProcesses []struct {
		Name        string            `yaml:"name"`
		Command     string            `yaml:"command"`
		Args        []string          `yaml:"args"`
		WorkingDir  string            `yaml:"working_dir"`
		Env         map[string]string `yaml:"env"`
		AutoRestart bool              `yaml:"auto_restart"`
		StartDelay  int               `yaml:"start_delay"` // Delay in seconds before starting
	} `yaml:"managed_processes"`
}

// ManagedProcess represents an external process managed by Navigator
type ManagedProcess struct {
	Name        string
	Command     string
	Args        []string
	WorkingDir  string
	Env         map[string]string
	AutoRestart bool
	StartDelay  time.Duration
	Process     *exec.Cmd
	Cancel      context.CancelFunc
	Running     bool
	mutex       sync.RWMutex
}

// ProcessManager manages external processes
type ProcessManager struct {
	processes []*ManagedProcess
	mutex     sync.RWMutex
	wg        sync.WaitGroup
}

// SuspendManager tracks active requests and handles machine suspension
type SuspendManager struct {
	enabled        bool
	idleTimeout    time.Duration
	activeRequests int64
	lastActivity   time.Time
	mutex          sync.RWMutex
	timer          *time.Timer
}

// AppManager manages Rails application processes
type AppManager struct {
	apps        map[string]*RailsApp
	config      *Config
	mutex       sync.RWMutex
	idleTimeout time.Duration
	minPort     int // Minimum port for Rails apps
	maxPort     int // Maximum port for Rails apps
}

// cleanupPidFile checks for and removes stale PID file
func cleanupPidFile(pidfilePath string) error {
	if pidfilePath == "" {
		return nil
	}

	// Check if PID file exists
	data, err := os.ReadFile(pidfilePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // No PID file, nothing to clean up
		}
		return fmt.Errorf("error reading PID file %s: %v", pidfilePath, err)
	}

	// Parse PID
	pidStr := strings.TrimSpace(string(data))
	pid, err := strconv.Atoi(pidStr)
	if err != nil {
		log.Printf("Invalid PID in file %s: %s", pidfilePath, pidStr)
		// Remove invalid PID file
		os.Remove(pidfilePath)
		return nil
	}

	// Try to kill the process
	process, err := os.FindProcess(pid)
	if err == nil {
		// Send SIGTERM
		err = process.Signal(syscall.SIGTERM)
		if err == nil {
			log.Printf("Killed stale process %d from %s", pid, pidfilePath)
			// Give it a moment to exit cleanly
			time.Sleep(100 * time.Millisecond)
		}
		// Try SIGKILL if needed
		process.Signal(syscall.SIGKILL)
	}

	// Remove PID file
	if err := os.Remove(pidfilePath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("error removing PID file %s: %v", pidfilePath, err)
	}

	return nil
}

// findAvailablePort finds an available port in the specified range
func findAvailablePort(minPort, maxPort int) (int, error) {
	for port := minPort; port <= maxPort; port++ {
		// Try to listen on the port
		listener, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
		if err == nil {
			// Port is available
			listener.Close()
			return port, nil
		}
	}
	return 0, fmt.Errorf("no available ports in range %d-%d", minPort, maxPort)
}

// getPidFilePath gets the PID file path from environment variables
func getPidFilePath(envVars map[string]string) string {
	if pidfile, ok := envVars["PIDFILE"]; ok {
		return pidfile
	}
	return ""
}

// UpdateConfig updates the AppManager configuration after a reload
func (m *AppManager) UpdateConfig(newConfig *Config) {
	m.mutex.Lock()
	defer m.mutex.Unlock()

	m.config = newConfig

	// Update idle timeout if changed
	idleTimeout := newConfig.IdleTimeout
	if idleTimeout == 0 {
		idleTimeout = 10 * time.Minute
	}
	m.idleTimeout = idleTimeout

	// Update port range if changed
	startPort := newConfig.StartPort
	if startPort == 0 {
		startPort = 4000
	}
	m.minPort = startPort
	m.maxPort = startPort + 100

	log.Printf("Updated AppManager configuration: idle timeout=%v, port range=%d-%d",
		m.idleTimeout, m.minPort, m.maxPort)
}

// Cleanup stops all running Rails applications
func (m *AppManager) Cleanup() {
	m.mutex.Lock()
	defer m.mutex.Unlock()

	log.Println("Cleaning up all Rails applications...")

	for path, app := range m.apps {
		log.Printf("Stopping Rails app for %s", path)

		// Clean up PID file
		pidfilePath := getPidFilePath(app.Location.EnvVars)
		if pidfilePath != "" {
			if err := os.Remove(pidfilePath); err != nil && !os.IsNotExist(err) {
				log.Printf("Warning: Error removing PID file %s: %v", pidfilePath, err)
			}
		}

		if app.cancel != nil {
			app.cancel()
		}
	}

	// Clear the apps map
	m.apps = make(map[string]*RailsApp)

	// Give processes a moment to exit cleanly
	time.Sleep(500 * time.Millisecond)
}

// NewProcessManager creates a new process manager
func NewProcessManager() *ProcessManager {
	return &ProcessManager{
		processes: make([]*ManagedProcess, 0),
	}
}

// StartProcess starts a managed process
func (pm *ProcessManager) StartProcess(mp *ManagedProcess) error {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()

	// Add delay if specified
	if mp.StartDelay > 0 {
		log.Printf("Waiting %v before starting process %s", mp.StartDelay, mp.Name)
		time.Sleep(mp.StartDelay)
	}

	ctx, cancel := context.WithCancel(context.Background())
	mp.Cancel = cancel

	// Create the command
	cmd := exec.CommandContext(ctx, mp.Command, mp.Args...)

	if mp.WorkingDir != "" {
		cmd.Dir = mp.WorkingDir
	}

	// Set up environment
	env := os.Environ()
	for k, v := range mp.Env {
		env = append(env, fmt.Sprintf("%s=%s", k, v))
	}
	cmd.Env = env

	// Set up output
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	mp.Process = cmd

	log.Printf("Starting managed process '%s': %s %s", mp.Name, mp.Command, strings.Join(mp.Args, " "))

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to start process %s: %v", mp.Name, err)
	}

	// Monitor the process
	pm.wg.Add(1)
	go func() {
		defer pm.wg.Done()
		err := cmd.Wait()

		mp.mutex.Lock()
		shouldRestart := mp.AutoRestart
		mp.mutex.Unlock()

		if err != nil {
			log.Printf("Process '%s' exited with error: %v", mp.Name, err)
		} else {
			log.Printf("Process '%s' exited normally", mp.Name)
		}

		// Auto-restart if configured
		if shouldRestart && err != nil {
			log.Printf("Auto-restarting process '%s' in 5 seconds", mp.Name)
			time.Sleep(5 * time.Second)
			if err := pm.StartProcess(mp); err != nil {
				log.Printf("Failed to restart process '%s': %v", mp.Name, err)
			}
		}
	}()

	pm.processes = append(pm.processes, mp)
	return nil
}

// StartAll starts all configured processes
func (pm *ProcessManager) StartAll(processes []struct {
	Name        string            `yaml:"name"`
	Command     string            `yaml:"command"`
	Args        []string          `yaml:"args"`
	WorkingDir  string            `yaml:"working_dir"`
	Env         map[string]string `yaml:"env"`
	AutoRestart bool              `yaml:"auto_restart"`
	StartDelay  int               `yaml:"start_delay"`
}) {
	for _, proc := range processes {
		mp := &ManagedProcess{
			Name:        proc.Name,
			Command:     proc.Command,
			Args:        proc.Args,
			WorkingDir:  proc.WorkingDir,
			Env:         proc.Env,
			AutoRestart: proc.AutoRestart,
			StartDelay:  time.Duration(proc.StartDelay) * time.Second,
		}

		if err := pm.StartProcess(mp); err != nil {
			log.Printf("Failed to start process '%s': %v", proc.Name, err)
		}
	}
}

// StopAll stops all managed processes
func (pm *ProcessManager) StopAll() {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()

	log.Println("Stopping all managed processes...")

	for _, mp := range pm.processes {
		if mp.Cancel != nil {
			log.Printf("Stopping process '%s'", mp.Name)
			mp.Cancel()
		}
	}

	// Wait for all processes to finish with timeout
	done := make(chan struct{})
	go func() {
		pm.wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		log.Println("All managed processes stopped")
	case <-time.After(10 * time.Second):
		log.Println("Timeout waiting for processes to stop, forcing shutdown")
		for _, mp := range pm.processes {
			if mp.Process != nil && mp.Process.Process != nil {
				mp.Process.Process.Kill()
			}
		}
	}
}

// UpdateConfig updates the process manager configuration
func (pm *ProcessManager) UpdateConfig(processes []struct {
	Name        string            `yaml:"name"`
	Command     string            `yaml:"command"`
	Args        []string          `yaml:"args"`
	WorkingDir  string            `yaml:"working_dir"`
	Env         map[string]string `yaml:"env"`
	AutoRestart bool              `yaml:"auto_restart"`
	StartDelay  int               `yaml:"start_delay"`
}) {
	slog.Info("Updating managed processes configuration", "count", len(processes))

	// Stop all existing processes
	pm.StopAll()

	// Clear the process list
	pm.mutex.Lock()
	pm.processes = make([]*ManagedProcess, 0)
	pm.mutex.Unlock()

	// Start new processes with updated config
	pm.StartAll(processes)
}

// NewSuspendManager creates a new suspend manager
func NewSuspendManager(enabled bool, idleTimeout time.Duration) *SuspendManager {
	if !enabled {
		return &SuspendManager{enabled: false}
	}

	return &SuspendManager{
		enabled:      true,
		idleTimeout:  idleTimeout,
		lastActivity: time.Now(),
	}
}

// RequestStarted increments active request counter and resets idle timer
func (sm *SuspendManager) RequestStarted() {
	if !sm.enabled {
		return
	}

	sm.mutex.Lock()
	defer sm.mutex.Unlock()

	sm.activeRequests++
	sm.lastActivity = time.Now()

	// Cancel existing timer since we have activity
	if sm.timer != nil {
		sm.timer.Stop()
		sm.timer = nil
	}

	slog.Debug("Request started", "activeRequests", sm.activeRequests)
}

// RequestFinished decrements active request counter and starts suspend timer if idle
func (sm *SuspendManager) RequestFinished() {
	if !sm.enabled {
		return
	}

	sm.mutex.Lock()
	defer sm.mutex.Unlock()

	sm.activeRequests--
	sm.lastActivity = time.Now()

	slog.Debug("Request finished", "activeRequests", sm.activeRequests)

	// Start suspend timer if no active requests
	if sm.activeRequests == 0 {
		sm.startSuspendTimer()
	}
}

// startSuspendTimer starts the suspend countdown (must be called with mutex held)
func (sm *SuspendManager) startSuspendTimer() {
	if sm.timer != nil {
		sm.timer.Stop()
	}

	sm.timer = time.AfterFunc(sm.idleTimeout, func() {
		sm.suspendMachine()
	})

	slog.Debug("Suspend timer started", "timeout", sm.idleTimeout)
}

// suspendMachine calls the Fly API to suspend the machine
func (sm *SuspendManager) suspendMachine() {
	appName := os.Getenv("FLY_APP_NAME")
	machineId := os.Getenv("FLY_MACHINE_ID")

	if appName == "" || machineId == "" {
		slog.Warn("Cannot suspend: missing FLY_APP_NAME or FLY_MACHINE_ID")
		return
	}

	// Clear DNS cache before suspending
	if dnsCache != nil {
		dnsCache.Clear()
		slog.Debug("DNS cache cleared before machine suspend")
	}

	slog.Info("Suspending machine", "app", appName, "machine", machineId)

	// Create HTTP client with Unix socket transport
	client := &http.Client{
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				return net.Dial("unix", "/.fly/api")
			},
		},
		Timeout: 10 * time.Second,
	}

	// Create suspend request
	url := fmt.Sprintf("http://flaps/v1/apps/%s/machines/%s/suspend", appName, machineId)
	req, err := http.NewRequest("POST", url, nil)
	if err != nil {
		slog.Error("Failed to create suspend request", "error", err)
		return
	}

	// Execute request
	resp, err := client.Do(req)
	if err != nil {
		slog.Error("Failed to suspend machine", "error", err)
		return
	}
	defer resp.Body.Close()

	// Read response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		slog.Error("Failed to read suspend response", "error", err)
		return
	}

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		slog.Info("Machine suspend requested successfully", "status", resp.StatusCode, "response", string(body))
	} else {
		slog.Error("Machine suspend failed", "status", resp.StatusCode, "response", string(body))
	}
}

// UpdateConfig updates the suspend manager configuration
func (sm *SuspendManager) UpdateConfig(enabled bool, idleTimeout time.Duration) {
	sm.mutex.Lock()
	defer sm.mutex.Unlock()

	// Stop existing timer if configuration is changing
	if sm.timer != nil {
		sm.timer.Stop()
		sm.timer = nil
	}

	sm.enabled = enabled
	sm.idleTimeout = idleTimeout

	if enabled {
		slog.Info("Suspend feature enabled", "idleTimeout", idleTimeout)
		sm.lastActivity = time.Now()
		// Start timer if we're idle (no active requests)
		if sm.activeRequests == 0 {
			sm.startSuspendTimer()
		}
	} else {
		slog.Info("Suspend feature disabled")
	}
}

// BasicAuth represents HTTP basic authentication
type BasicAuth struct {
	File    *htpasswd.File
	Realm   string
	Exclude []string
}

// Placeholder for removed APR1 implementation - now handled by go-htpasswd library

const navigatorPIDFile = "/tmp/navigator.pid"

// writePIDFile writes the current process PID to a file
func writePIDFile() error {
	pid := os.Getpid()
	return os.WriteFile(navigatorPIDFile, []byte(strconv.Itoa(pid)), 0644)
}

// removePIDFile removes the PID file
func removePIDFile() {
	os.Remove(navigatorPIDFile)
}

// sendReloadSignal sends a HUP signal to the running navigator process
func sendReloadSignal() error {
	// Read PID from file
	pidData, err := os.ReadFile(navigatorPIDFile)
	if err != nil {
		if os.IsNotExist(err) {
			return fmt.Errorf("navigator is not running (PID file not found)")
		}
		return fmt.Errorf("failed to read PID file: %v", err)
	}

	pid, err := strconv.Atoi(strings.TrimSpace(string(pidData)))
	if err != nil {
		return fmt.Errorf("invalid PID in file: %v", err)
	}

	// Find the process
	process, err := os.FindProcess(pid)
	if err != nil {
		return fmt.Errorf("failed to find process %d: %v", pid, err)
	}

	// Send HUP signal
	if err := process.Signal(syscall.SIGHUP); err != nil {
		// Check if process exists
		if err.Error() == "os: process already finished" {
			// Clean up stale PID file
			removePIDFile()
			return fmt.Errorf("navigator is not running (process %d not found)", pid)
		}
		return fmt.Errorf("failed to send signal to process %d: %v", pid, err)
	}

	log.Printf("Reload signal sent to navigator (PID: %d)", pid)
	return nil
}

// Global DNS cache for target machine availability checks
var dnsCache *DNSCache

func main() {
	// Initialize logger with level from environment variable
	logLevel := slog.LevelInfo // Default to Info level
	if lvl := os.Getenv("LOG_LEVEL"); lvl != "" {
		switch strings.ToLower(lvl) {
		case "debug":
			logLevel = slog.LevelDebug
		case "info":
			logLevel = slog.LevelInfo
		case "warn", "warning":
			logLevel = slog.LevelWarn
		case "error":
			logLevel = slog.LevelError
		}
	}

	// Create text handler with the specified level
	opts := &slog.HandlerOptions{
		Level: logLevel,
	}
	logger := slog.New(slog.NewTextHandler(os.Stdout, opts))
	slog.SetDefault(logger)

	// Initialize DNS cache with 30-second TTL
	dnsCache = NewDNSCache(30 * time.Second)

	// Handle -s reload option
	if len(os.Args) > 1 && os.Args[1] == "-s" {
		if len(os.Args) > 2 && os.Args[2] == "reload" {
			if err := sendReloadSignal(); err != nil {
				log.Fatalf("Failed to reload: %v", err)
			}
			os.Exit(0)
		} else if len(os.Args) > 2 {
			log.Fatalf("Unknown signal: %s (only 'reload' is supported)", os.Args[2])
		} else {
			log.Fatalf("Option -s requires a signal name (e.g., -s reload)")
		}
	}

	// Handle --help option
	if len(os.Args) > 1 && (os.Args[1] == "--help" || os.Args[1] == "-h") {
		fmt.Println("Navigator - Rails application server")
		fmt.Println()
		fmt.Println("Usage:")
		fmt.Println("  navigator [config-file]     Start server with optional config file")
		fmt.Println("  navigator -s reload         Reload configuration of running server")
		fmt.Println("  navigator --help            Show this help message")
		fmt.Println()
		fmt.Println("Default config file: config/navigator.yml")
		fmt.Println()
		fmt.Println("Signals:")
		fmt.Println("  SIGHUP   Reload configuration without restart")
		fmt.Println("  SIGTERM  Graceful shutdown")
		fmt.Println("  SIGINT   Immediate shutdown")
		os.Exit(0)
	}

	configFile := "config/navigator.yml"
	if len(os.Args) > 1 {
		configFile = os.Args[1]
	}

	// Write PID file for -s reload functionality
	if err := writePIDFile(); err != nil {
		log.Printf("Warning: Could not write PID file: %v", err)
	}
	defer removePIDFile()

	log.Printf("Loading configuration from %s", configFile)
	config, err := LoadConfig(configFile)
	if err != nil {
		log.Fatalf("Failed to parse config: %v", err)
	}

	log.Printf("Loaded %d locations and %d proxy routes", len(config.Locations), len(config.ProxyRoutes))

	var auth *BasicAuth
	if config.AuthFile != "" {
		auth, err = LoadAuthFile(config.AuthFile, config.AuthRealm, config.AuthExclude)
		if err != nil {
			log.Printf("Warning: Failed to load auth file %s: %v", config.AuthFile, err)
		} else {
			log.Printf("Loaded authentication from %s", config.AuthFile)
		}
	}

	manager := NewAppManager(config)

	// Create suspend manager
	suspendManager := NewSuspendManager(config.SuspendEnabled, config.SuspendIdleTimeout)
	if suspendManager.enabled {
		slog.Info("Suspend feature enabled", "idleTimeout", config.SuspendIdleTimeout)
	}

	// Create and start process manager for managed processes
	processManager := NewProcessManager()
	if len(config.ManagedProcesses) > 0 {
		log.Printf("Starting %d managed processes", len(config.ManagedProcesses))
		processManager.StartAll(config.ManagedProcesses)
	}

	// Start DNS cache cleanup goroutine
	go func() {
		ticker := time.NewTicker(60 * time.Second) // Clean every minute
		defer ticker.Stop()

		for range ticker.C {
			if dnsCache != nil {
				dnsCache.CleanExpired()
			}
		}
	}()

	// Create a mutable handler wrapper for configuration reloading
	handler := CreateHandler(config, manager, auth, suspendManager)

	// Wrapper handler that delegates to the current configuration
	var handlerMutex sync.RWMutex
	currentHandler := handler

	mainHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		handlerMutex.RLock()
		h := currentHandler
		handlerMutex.RUnlock()
		h.ServeHTTP(w, r)
	})

	// Set up signal handling for graceful shutdown and reload
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM, syscall.SIGHUP)

	// Start signal handler goroutine
	go func() {
		for sig := range sigChan {
			switch sig {
			case syscall.SIGHUP:
				// Reload configuration
				log.Println("Received SIGHUP signal, reloading configuration...")

				newConfig, err := LoadConfig(configFile)
				if err != nil {
					log.Printf("Error reloading configuration: %v", err)
					continue
				}

				log.Printf("Reloaded %d locations and %d proxy routes", len(newConfig.Locations), len(newConfig.ProxyRoutes))

				// Reload auth if configured
				var newAuth *BasicAuth
				if newConfig.AuthFile != "" {
					newAuth, err = LoadAuthFile(newConfig.AuthFile, newConfig.AuthRealm, newConfig.AuthExclude)
					if err != nil {
						log.Printf("Warning: Failed to reload auth file %s: %v", newConfig.AuthFile, err)
						// Keep existing auth on error
						newAuth = auth
					} else {
						log.Printf("Reloaded authentication from %s", newConfig.AuthFile)
					}
				}

				// Update manager configuration
				manager.UpdateConfig(newConfig)

				// Update suspend manager configuration
				suspendManager.UpdateConfig(newConfig.SuspendEnabled, newConfig.SuspendIdleTimeout)

				// Update process manager configuration
				processManager.UpdateConfig(newConfig.ManagedProcesses)

				// Create new handler with updated config
				newHandler := CreateHandler(newConfig, manager, newAuth, suspendManager)

				// Atomically swap the handler
				handlerMutex.Lock()
				currentHandler = newHandler
				config = newConfig
				auth = newAuth
				handlerMutex.Unlock()

				log.Println("Configuration reload complete")

			case os.Interrupt, syscall.SIGTERM:
				log.Println("Received interrupt signal, cleaning up...")
				manager.Cleanup()        // Stop Rails apps first
				processManager.StopAll() // Then stop managed processes
				os.Exit(0)
			}
		}
	}()

	go manager.IdleChecker()

	addr := fmt.Sprintf(":%d", config.ListenPort)
	log.Printf("Starting Navigator server on %s", addr)
	log.Printf("Max pool size: %d, Idle timeout: %v", config.MaxPoolSize, manager.idleTimeout)
	log.Printf("Send SIGHUP to reload configuration without restart (kill -HUP %d)", os.Getpid())

	if err := http.ListenAndServe(addr, mainHandler); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

// LoadConfig loads YAML configuration
func LoadConfig(filename string) (*Config, error) {
	content, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}

	log.Println("Loading YAML configuration")
	return ParseYAML(content)
}

// substituteVars replaces template variables with tenant values
func substituteVars(template string, tenant struct {
	Path                       string            `yaml:"path"`
	Root                       string            `yaml:"root"`
	Special                    bool              `yaml:"special"`
	MatchPattern               string            `yaml:"match_pattern"`
	StandaloneServer           string            `yaml:"standalone_server"`
	Env                        map[string]string `yaml:"env"`
	Var                        map[string]string `yaml:"var"`
	ForceMaxConcurrentRequests int               `yaml:"force_max_concurrent_requests"`
}) string {
	result := template
	// Replace ${var} with values from the Var map
	if tenant.Var != nil {
		for key, value := range tenant.Var {
			result = strings.ReplaceAll(result, "${"+key+"}", value)
		}
	}
	return result
}

// ParseYAML parses the new YAML configuration format
func ParseYAML(content []byte) (*Config, error) {
	var yamlConfig YAMLConfig
	if err := yaml.Unmarshal(content, &yamlConfig); err != nil {
		return nil, fmt.Errorf("failed to parse YAML: %w", err)
	}

	// Convert YAML config to internal Config structure
	config := &Config{
		ServerName:    yamlConfig.Server.Hostname,
		ListenPort:    yamlConfig.Server.Listen,
		MaxPoolSize:   yamlConfig.Pools.MaxSize,
		Locations:     make(map[string]*Location),
		ProxyRoutes:   make(map[string]*ProxyRoute),
		GlobalEnvVars: make(map[string]string),
		RewriteRules:  []*RewriteRule{},
		AuthPatterns:  []*AuthPattern{},
	}

	// Set authentication config
	if yamlConfig.Auth.Enabled {
		config.AuthFile = yamlConfig.Auth.HTPasswd
		config.AuthRealm = yamlConfig.Auth.Realm
		config.AuthExclude = yamlConfig.Auth.PublicPaths

		// Convert exclude patterns
		for _, pattern := range yamlConfig.Auth.ExcludePatterns {
			if re, err := regexp.Compile(pattern.Pattern); err == nil {
				config.AuthPatterns = append(config.AuthPatterns, &AuthPattern{
					Pattern: re,
					Action:  "off",
				})
			} else {
				log.Printf("Warning: Invalid auth pattern %s: %v", pattern.Pattern, err)
			}
		}
	}

	// Convert redirects to rewrite rules
	for _, redirect := range yamlConfig.Routes.Redirects {
		if re, err := regexp.Compile(redirect.From); err == nil {
			config.RewriteRules = append(config.RewriteRules, &RewriteRule{
				Pattern:     re,
				Replacement: redirect.To,
				Flag:        "redirect",
			})
		}
	}

	// Convert internal rewrites
	for _, rewrite := range yamlConfig.Routes.Rewrites {
		if re, err := regexp.Compile(rewrite.From); err == nil {
			config.RewriteRules = append(config.RewriteRules, &RewriteRule{
				Pattern:     re,
				Replacement: rewrite.To,
				Flag:        "last",
			})
		}
	}

	// Convert proxy routes
	for _, proxy := range yamlConfig.Routes.Proxies {
		config.ProxyRoutes[proxy.Path] = &ProxyRoute{
			Pattern:    proxy.Path,
			ProxyPass:  proxy.Target,
			SetHeaders: proxy.Headers,
		}
	}

	// Convert fly-replay routes
	for _, flyReplay := range yamlConfig.Routes.FlyReplay {
		if re, err := regexp.Compile(flyReplay.Path); err == nil {
			config.RewriteRules = append(config.RewriteRules, &RewriteRule{
				Pattern:     re,
				Replacement: flyReplay.Path, // Keep original path for fly-replay
				Flag:        fmt.Sprintf("fly-replay:%s:%d", flyReplay.Region, flyReplay.Status),
				Methods:     flyReplay.Methods,
			})
		}
	}

	// Convert reverse proxy routes
	for _, reverseProxy := range yamlConfig.Routes.ReverseProxies {
		config.ProxyRoutes[reverseProxy.Path] = &ProxyRoute{
			Pattern:        reverseProxy.Path,
			ProxyPass:      reverseProxy.Target,
			SetHeaders:     reverseProxy.Headers,
			ExcludeMethods: reverseProxy.ExcludeMethods,
		}
	}

	// Process applications.env to separate global vars from templates
	for varName, value := range yamlConfig.Applications.Env {
		// If the value doesn't contain variables, it's a global env var
		if !strings.Contains(value, "${") {
			config.GlobalEnvVars[varName] = value
		}
	}

	// Convert tenant applications to locations
	for _, tenant := range yamlConfig.Applications.Tenants {
		location := &Location{
			Path:             tenant.Path,
			EnvVars:          make(map[string]string),
			MatchPattern:     tenant.MatchPattern,
			StandaloneServer: tenant.StandaloneServer,
		}

		// Copy tenant environment variables
		for k, v := range tenant.Env {
			location.EnvVars[k] = v
		}

		// Add variables from applications.env that need substitution (unless it's a special tenant)
		if !tenant.Special {
			for varName, template := range yamlConfig.Applications.Env {
				// Only process templates that contain variables
				if strings.Contains(template, "${") {
					value := substituteVars(template, tenant)
					location.EnvVars[varName] = value
				}
			}
		}

		if tenant.Root != "" {
			location.Root = tenant.Root
		} else if yamlConfig.Server.PublicDir != "" {
			location.Root = yamlConfig.Server.PublicDir
		}

		config.Locations[tenant.Path] = location
	}

	// Set process config
	config.PassengerRuby = yamlConfig.Process.Ruby
	config.PreloadBundler = yamlConfig.Process.BundlerPreload
	config.MinInstances = yamlConfig.Process.MinInstances

	// Set logging config
	config.AccessLog = yamlConfig.Logging.AccessLog
	config.ErrorLog = yamlConfig.Logging.ErrorLog

	// Set idle timeout from pools config
	if yamlConfig.Pools.IdleTimeout > 0 {
		config.IdleTimeout = time.Duration(yamlConfig.Pools.IdleTimeout) * time.Second
	} else {
		config.IdleTimeout = 10 * time.Minute // Default
	}

	// Set start port for Rails apps
	if yamlConfig.Pools.StartPort > 0 {
		config.StartPort = yamlConfig.Pools.StartPort
	} else {
		config.StartPort = 4000 // Default
	}

	// Set public directory
	config.PublicDir = yamlConfig.Server.PublicDir

	// Set static file configuration
	config.StaticDirs = []*StaticDir{}
	for _, dir := range yamlConfig.Static.Directories {
		config.StaticDirs = append(config.StaticDirs, &StaticDir{
			URLPath:   dir.Path,
			LocalPath: dir.Root,
			CacheTTL:  dir.Cache,
		})
	}

	// Set static file extensions
	config.StaticExts = yamlConfig.Static.Extensions
	if len(config.StaticExts) == 0 {
		// Default extensions if not specified
		config.StaticExts = []string{"html", "htm", "txt", "xml", "json", "css", "js",
			"png", "jpg", "jpeg", "gif", "svg", "ico", "woff", "woff2", "ttf", "eot"}
	}

	// Set try_files suffixes
	if yamlConfig.Static.TryFiles.Enabled {
		config.TryFilesSuffixes = yamlConfig.Static.TryFiles.Suffixes
		if len(config.TryFilesSuffixes) == 0 {
			// Default suffixes if not specified
			config.TryFilesSuffixes = []string{".html", ".htm", ".txt", ".xml", ".json"}
		}
	}

	// Set managed processes
	config.ManagedProcesses = yamlConfig.ManagedProcesses

	// Set suspend configuration
	config.SuspendEnabled = yamlConfig.Suspend.Enabled
	if yamlConfig.Suspend.IdleTimeout > 0 {
		config.SuspendIdleTimeout = time.Duration(yamlConfig.Suspend.IdleTimeout) * time.Second
	} else {
		config.SuspendIdleTimeout = 10 * time.Minute // Default
	}

	return config, nil
}

// NewAppManager creates a new application manager
func NewAppManager(config *Config) *AppManager {
	idleTimeout := config.IdleTimeout
	if idleTimeout == 0 {
		idleTimeout = 10 * time.Minute // Default if not set
	}

	startPort := config.StartPort
	if startPort == 0 {
		startPort = 4000 // Default if not set
	}

	return &AppManager{
		apps:        make(map[string]*RailsApp),
		config:      config,
		minPort:     startPort,
		maxPort:     startPort + 100, // Allow up to 100 Rails apps
		idleTimeout: idleTimeout,
	}
}

// GetOrStartApp gets an existing app or starts a new one
func (m *AppManager) GetOrStartApp(location *Location) (*RailsApp, error) {
	m.mutex.Lock()
	key := location.Path
	app, exists := m.apps[key]

	if exists {
		m.mutex.Unlock()
		app.mutex.Lock()
		app.LastAccess = time.Now()
		isStarting := app.Starting
		app.mutex.Unlock()

		if !isStarting {
			return app, nil
		}

		// Wait if app is still starting (with timeout)
		timeout := time.NewTimer(30 * time.Second)
		defer timeout.Stop()

		ticker := time.NewTicker(100 * time.Millisecond)
		defer ticker.Stop()

		for {
			select {
			case <-timeout.C:
				return nil, fmt.Errorf("timeout waiting for app %s to start", location.Path)
			case <-ticker.C:
				app.mutex.Lock()
				isStarting := app.Starting
				app.mutex.Unlock()
				if !isStarting {
					return app, nil
				}
			}
		}
	}

	// Find an available port
	port, err := findAvailablePort(m.minPort, m.maxPort)
	if err != nil {
		m.mutex.Unlock()
		return nil, fmt.Errorf("no available ports: %v", err)
	}

	// Start new app
	app = &RailsApp{
		Location:   location,
		Port:       port,
		LastAccess: time.Now(),
		Starting:   true,
	}
	m.apps[key] = app
	m.mutex.Unlock()

	// Start app in background
	go m.startApp(app)

	// Wait for app to start (with timeout)
	timeout := time.NewTimer(30 * time.Second)
	defer timeout.Stop()

	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-timeout.C:
			return nil, fmt.Errorf("timeout starting app %s", location.Path)
		case <-ticker.C:
			app.mutex.Lock()
			isStarting := app.Starting
			app.mutex.Unlock()
			if !isStarting {
				return app, nil
			}
		}
	}
}

// startApp starts a Rails application
func (m *AppManager) startApp(app *RailsApp) {
	ctx, cancel := context.WithCancel(context.Background())
	app.ctx = ctx
	app.cancel = cancel

	// Build environment variables
	env := os.Environ()

	// Add global env vars
	for k, v := range m.config.GlobalEnvVars {
		env = append(env, fmt.Sprintf("%s=%s", k, v))
	}

	// Add location-specific env vars
	for k, v := range app.Location.EnvVars {
		env = append(env, fmt.Sprintf("%s=%s", k, v))
	}

	// Add port
	env = append(env, fmt.Sprintf("PORT=%d", app.Port))

	// Check for and clean up PID file before starting
	pidfilePath := getPidFilePath(app.Location.EnvVars)
	if pidfilePath != "" {
		if err := cleanupPidFile(pidfilePath); err != nil {
			log.Printf("Warning: Error cleaning up PID file for %s: %v", app.Location.Path, err)
		}
	}

	// Change to Rails directory
	railsDir := "/rails"
	if app.Location.Root != "" {
		railsDir = strings.TrimSuffix(app.Location.Root, "/public")
	}

	// Try to use the current working directory if /rails doesn't exist
	if _, err := os.Stat(railsDir); os.IsNotExist(err) {
		if cwd, err := os.Getwd(); err == nil {
			railsDir = cwd
		}
	}

	// Determine which command to use
	var cmd *exec.Cmd

	// Always use rails server directly to control the port
	// bin/dev starts on port 3000 which conflicts with navigator
	binRails := filepath.Join(railsDir, "bin", "rails")
	if _, err := os.Stat(binRails); err == nil {
		cmd = exec.CommandContext(ctx, binRails, "server", "-p", strconv.Itoa(app.Port))
	} else {
		// Fallback to ruby bin/rails
		rubyPath := m.config.PassengerRuby
		if rubyPath == "" {
			rubyPath = "ruby"
		}
		cmd = exec.CommandContext(ctx, rubyPath, "bin/rails", "server", "-p", strconv.Itoa(app.Port))
	}

	cmd.Dir = railsDir
	cmd.Env = env
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	app.mutex.Lock()
	app.Process = cmd
	app.mutex.Unlock()

	log.Printf("Starting Rails app for %s on port %d in %s", app.Location.Path, app.Port, railsDir)

	if err := cmd.Start(); err != nil {
		log.Printf("Failed to start Rails app for %s: %v", app.Location.Path, err)
		app.mutex.Lock()
		app.Starting = false
		app.mutex.Unlock()
		return
	}

	// Wait a moment for Rails to start, then mark as ready
	time.Sleep(5 * time.Second)
	app.mutex.Lock()
	app.Starting = false
	app.mutex.Unlock()
	log.Printf("Rails app for %s ready on port %d", app.Location.Path, app.Port)

	// Wait for process to exit in background
	go func() {
		cmd.Wait()
		log.Printf("Rails app for %s on port %d exited", app.Location.Path, app.Port)

		// Clean up PID file when app exits
		if pidfilePath != "" {
			if err := os.Remove(pidfilePath); err != nil && !os.IsNotExist(err) {
				log.Printf("Warning: Error removing PID file %s: %v", pidfilePath, err)
			}
		}

		// Remove from apps map when process exits
		m.mutex.Lock()
		delete(m.apps, app.Location.Path)
		m.mutex.Unlock()
	}()
}

// StopApp stops a Rails application
func (m *AppManager) StopApp(path string) {
	m.mutex.Lock()
	defer m.mutex.Unlock()

	app, exists := m.apps[path]
	if !exists {
		return
	}

	log.Printf("Stopping Rails app for %s", path)

	// Clean up PID file
	pidfilePath := getPidFilePath(app.Location.EnvVars)
	if pidfilePath != "" {
		if err := os.Remove(pidfilePath); err != nil && !os.IsNotExist(err) {
			log.Printf("Warning: Error removing PID file %s: %v", pidfilePath, err)
		}
	}

	if app.cancel != nil {
		app.cancel()
	}

	delete(m.apps, path)
}

// IdleChecker periodically checks for idle apps and stops them
func (m *AppManager) IdleChecker() {
	ticker := time.NewTicker(1 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		now := time.Now()
		m.mutex.RLock()
		toStop := []string{}

		for path, app := range m.apps {
			app.mutex.RLock()
			if now.Sub(app.LastAccess) > m.idleTimeout {
				toStop = append(toStop, path)
			}
			app.mutex.RUnlock()
		}
		m.mutex.RUnlock()

		for _, path := range toStop {
			log.Printf("Stopping idle app: %s", path)
			m.StopApp(path)
		}
	}
}

// LoadAuthFile loads the htpasswd file for basic authentication
func LoadAuthFile(filename, realm string, exclude []string) (*BasicAuth, error) {
	if filename == "" {
		return nil, nil
	}

	// Use go-htpasswd library to load the file
	htFile, err := htpasswd.New(filename, htpasswd.DefaultSystems, nil)
	if err != nil {
		return nil, err
	}

	auth := &BasicAuth{
		File:    htFile,
		Realm:   realm,
		Exclude: exclude,
	}

	return auth, nil
}

// CreateHandler creates the main HTTP handler
func CreateHandler(config *Config, manager *AppManager, auth *BasicAuth, suspendManager *SuspendManager) http.Handler {
	mux := http.NewServeMux()

	// Health check
	mux.HandleFunc("/up", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Main handler
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Track request for suspend management
		suspendManager.RequestStarted()
		defer suspendManager.RequestFinished()

		slog.Debug("Request received", "method", r.Method, "path", r.URL.Path)

		// Handle rewrites/redirects first
		if handleRewrites(w, r, config) {
			return
		}

		// Check if path should be excluded from auth using parsed patterns
		// This tells us if the path is "public" regardless of whether auth is actually enabled
		isPublicPath := shouldExcludeFromAuth(r.URL.Path, config)
		needsAuth := auth != nil && auth.Realm != "off" && !isPublicPath
		slog.Debug("Auth check", "needed", needsAuth, "isPublic", isPublicPath)

		// Apply basic auth if needed
		if needsAuth && !checkAuth(r, auth) {
			w.Header().Set("WWW-Authenticate", fmt.Sprintf(`Basic realm="%s"`, auth.Realm))
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		// Try to serve static files first (assets, images, etc.)
		if serveStaticFile(w, r, config) {
			return
		}

		// Find matching location early to determine if this is a Rails app
		var bestMatch *Location
		bestMatchLen := 0

		// First, check for pattern matches
		for _, location := range config.Locations {
			if location.MatchPattern != "" {
				if matched, _ := filepath.Match(location.MatchPattern, r.URL.Path); matched {
					bestMatch = location
					break // Pattern matches take priority
				}
			}
		}

		// If no pattern match, use prefix matching (existing logic)
		if bestMatch == nil {
			for path, location := range config.Locations {
				if strings.HasPrefix(r.URL.Path, path) && len(path) > bestMatchLen {
					bestMatch = location
					bestMatchLen = len(path)
				}
			}
		}

		// Try tryFiles for public paths (those that would be excluded from auth)
		// This ensures static content is served for public paths like /showcase/regions/
		// while Rails apps (which would require auth if enabled) are always proxied
		if isPublicPath && tryFiles(w, r, config) {
			return
		}

		// Check for proxy routes (PDF/XLSX and reverse proxies)
		for pattern, route := range config.ProxyRoutes {
			matched, _ := regexp.MatchString(pattern, r.URL.Path)
			if matched {
				// Check if method should be excluded
				excluded := false
				for _, excludeMethod := range route.ExcludeMethods {
					if r.Method == excludeMethod {
						excluded = true
						break
					}
				}

				// Only proxy if method is not excluded
				if !excluded {
					proxyRequest(w, r, route)
					return
				}
			}
		}

		// Now check if we still don't have a match (moved from after proxy routes)
		if bestMatch == nil {
			// Try root location
			if rootLoc, ok := config.Locations["/"]; ok {
				slog.Debug("No specific location match, using root location")
				bestMatch = rootLoc
			} else {
				// Delegate to health check handler
				slog.Debug("No location match found", "path", r.URL.Path)
				mux.ServeHTTP(w, r)
				return
			}
		}

		// Check if this should be routed to a standalone server
		if bestMatch.StandaloneServer != "" {
			target, err := url.Parse(fmt.Sprintf("http://%s", bestMatch.StandaloneServer))
			if err != nil {
				http.Error(w, "Invalid standalone server configuration", http.StatusInternalServerError)
				return
			}
			proxyWithRetry(w, r, target, 3*time.Second)
			return
		}

		// Get or start the Rails app
		app, err := manager.GetOrStartApp(bestMatch)
		if err != nil {
			http.Error(w, "Failed to start application", http.StatusInternalServerError)
			return
		}

		// Proxy to Rails app
		target, _ := url.Parse(fmt.Sprintf("http://localhost:%d", app.Port))

		// For Rails apps, preserve the full path - don't strip the location prefix
		// Rails routing expects to see the full path like "/2025/adelaide/adelaide-combined/"
		// Only strip if the location is "/" (root)
		originalPath := r.URL.Path
		if bestMatch.Path != "/" {
			// Don't modify the path - Rails needs to see the full path
			// The RAILS_APP_SCOPE environment variable tells Rails what prefix to expect
		} else {
			// Root location - path is already correct
		}

		// Add headers
		r.Header.Set("X-Forwarded-For", r.RemoteAddr)
		r.Header.Set("X-Forwarded-Host", r.Host)
		r.Header.Set("X-Forwarded-Proto", "http")

		slog.Info("Proxying to Rails", "path", originalPath, "port", app.Port, "location", bestMatch.Path)

		// Use retry logic for Rails apps too
		proxyWithRetry(w, r, target, 3*time.Second)
	})
}

// checkAuth checks basic authentication
func checkAuth(r *http.Request, auth *BasicAuth) bool {
	username, password, ok := r.BasicAuth()
	if !ok {
		return false
	}

	// Use go-htpasswd library to match the password
	return auth.File.Match(username, password)
}

// handleRewrites handles rewrite rules from config
func handleRewrites(w http.ResponseWriter, r *http.Request, config *Config) bool {
	path := r.URL.Path

	slog.Debug("Checking rewrites", "path", path, "rulesCount", len(config.RewriteRules))

	for _, rule := range config.RewriteRules {
		slog.Debug("Checking rewrite rule", "pattern", rule.Pattern.String())
		if rule.Pattern.MatchString(path) {
			// Apply the rewrite
			newPath := rule.Pattern.ReplaceAllString(path, rule.Replacement)
			slog.Debug("Rewrite matched", "originalPath", path, "newPath", newPath, "flag", rule.Flag)

			if rule.Flag == "redirect" {
				http.Redirect(w, r, newPath, http.StatusFound)
				return true
			} else if strings.HasPrefix(rule.Flag, "fly-replay:") {
				// Handle fly-replay: fly-replay:region:status
				parts := strings.Split(rule.Flag, ":")
				if len(parts) == 3 {
					region := parts[1]
					status := parts[2]

					// Check if method is allowed for this rule
					methodAllowed := len(rule.Methods) == 0 // If no methods specified, allow all
					if len(rule.Methods) > 0 {
						for _, method := range rule.Methods {
							if r.Method == method {
								methodAllowed = true
								break
							}
						}
					}

					if methodAllowed {
						if shouldUseFlyReplay(r) {
							// Check if target machine is available via DNS or if this is a retry
							if !checkTargetMachineAvailable(region) || r.Header.Get("X-Navigator-Retry") == "true" {
								// Target machine unavailable or retry detected, serve maintenance page
								slog.Info("Target machine unavailable or retry detected, serving maintenance page",
									"path", path,
									"region", region,
									"method", r.Method,
									"navigatorRetry", r.Header.Get("X-Navigator-Retry"))

								serveMaintenancePage(w, r, config)
								return true
							}

							w.Header().Set("Fly-Replay", fmt.Sprintf("region=%s", region))
							w.Header().Set("Content-Type", "application/json")
							statusCode := http.StatusTemporaryRedirect
							if code, err := strconv.Atoi(status); err == nil {
								statusCode = code
							}

							// Log all request headers for debugging
							for name, values := range r.Header {
								for _, value := range values {
									slog.Info("Request header", "name", name, "value", value)
								}
							}

							slog.Info("Sending fly-replay response",
								"path", path,
								"region", region,
								"status", statusCode,
								"method", r.Method,
								"contentLength", r.ContentLength)

							w.WriteHeader(statusCode)

							// Write the JSON body with transform instructions
							responseMap := map[string]interface{}{
								"transform": map[string]interface{}{
									"remove-headers": []string{"Fly-Region"},
									"set_headers": []map[string]string{
										{"name": "X-Navigator-Retry", "value": "true"},
										{"name": "Fly-Prefer-Region", "value": region},
									},
								},
							}

							responseBodyBytes, err := json.Marshal(responseMap)
							if err != nil {
								http.Error(w, "Internal Server Error", http.StatusInternalServerError)
								return true
							}
							slog.Info("Fly replay response body", "body", string(responseBodyBytes))
							w.Write(responseBodyBytes)
							return true
						} else {
							// Automatically reverse proxy instead of fly-replay
							return handleFlyReplayFallback(w, r, region, config)
						}
					}
				}
			} else if rule.Flag == "last" {
				// Internal rewrite, modify the path and continue
				r.URL.Path = newPath
				// Don't return true for "last" - continue processing
			} else {
				// Default behavior for rewrites without flags
				r.URL.Path = newPath
			}
		}
	}

	slog.Debug("No rewrite rules matched", "path", path)
	return false
}

// shouldUseFlyReplay determines if a request should use fly-replay based on content length
// Fly replay can handle any method as long as the content length is less than 1MB
func shouldUseFlyReplay(r *http.Request) bool {
	const maxFlyReplaySize = 1000000 // 1 million bytes

	// If Content-Length is explicitly set and >= 1MB, use reverse proxy
	if r.ContentLength >= maxFlyReplaySize {
		slog.Debug("Using reverse proxy due to large content length",
			"method", r.Method,
			"contentLength", r.ContentLength)
		return false
	}

	// If Content-Length is missing (-1) on methods that typically require content
	// (POST, PUT, PATCH), be conservative and use reverse proxy
	if r.ContentLength == -1 {
		methodsRequiringContent := []string{"POST", "PUT", "PATCH"}
		for _, method := range methodsRequiringContent {
			if r.Method == method {
				slog.Debug("Using reverse proxy due to missing content length on body method",
					"method", r.Method)
				return false
			}
		}
	}

	// For GET, HEAD, DELETE, OPTIONS and other methods without content, or
	// methods with content < 1MB, use fly-replay
	return true
}

// checkTargetMachineAvailable checks if the target machine is available via IPv6 DNS
// This helps detect if a machine is in the process of redeploying
// Results are cached to avoid expensive DNS lookups
func checkTargetMachineAvailable(region string) bool {
	// DNS check is disabled by default - must be explicitly enabled
	if os.Getenv("ENABLE_DNS_CHECK") == "" {
		return true // Default: assume target is available
	}

	flyAppName := os.Getenv("FLY_APP_NAME")
	if flyAppName == "" {
		return true // Can't check without app name, assume available
	}

	// Check cache first
	if available, found := dnsCache.Get(region); found {
		slog.Debug("DNS cache hit for target machine",
			"region", region,
			"available", available)
		return available
	}

	// Construct the IPv6 DNS name for the target machine
	dnsName := fmt.Sprintf("%s.%s.internal", region, flyAppName)

	// Set a reasonable timeout for DNS lookup
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	// Perform IPv6 DNS lookup
	resolver := &net.Resolver{}
	addrs, err := resolver.LookupIPAddr(ctx, dnsName)
	if err != nil {
		slog.Debug("DNS lookup failed for target machine",
			"dnsName", dnsName,
			"error", err)
		// Cache negative result
		dnsCache.Set(region, false)
		return false
	}

	// Check if we found any IPv6 addresses
	hasIPv6 := false
	for _, addr := range addrs {
		if addr.IP.To4() == nil { // IPv6 address
			hasIPv6 = true
			break
		}
	}

	slog.Debug("DNS lookup result for target machine",
		"dnsName", dnsName,
		"addressCount", len(addrs),
		"hasIPv6", hasIPv6)

	// Cache the result
	dnsCache.Set(region, hasIPv6)
	return hasIPv6
}

// serveMaintenancePage serves a maintenance page when target machine is unavailable
func serveMaintenancePage(w http.ResponseWriter, r *http.Request, config *Config) {
	// Set appropriate status code
	w.WriteHeader(http.StatusServiceUnavailable)

	// Try to serve the configured maintenance page file
	maintenancePath := config.MaintenancePage
	if maintenancePath == "" {
		maintenancePath = "/503.html" // Default fallback
	}
	if config.PublicDir != "" {
		fullPath := filepath.Join(config.PublicDir, maintenancePath)
		if content, err := os.ReadFile(fullPath); err == nil {
			// Set content type based on file extension
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
			w.Header().Set("Pragma", "no-cache")
			w.Header().Set("Expires", "0")

			w.Write(content)
			slog.Debug("Served maintenance page from file", "path", fullPath)
			return
		} else {
			slog.Debug("Could not read maintenance page file", "path", fullPath, "error", err)
		}
	}

	// Fallback to simple HTML response if no maintenance page file found
	fallbackHTML := `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Service Temporarily Unavailable</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; background-color: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #d73502; }
        p { color: #666; line-height: 1.6; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Service Temporarily Unavailable</h1>
        <p>The service you are trying to reach is currently unavailable. This may be due to maintenance or a temporary deployment.</p>
        <p>Please try again in a few minutes.</p>
    </div>
</body>
</html>`

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
	w.Header().Set("Pragma", "no-cache")
	w.Header().Set("Expires", "0")

	w.Write([]byte(fallbackHTML))
	slog.Debug("Served fallback maintenance page")
}

// handleFlyReplayFallback automatically reverse proxies the request when fly-replay isn't suitable
// Constructs the target URL as http://<region>.<FLY_APP_NAME>.internal:<port><path>
func handleFlyReplayFallback(w http.ResponseWriter, r *http.Request, region string, config *Config) bool {
	flyAppName := os.Getenv("FLY_APP_NAME")
	if flyAppName == "" {
		slog.Debug("FLY_APP_NAME not set, cannot construct fallback proxy URL")
		return false
	}

	// Construct the target URL: http://<region>.<FLY_APP_NAME>.internal:<port><path>
	listenPort := config.ListenPort
	if listenPort == 0 {
		listenPort = 3000 // Default port
	}

	targetURL := fmt.Sprintf("http://%s.%s.internal:%d%s", region, flyAppName, listenPort, r.URL.Path)
	if r.URL.RawQuery != "" {
		targetURL += "?" + r.URL.RawQuery
	}

	target, err := url.Parse(targetURL)
	if err != nil {
		slog.Debug("Failed to parse fallback proxy URL", "url", targetURL, "error", err)
		return false
	}

	// Set forwarding headers
	r.Header.Set("X-Forwarded-Host", r.Host)

	slog.Info("Using automatic reverse proxy fallback for fly-replay",
		"originalPath", r.URL.Path,
		"targetURL", targetURL,
		"region", region,
		"method", r.Method,
		"contentLength", r.ContentLength)

	// Use the existing retry proxy logic
	proxyWithRetry(w, r, target, 3*time.Second)
	return true
}

// shouldExcludeFromAuth checks if a path should be excluded from authentication using parsed patterns
func shouldExcludeFromAuth(path string, config *Config) bool {
	// Check simple exclusion paths first (from YAML public_paths)
	for _, excludePath := range config.AuthExclude {
		// Handle glob patterns like *.css
		if strings.HasPrefix(excludePath, "*") {
			if strings.HasSuffix(path, excludePath[1:]) {
				return true
			}
		} else if strings.Contains(excludePath, "*") {
			// Handle patterns like /path/*.ext
			if matched, _ := filepath.Match(excludePath, path); matched {
				return true
			}
		} else {
			// Check for prefix match (paths ending with /)
			if strings.HasSuffix(excludePath, "/") {
				if strings.HasPrefix(path, excludePath) {
					return true
				}
			} else {
				// Exact match
				if path == excludePath {
					return true
				}
			}
		}
	}

	// Check regex auth patterns from the config file
	for _, authPattern := range config.AuthPatterns {
		if authPattern.Pattern.MatchString(path) && authPattern.Action == "off" {
			return true
		}
	}

	return false
}

// serveStaticFile attempts to serve static files directly from the filesystem
func serveStaticFile(w http.ResponseWriter, r *http.Request, config *Config) bool {
	// Check if this is a request for static assets
	path := r.URL.Path

	slog.Debug("Checking static file",
		"path", path,
		"staticDirsCount", len(config.StaticDirs),
		"publicDir", config.PublicDir)

	// First check static directories from config
	for _, staticDir := range config.StaticDirs {
		slog.Debug("Checking static dir",
			"urlPath", staticDir.URLPath,
			"localPath", staticDir.LocalPath)
		if strings.HasPrefix(path, staticDir.URLPath) {
			// Calculate the local file path
			relativePath := strings.TrimPrefix(path, staticDir.URLPath)
			fsPath := filepath.Join(config.PublicDir, staticDir.LocalPath, relativePath)

			slog.Debug("Checking file", "fsPath", fsPath)

			// Check if file exists
			if info, err := os.Stat(fsPath); err == nil && !info.IsDir() {
				// Set cache headers if configured
				if staticDir.CacheTTL > 0 {
					w.Header().Set("Cache-Control", fmt.Sprintf("public, max-age=%d", staticDir.CacheTTL))
				}

				// Set content type and serve
				setContentType(w, fsPath)
				http.ServeFile(w, r, fsPath)
				slog.Info("Serving static file", "path", path, "fsPath", fsPath)
				return true
			} else {
				slog.Debug("File not found or is directory",
					"error", err,
					"isDir", info != nil && info.IsDir())
			}
		}
	}

	// Check if file has a static extension from config
	isStatic := false
	ext := strings.TrimPrefix(filepath.Ext(path), ".")
	if ext != "" {
		for _, staticExt := range config.StaticExts {
			if ext == staticExt {
				isStatic = true
				break
			}
		}
	}

	if !isStatic {
		return false
	}

	// Find the best matching location for this path
	var bestMatch *Location
	bestMatchLen := 0

	for locPath, location := range config.Locations {
		if strings.HasPrefix(path, locPath) && len(locPath) > bestMatchLen {
			bestMatch = location
			bestMatchLen = len(locPath)
		}
	}

	if bestMatch == nil || bestMatch.Root == "" {
		return false
	}

	// Construct the filesystem path
	// Remove the location prefix from the URL path
	relativePath := strings.TrimPrefix(path, bestMatch.Path)
	if relativePath == "" || relativePath[0] != '/' {
		relativePath = "/" + relativePath
	}

	// The root typically ends with /public, and we need to serve from there
	fsPath := filepath.Join(bestMatch.Root, relativePath)

	// Check if file exists
	if _, err := os.Stat(fsPath); os.IsNotExist(err) {
		// If not found in root, try in public directory explicitly
		publicPath := filepath.Join(strings.TrimSuffix(bestMatch.Root, "/public"), "public", relativePath)
		if _, err := os.Stat(publicPath); os.IsNotExist(err) {
			return false
		}
		fsPath = publicPath
	}

	// Set content type and serve the file
	setContentType(w, fsPath)
	http.ServeFile(w, r, fsPath)
	log.Printf("Serving static file: %s -> %s", path, fsPath)
	return true
}

// tryFiles implements try_files behavior for non-authenticated routes
// Attempts to serve static files with common extensions before falling back to Rails
func tryFiles(w http.ResponseWriter, r *http.Request, config *Config) bool {
	path := r.URL.Path

	slog.Debug("tryFiles checking", "path", path)

	// Only try files for paths that don't already have an extension
	if filepath.Ext(path) != "" {
		slog.Debug("tryFiles skipping - path has extension")
		return false
	}

	// Skip if try_files is disabled (no suffixes configured)
	if len(config.TryFilesSuffixes) == 0 {
		slog.Debug("tryFiles disabled - no suffixes configured")
		return false
	}

	// First, check static directories from config
	var bestStaticDir *StaticDir
	bestStaticDirLen := 0

	for _, staticDir := range config.StaticDirs {
		if strings.HasPrefix(path, staticDir.URLPath) && len(staticDir.URLPath) > bestStaticDirLen {
			bestStaticDir = staticDir
			bestStaticDirLen = len(staticDir.URLPath)
		}
	}

	// If we found a matching static directory, try to serve from there
	if bestStaticDir != nil {
		// Remove the URL prefix to get the relative path
		relativePath := strings.TrimPrefix(path, bestStaticDir.URLPath)
		if relativePath == "" {
			relativePath = "/"
		}
		if relativePath[0] != '/' {
			relativePath = "/" + relativePath
		}

		// Use extensions from config
		extensions := config.TryFilesSuffixes

		for _, ext := range extensions {
			// Build the full filesystem path
			fsPath := filepath.Join(config.PublicDir, bestStaticDir.LocalPath, relativePath+ext)
			slog.Debug("tryFiles checking static", "fsPath", fsPath)
			if _, err := os.Stat(fsPath); err == nil {
				return serveFile(w, r, fsPath, path+ext)
			}
		}
	}

	// Fall back to checking locations (for backward compatibility)
	var bestMatch *Location
	bestMatchLen := 0

	for locPath, location := range config.Locations {
		if strings.HasPrefix(path, locPath) && len(locPath) > bestMatchLen {
			bestMatch = location
			bestMatchLen = len(locPath)
		}
	}

	if bestMatch == nil || bestMatch.Root == "" {
		return false
	}

	// Remove the location prefix from the URL path
	relativePath := strings.TrimPrefix(path, bestMatch.Path)
	if relativePath == "" || relativePath[0] != '/' {
		relativePath = "/" + relativePath
	}

	// Use extensions from config
	extensions := config.TryFilesSuffixes

	for _, ext := range extensions {
		// Try in the root directory first
		fsPath := filepath.Join(bestMatch.Root, relativePath+ext)
		if _, err := os.Stat(fsPath); err == nil {
			return serveFile(w, r, fsPath, path+ext)
		}

		// If not found in root, try in public directory explicitly
		publicPath := filepath.Join(strings.TrimSuffix(bestMatch.Root, "/public"), "public", relativePath+ext)
		if _, err := os.Stat(publicPath); err == nil {
			return serveFile(w, r, publicPath, path+ext)
		}
	}

	return false
}

// serveFile serves a specific file with appropriate headers
func serveFile(w http.ResponseWriter, r *http.Request, fsPath, requestPath string) bool {
	// Set appropriate content type
	setContentType(w, fsPath)

	// Serve the file
	http.ServeFile(w, r, fsPath)
	log.Printf("Try files: %s -> %s", requestPath, fsPath)
	return true
}

// setContentType sets the appropriate Content-Type header based on file extension
func setContentType(w http.ResponseWriter, fsPath string) {
	ext := filepath.Ext(fsPath)
	switch ext {
	case ".js":
		w.Header().Set("Content-Type", "application/javascript")
	case ".css":
		w.Header().Set("Content-Type", "text/css")
	case ".html", ".htm":
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
	case ".txt":
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	case ".xml":
		w.Header().Set("Content-Type", "application/xml; charset=utf-8")
	case ".json":
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
	case ".png":
		w.Header().Set("Content-Type", "image/png")
	case ".jpg", ".jpeg":
		w.Header().Set("Content-Type", "image/jpeg")
	case ".gif":
		w.Header().Set("Content-Type", "image/gif")
	case ".svg":
		w.Header().Set("Content-Type", "image/svg+xml")
	case ".ico":
		w.Header().Set("Content-Type", "image/x-icon")
	case ".pdf":
		w.Header().Set("Content-Type", "application/pdf")
	case ".xlsx":
		w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
	case ".woff":
		w.Header().Set("Content-Type", "font/woff")
	case ".woff2":
		w.Header().Set("Content-Type", "font/woff2")
	case ".ttf":
		w.Header().Set("Content-Type", "font/ttf")
	case ".eot":
		w.Header().Set("Content-Type", "application/vnd.ms-fontobject")
	}
}

// proxyWithRetry handles proxying with automatic retry on 502 errors
func proxyWithRetry(w http.ResponseWriter, r *http.Request, target *url.URL, maxRetryDuration time.Duration) {
	startTime := time.Now()
	retryCount := 0
	sleepDuration := 100 * time.Millisecond // Start with 100ms

	for {
		// Create a new proxy for each attempt
		proxy := httputil.NewSingleHostReverseProxy(target)

		// Track if we got an error
		errorOccurred := false
		errorHandled := false

		// Custom error handler to detect connection errors
		proxy.ErrorHandler = func(rw http.ResponseWriter, req *http.Request, err error) {
			errorOccurred = true

			// Check if we should retry
			if time.Since(startTime) < maxRetryDuration {
				// We'll retry, don't write response yet
				return
			}

			// Max retry time exceeded or non-retryable error
			if !errorHandled {
				errorHandled = true
				slog.Warn("Proxy error after retries",
					"target", target.String(),
					"error", err,
					"retries", retryCount,
					"duration", time.Since(startTime))
				http.Error(rw, "Bad Gateway", http.StatusBadGateway)
			}
		}

		// Attempt the proxy request
		proxy.ServeHTTP(w, r)

		// If no error occurred, we're done
		if !errorOccurred {
			return
		}

		// Check if we've exceeded max retry duration
		if time.Since(startTime) >= maxRetryDuration {
			if !errorHandled {
				slog.Warn("Proxy retry timeout",
					"target", target.String(),
					"retries", retryCount,
					"duration", time.Since(startTime))
				http.Error(w, "Bad Gateway", http.StatusBadGateway)
			}
			return
		}

		// Log retry attempt
		retryCount++
		slog.Debug("Retrying proxy request",
			"target", target.String(),
			"retry", retryCount,
			"sleep", sleepDuration)

		// Sleep before retry with exponential backoff
		time.Sleep(sleepDuration)
		sleepDuration = sleepDuration * 2
		if sleepDuration > 500*time.Millisecond {
			sleepDuration = 500 * time.Millisecond // Cap at 500ms
		}

		// Clone the request for retry (body might have been consumed)
		if r.Body != nil && r.ContentLength > 0 {
			// For retries with body, we'd need to buffer the body
			// For now, we'll only retry GET/HEAD requests without body
			if r.Method != "GET" && r.Method != "HEAD" {
				slog.Debug("Not retrying request with body", "method", r.Method)
				http.Error(w, "Bad Gateway", http.StatusBadGateway)
				return
			}
		}
	}
}

// proxyRequest proxies a request to another server with retry logic
func proxyRequest(w http.ResponseWriter, r *http.Request, route *ProxyRoute) {
	target, err := url.Parse(route.ProxyPass)
	if err != nil {
		http.Error(w, "Invalid proxy target", http.StatusInternalServerError)
		return
	}

	// Add custom headers
	for k, v := range route.SetHeaders {
		r.Header.Set(k, v)
	}

	// Use the retry proxy helper
	proxyWithRetry(w, r, target, 3*time.Second)
}
