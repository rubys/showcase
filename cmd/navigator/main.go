package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
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

// Constants for configuration defaults and limits
const (
	// Timeout constants
	DefaultIdleTimeout  = 10 * time.Minute
	RailsStartupTimeout = 30 * time.Second
	ProxyRetryTimeout   = 3 * time.Second
	ProcessStopTimeout  = 10 * time.Second
	RailsStartupDelay   = 5 * time.Second

	// Port configuration
	DefaultStartPort  = 4000
	MaxPortRange      = 100
	DefaultListenPort = 3000

	// Proxy configuration
	MaxFlyReplaySize       = 1000000 // 1MB
	ProxyRetryInitialDelay = 100 * time.Millisecond
	ProxyRetryMaxDelay     = 500 * time.Millisecond

	// File paths
	NavigatorPIDFile       = "/tmp/navigator.pid"
	DefaultMaintenancePage = "/503.html"
)

// ManagedProcessConfig represents configuration for a managed process
type ManagedProcessConfig struct {
	Name        string            `yaml:"name"`
	Command     string            `yaml:"command"`
	Args        []string          `yaml:"args"`
	WorkingDir  string            `yaml:"working_dir"`
	Env         map[string]string `yaml:"env"`
	AutoRestart bool              `yaml:"auto_restart"`
	StartDelay  int               `yaml:"start_delay"`
}

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

// LogConfig represents logging configuration
type LogConfig struct {
	Format string `yaml:"format"` // "text" or "json"
	File   string `yaml:"file"`   // Optional file output path (supports {{app}} template)
	Vector struct {
		Enabled bool   `yaml:"enabled"` // Enable Vector integration
		Socket  string `yaml:"socket"`  // Unix socket path for Vector
		Config  string `yaml:"config"`  // Path to vector.toml configuration
	} `yaml:"vector"`
}

// HookConfig represents a hook command configuration
type HookConfig struct {
	Command string   `yaml:"command"`
	Args    []string `yaml:"args"`
	Timeout int      `yaml:"timeout"` // Timeout in seconds, 0 for no timeout
}

// ServerHooks represents server lifecycle hooks
type ServerHooks struct {
	Start []HookConfig `yaml:"start"` // Before accepting requests
	Ready []HookConfig `yaml:"ready"` // Once accepting requests
	Idle  []HookConfig `yaml:"idle"`  // Before suspend
}

// TenantHooks represents tenant lifecycle hooks
type TenantHooks struct {
	Start []HookConfig `yaml:"start"` // After tenant starts
	Stop  []HookConfig `yaml:"stop"`  // Before tenant stops
}

// Config represents the parsed configuration
type Config struct {
	ServerName       string
	ListenPort       int
	MaxPoolSize      int
	AuthFile         string
	AuthRealm        string
	AuthExclude      []string
	AuthPatterns     []*AuthPattern
	RewriteRules     []*RewriteRule
	ProxyRoutes      map[string]*ProxyRoute
	Locations        map[string]*Location
	GlobalEnvVars    map[string]string
	Framework        FrameworkConfig // Framework-specific configuration
	IdleTimeout      time.Duration          // Idle timeout for app processes
	StartPort        int                    // Starting port for web apps
	StaticDirs       []*StaticDir           // Static directory mappings
	StaticExts       []string               // File extensions to serve statically
	TryFilesSuffixes []string               // Suffixes for try_files behavior
	PublicDir        string                 // Default public directory
	MaintenancePage  string                 // Path to maintenance page (e.g., "/503.html")
	ManagedProcesses []ManagedProcessConfig // Managed processes to start/stop with Navigator
	Logging          LogConfig              // Logging configuration

	// Machine idle configuration
	MachineIdleAction  string        // "suspend", "stop", or empty
	MachineIdleTimeout time.Duration // Duration before machine idle action
	
	// Hooks configuration
	ServerHooks        ServerHooks // Server lifecycle hooks
	DefaultTenantHooks TenantHooks // Default hooks for all tenants
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
	ExcludeMethods []string // Methods to exclude from proxying
}

// Location represents a web application location
type Location struct {
	Path             string
	Root             string
	EnvVars          map[string]string
	MatchPattern     string      // Pattern for matching request paths (e.g., "*/cable")
	StandaloneServer string      // If set, proxy to this server instead of web app
	Hooks            TenantHooks // Tenant-specific hooks
}

// WebApp represents a running web application
type WebApp struct {
	Location   *Location
	Process    *exec.Cmd
	Port       int
	LastAccess time.Time
	Starting   bool
	mutex      sync.RWMutex
	ctx        context.Context
	cancel     context.CancelFunc
}

// FrameworkConfig represents framework-specific configuration
type FrameworkConfig struct {
	Command      string   `yaml:"command"`       // e.g., "ruby", "node", "python", "bin/rails"
	Args         []string `yaml:"args"`          // e.g., ["server", "-p", "${port}"]
	AppDirectory string   `yaml:"app_directory"` // e.g., "/rails", "/app"
	PortEnvVar   string   `yaml:"port_env_var"`  // e.g., "PORT"
	StartupDelay int      `yaml:"startup_delay"` // seconds to wait before marking ready
}

// Tenant represents a tenant configuration with optional framework overrides
type Tenant struct {
	Path                       string            `yaml:"path"`
	Root                       string            `yaml:"root"`
	Special                    bool              `yaml:"special"`
	MatchPattern               string            `yaml:"match_pattern"`
	StandaloneServer           string            `yaml:"standalone_server"`
	Env                        map[string]string `yaml:"env"`
	Var                        map[string]string `yaml:"var"`
	ForceMaxConcurrentRequests int               `yaml:"force_max_concurrent_requests"`
	Hooks                      TenantHooks       `yaml:"hooks"` // Tenant-specific hooks
}

// YAMLConfig represents the new YAML configuration format
type YAMLConfig struct {
	Server struct {
		Listen    int    `yaml:"listen"`
		Hostname  string `yaml:"hostname"`
		RootPath  string `yaml:"root_path"`
		PublicDir string `yaml:"public_dir"`
		Idle      struct {
			Action  string `yaml:"action"`  // "suspend", "stop", or empty
			Timeout string `yaml:"timeout"` // Duration string like "20m", "1h30m"
		} `yaml:"idle"`
	} `yaml:"server"`

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
			App     string   `yaml:"app"`
			Machine string   `yaml:"machine"`
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
		} `yaml:"try_files"`
	} `yaml:"static"`

	Applications struct {
		Framework FrameworkConfig   `yaml:"framework"`
		Env       map[string]string `yaml:"env"`
		Tenants   []Tenant          `yaml:"tenants"`
		Pools     struct {
			MaxSize   int    `yaml:"max_size"`
			Timeout   string `yaml:"timeout"` // Duration string like "5m", "30s"
			StartPort int    `yaml:"start_port"`
		} `yaml:"pools"`
	} `yaml:"applications"`



	ManagedProcesses []ManagedProcessConfig `yaml:"managed_processes"`
	Logging          LogConfig              `yaml:"logging"`
	
	Hooks struct {
		Server ServerHooks `yaml:"server"`
		Tenant TenantHooks `yaml:"tenant"` // Default hooks for all tenants
	} `yaml:"hooks"`
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
	config    *Config
	mutex     sync.RWMutex
	wg        sync.WaitGroup
}

// IdleManager tracks active requests and handles machine idle actions (suspend/stop)
type IdleManager struct {
	enabled        bool
	action         string        // "suspend" or "stop"
	idleTimeout    time.Duration
	activeRequests int64
	lastActivity   time.Time
	mutex          sync.RWMutex
	timer          *time.Timer
	config         *Config
}

// AppManager manages web application processes
type AppManager struct {
	apps        map[string]*WebApp
	config      *Config
	mutex       sync.RWMutex
	idleTimeout time.Duration
	minPort     int // Minimum port for web apps
	maxPort     int // Maximum port for web apps
}

// LogWriter wraps output streams to add source identification
type LogWriter struct {
	source string     // app name or process name
	stream string     // "stdout" or "stderr"
	output io.Writer
}

// Write implements io.Writer interface, prefixing each line with source metadata
func (w *LogWriter) Write(p []byte) (n int, err error) {
	// Split input into lines
	lines := bytes.Split(p, []byte("\n"))
	for i, line := range lines {
		// Skip empty lines at the end
		if len(line) == 0 && i == len(lines)-1 {
			continue
		}
		// Write prefixed line
		prefix := fmt.Sprintf("[%s.%s] ", w.source, w.stream)
		w.output.Write([]byte(prefix))
		w.output.Write(line)
		w.output.Write([]byte("\n"))
	}
	return len(p), nil
}

// LogEntry represents a structured log entry
type LogEntry struct {
	Timestamp string `json:"@timestamp"`
	Source    string `json:"source"`
	Stream    string `json:"stream"`
	Message   string `json:"message"`
	Tenant    string `json:"tenant,omitempty"`
}

// JSONLogWriter writes structured JSON log entries
type JSONLogWriter struct {
	source string
	stream string
	tenant string
	output io.Writer
}

// Write implements io.Writer interface, outputting JSON log entries
func (w *JSONLogWriter) Write(p []byte) (n int, err error) {
	lines := bytes.Split(p, []byte("\n"))
	for _, line := range lines {
		if len(line) == 0 {
			continue
		}
		entry := LogEntry{
			Timestamp: time.Now().Format(time.RFC3339),
			Source:    w.source,
			Stream:    w.stream,
			Message:   string(line),
			Tenant:    w.tenant,
		}
		data, _ := json.Marshal(entry)
		w.output.Write(data)
		w.output.Write([]byte("\n"))
	}
	return len(p), nil
}

// MultiLogWriter writes to multiple outputs simultaneously
type MultiLogWriter struct {
	outputs []io.Writer
}

// Write implements io.Writer interface, writing to all configured outputs
func (m *MultiLogWriter) Write(p []byte) (n int, err error) {
	for _, output := range m.outputs {
		output.Write(p)
	}
	return len(p), nil
}

// createFileWriter creates a file writer with the specified path
// The path can contain {{app}} which will be replaced with the app name
func createFileWriter(path string, appName string) (io.Writer, error) {
	// Replace {{app}} template with actual app name
	logPath := strings.ReplaceAll(path, "{{app}}", appName)
	
	// Create directory if it doesn't exist
	dir := filepath.Dir(logPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create log directory %s: %w", dir, err)
	}
	
	// Open file for append (create if doesn't exist)
	file, err := os.OpenFile(logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return nil, fmt.Errorf("failed to open log file %s: %w", logPath, err)
	}
	
	return file, nil
}

// VectorWriter writes logs to Vector via Unix socket
type VectorWriter struct {
	socket string
	conn   net.Conn
	mutex  sync.Mutex
}

// NewVectorWriter creates a new Vector writer
func NewVectorWriter(socket string) *VectorWriter {
	return &VectorWriter{socket: socket}
}

// Write implements io.Writer interface for Vector output
func (v *VectorWriter) Write(p []byte) (n int, err error) {
	v.mutex.Lock()
	defer v.mutex.Unlock()
	
	// Lazy connection - connect on first write
	if v.conn == nil {
		v.conn, err = net.Dial("unix", v.socket)
		if err != nil {
			// Silently fail if Vector isn't running - graceful degradation
			return len(p), nil
		}
	}
	
	// Try to write to Vector
	n, err = v.conn.Write(p)
	if err != nil {
		// Connection failed, close and reset
		v.conn.Close()
		v.conn = nil
		// Return success to avoid breaking the log pipeline
		return len(p), nil
	}
	
	return n, nil
}

// Close closes the Vector connection
func (v *VectorWriter) Close() error {
	v.mutex.Lock()
	defer v.mutex.Unlock()
	
	if v.conn != nil {
		err := v.conn.Close()
		v.conn = nil
		return err
	}
	return nil
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
		slog.Warn("Invalid PID in file", "file", pidfilePath, "pid", pidStr)
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
			slog.Info("Killed stale process", "pid", pid, "file", pidfilePath)
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
		idleTimeout = DefaultIdleTimeout
	}
	m.idleTimeout = idleTimeout

	// Update port range if changed
	startPort := newConfig.StartPort
	if startPort == 0 {
		startPort = DefaultStartPort
	}
	m.minPort = startPort
	m.maxPort = startPort + MaxPortRange

	slog.Info("Updated AppManager configuration",
		"idleTimeout", m.idleTimeout,
		"minPort", m.minPort,
		"maxPort", m.maxPort)
}

// Cleanup stops all running web applications
func (m *AppManager) Cleanup() {
	m.mutex.Lock()
	defer m.mutex.Unlock()

	slog.Info("Cleaning up all web applications")

	for path, app := range m.apps {
		slog.Info("Stopping web app", "path", path)

		// Clean up PID file
		pidfilePath := getPidFilePath(app.Location.EnvVars)
		if pidfilePath != "" {
			if err := os.Remove(pidfilePath); err != nil && !os.IsNotExist(err) {
				slog.Warn("Error removing PID file", "file", pidfilePath, "error", err)
			}
		}

		if app.cancel != nil {
			app.cancel()
		}
	}

	// Clear the apps map
	m.apps = make(map[string]*WebApp)

	// Give processes a moment to exit cleanly
	time.Sleep(500 * time.Millisecond)
}

// NewProcessManager creates a new process manager
func NewProcessManager(config *Config) *ProcessManager {
	return &ProcessManager{
		processes: make([]*ManagedProcess, 0),
		config:    config,
	}
}

// StartProcess starts a managed process
func (pm *ProcessManager) StartProcess(mp *ManagedProcess) error {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()

	// Add delay if specified
	if mp.StartDelay > 0 {
		slog.Info("Waiting before starting process", "delay", mp.StartDelay, "name", mp.Name)
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

	// Set up output destinations
	outputs := []io.Writer{os.Stdout}
	
	// Add file output if configured
	if pm.config != nil && pm.config.Logging.File != "" {
		if fileWriter, err := createFileWriter(pm.config.Logging.File, mp.Name); err == nil {
			outputs = append(outputs, fileWriter)
			// Note: File will be closed when process exits
		} else {
			slog.Warn("Failed to create log file for managed process",
				"process", mp.Name,
				"error", err)
		}
	}
	
	// Add Vector output if configured (but not for Vector itself to avoid loop)
	if pm.config != nil && pm.config.Logging.Vector.Enabled && 
	   pm.config.Logging.Vector.Socket != "" && mp.Name != "vector" {
		vectorWriter := NewVectorWriter(pm.config.Logging.Vector.Socket)
		outputs = append(outputs, vectorWriter)
	}
	
	// Create the appropriate output writer
	var outputWriter io.Writer
	if len(outputs) > 1 {
		outputWriter = &MultiLogWriter{outputs: outputs}
	} else {
		outputWriter = outputs[0]
	}
	
	// Set up output with source identification
	if pm.config != nil && pm.config.Logging.Format == "json" {
		cmd.Stdout = &JSONLogWriter{source: mp.Name, stream: "stdout", output: outputWriter}
		cmd.Stderr = &JSONLogWriter{source: mp.Name, stream: "stderr", output: outputWriter}
	} else {
		cmd.Stdout = &LogWriter{source: mp.Name, stream: "stdout", output: outputWriter}
		cmd.Stderr = &LogWriter{source: mp.Name, stream: "stderr", output: outputWriter}
	}

	mp.Process = cmd

	slog.Info("Starting managed process",
		"name", mp.Name,
		"command", mp.Command,
		"args", strings.Join(mp.Args, " "))

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
			slog.Error("Process exited with error", "name", mp.Name, "error", err)
		} else {
			slog.Info("Process exited normally", "name", mp.Name)
		}

		// Auto-restart if configured
		if shouldRestart && err != nil {
			slog.Info("Auto-restarting process in 5 seconds", "name", mp.Name)
			time.Sleep(5 * time.Second)
			if err := pm.StartProcess(mp); err != nil {
				slog.Error("Failed to restart process", "name", mp.Name, "error", err)
			}
		}
	}()

	pm.processes = append(pm.processes, mp)
	return nil
}

// StartAll starts all configured processes
func (pm *ProcessManager) StartAll(processes []ManagedProcessConfig) {
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
			slog.Error("Failed to start process", "name", proc.Name, "error", err)
		}
	}
}

// StopAll stops all managed processes
func (pm *ProcessManager) StopAll() {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()

	slog.Info("Stopping all managed processes")

	for _, mp := range pm.processes {
		if mp.Cancel != nil {
			slog.Info("Stopping process", "name", mp.Name)
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
		slog.Info("All managed processes stopped")
	case <-time.After(ProcessStopTimeout):
		slog.Warn("Timeout waiting for processes to stop, forcing shutdown")
		for _, mp := range pm.processes {
			if mp.Process != nil && mp.Process.Process != nil {
				mp.Process.Process.Kill()
			}
		}
	}
}

// UpdateConfig updates the process manager configuration
func (pm *ProcessManager) UpdateConfig(processes []ManagedProcessConfig) {
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

// NewIdleManager creates a new idle manager
func NewIdleManager(config *Config) *IdleManager {
	if config.MachineIdleAction == "" {
		return &IdleManager{enabled: false, config: config}
	}

	return &IdleManager{
		enabled:      true,
		action:       config.MachineIdleAction,
		idleTimeout:  config.MachineIdleTimeout,
		lastActivity: time.Now(),
		config:       config,
	}
}

// RequestStarted increments active request counter and resets idle timer
func (im *IdleManager) RequestStarted() {
	if !im.enabled {
		return
	}

	im.mutex.Lock()
	defer im.mutex.Unlock()

	im.activeRequests++
	im.lastActivity = time.Now()

	// Cancel existing timer since we have activity
	if im.timer != nil {
		im.timer.Stop()
		im.timer = nil
	}

	slog.Debug("Request started", "activeRequests", im.activeRequests)
}

// RequestFinished decrements active request counter and starts idle timer if idle
func (im *IdleManager) RequestFinished() {
	if !im.enabled {
		return
	}

	im.mutex.Lock()
	defer im.mutex.Unlock()

	im.activeRequests--
	im.lastActivity = time.Now()

	slog.Debug("Request finished", "activeRequests", im.activeRequests)

	// Start idle timer if no active requests
	if im.activeRequests == 0 {
		im.startIdleTimer()
	}
}

// startIdleTimer starts the idle countdown timer
func (im *IdleManager) startIdleTimer() {
	if im.timer != nil {
		im.timer.Stop()
	}

	im.timer = time.AfterFunc(im.idleTimeout, func() {
		im.performIdleAction()
	})

	slog.Debug("Idle timer started", "timeout", im.idleTimeout)
}

// performIdleAction calls the Fly API to suspend or stop the machine
func (im *IdleManager) performIdleAction() {
	// Execute server.idle hooks before idle action
	if im.config != nil && len(im.config.ServerHooks.Idle) > 0 {
		if err := executeServerHooks(im.config.ServerHooks.Idle, "idle"); err != nil {
			slog.Error("Server idle hooks failed", "error", err)
		}
	}

	appName := os.Getenv("FLY_APP_NAME")
	machineId := os.Getenv("FLY_MACHINE_ID")

	if appName == "" || machineId == "" {
		slog.Warn("Cannot perform idle action: missing FLY_APP_NAME or FLY_MACHINE_ID")
		return
	}

	// Determine action endpoint
	action := im.action
	if action != "suspend" && action != "stop" {
		slog.Warn("Invalid idle action", "action", action)
		return
	}

	slog.Info("Performing idle action", "action", action, "app", appName, "machine", machineId)

	// Create HTTP client with Unix socket transport
	client := &http.Client{
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				return net.Dial("unix", "/.fly/api")
			},
		},
		Timeout: 10 * time.Second,
	}

	// Create request for the appropriate action
	url := fmt.Sprintf("http://flaps/v1/apps/%s/machines/%s/%s", appName, machineId, action)
	req, err := http.NewRequest("POST", url, nil)
	if err != nil {
		slog.Error("Failed to create idle action request", "action", action, "error", err)
		return
	}

	// Execute request
	resp, err := client.Do(req)
	if err != nil {
		slog.Error("Failed to perform idle action", "action", action, "error", err)
		return
	}
	defer resp.Body.Close()

	// Read response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		slog.Error("Failed to read idle action response", "action", action, "error", err)
		return
	}

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		slog.Info("Machine idle action requested successfully", "action", action, "status", resp.StatusCode, "response", string(body))
	} else {
		slog.Error("Machine idle action failed", "action", action, "status", resp.StatusCode, "response", string(body))
	}
}

// UpdateConfig updates the idle manager configuration
func (im *IdleManager) UpdateConfig(config *Config) {
	im.mutex.Lock()
	defer im.mutex.Unlock()

	// Stop existing timer if configuration is changing
	if im.timer != nil {
		im.timer.Stop()
		im.timer = nil
	}

	im.enabled = config.MachineIdleAction != ""
	im.action = config.MachineIdleAction
	im.idleTimeout = config.MachineIdleTimeout
	im.config = config

	if im.enabled {
		slog.Info("Idle action enabled", "action", im.action, "timeout", im.idleTimeout)
		im.lastActivity = time.Now()
		// Start timer if we're idle (no active requests)
		if im.activeRequests == 0 {
			im.startIdleTimer()
		}
	} else {
		slog.Info("Idle action disabled")
	}
}

// executeHooks runs a list of hook commands sequentially
func executeHooks(hooks []HookConfig, env map[string]string, hookType string) error {
	for i, hook := range hooks {
		if hook.Command == "" {
			continue
		}
		
		slog.Info("Executing hook", "type", hookType, "index", i, "command", hook.Command)
		
		// Create command with timeout if specified
		var cmd *exec.Cmd
		var ctx context.Context
		var cancel context.CancelFunc
		
		if hook.Timeout > 0 {
			ctx, cancel = context.WithTimeout(context.Background(), time.Duration(hook.Timeout)*time.Second)
			defer cancel()
			cmd = exec.CommandContext(ctx, hook.Command, hook.Args...)
		} else {
			cmd = exec.Command(hook.Command, hook.Args...)
		}
		
		// Set environment variables if provided
		if env != nil {
			cmd.Env = os.Environ()
			for k, v := range env {
				cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
			}
		}
		
		// Capture output
		output, err := cmd.CombinedOutput()
		if err != nil {
			slog.Error("Hook failed", "type", hookType, "index", i, "error", err, "output", string(output))
			return fmt.Errorf("hook %s[%d] failed: %w", hookType, i, err)
		}
		
		if len(output) > 0 {
			slog.Info("Hook output", "type", hookType, "index", i, "output", string(output))
		}
	}
	
	return nil
}

// executeServerHooks runs server lifecycle hooks
func executeServerHooks(hooks []HookConfig, hookType string) error {
	return executeHooks(hooks, nil, fmt.Sprintf("server.%s", hookType))
}

// executeTenantHooks runs tenant lifecycle hooks with tenant environment
func executeTenantHooks(defaultHooks, specificHooks []HookConfig, env map[string]string, tenantName, hookType string) error {
	// Execute default hooks first
	if err := executeHooks(defaultHooks, env, fmt.Sprintf("tenant.default.%s", hookType)); err != nil {
		return err
	}
	
	// Then execute tenant-specific hooks
	if err := executeHooks(specificHooks, env, fmt.Sprintf("tenant.%s.%s", tenantName, hookType)); err != nil {
		return err
	}
	
	return nil
}

// BasicAuth represents HTTP basic authentication
type BasicAuth struct {
	File    *htpasswd.File
	Realm   string
	Exclude []string
}

// writePIDFile writes the current process PID to a file
func writePIDFile() error {
	pid := os.Getpid()
	return os.WriteFile(NavigatorPIDFile, []byte(strconv.Itoa(pid)), 0644)
}

// removePIDFile removes the PID file
func removePIDFile() {
	os.Remove(NavigatorPIDFile)
}

// sendReloadSignal sends a HUP signal to the running navigator process
func sendReloadSignal() error {
	// Read PID from file
	pidData, err := os.ReadFile(NavigatorPIDFile)
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

	slog.Info("Reload signal sent to navigator", "pid", pid)
	return nil
}

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

	// Handle -s reload option
	if len(os.Args) > 1 && os.Args[1] == "-s" {
		if len(os.Args) > 2 && os.Args[2] == "reload" {
			if err := sendReloadSignal(); err != nil {
				slog.Error("Failed to reload", "error", err)
				os.Exit(1)
			}
			os.Exit(0)
		} else if len(os.Args) > 2 {
			slog.Error("Unknown signal (only 'reload' is supported)", "signal", os.Args[2])
			os.Exit(1)
		} else {
			slog.Error("Option -s requires a signal name (e.g., -s reload)")
			os.Exit(1)
		}
	}

	// Handle --help option
	if len(os.Args) > 1 && (os.Args[1] == "--help" || os.Args[1] == "-h") {
		fmt.Println("Navigator - Web application server")
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
		slog.Warn("Could not write PID file", "error", err)
	}
	defer removePIDFile()

	slog.Info("Loading configuration", "file", configFile)
	config, err := LoadConfig(configFile)
	if err != nil {
		slog.Error("Failed to parse config", "error", err)
		os.Exit(1)
	}

	slog.Info("Loaded configuration",
		"locations", len(config.Locations),
		"proxyRoutes", len(config.ProxyRoutes))

	// Update logger based on configuration
	if config.Logging.Format == "json" {
		jsonLogger := slog.New(slog.NewJSONHandler(os.Stdout, opts))
		slog.SetDefault(jsonLogger)
		slog.Info("Switched to JSON logging format")
	}

	var auth *BasicAuth
	if config.AuthFile != "" {
		auth, err = LoadAuthFile(config.AuthFile, config.AuthRealm, config.AuthExclude)
		if err != nil {
			slog.Warn("Failed to load auth file", "file", config.AuthFile, "error", err)
		} else {
			slog.Info("Loaded authentication", "file", config.AuthFile)
		}
	}

	manager := NewAppManager(config)

	// Create suspend manager
	idleManager := NewIdleManager(config)
	if idleManager.enabled {
		slog.Info("Machine idle feature enabled", "action", config.MachineIdleAction, "timeout", config.MachineIdleTimeout)
	}

	// Execute server.start hooks before starting anything
	if err := executeServerHooks(config.ServerHooks.Start, "start"); err != nil {
		slog.Error("Server start hooks failed", "error", err)
		os.Exit(1)
	}

	// Create and start process manager for managed processes
	processManager := NewProcessManager(config)
	
	// Add Vector as a managed process if configured
	managedProcs := make([]ManagedProcessConfig, 0, len(config.ManagedProcesses)+1)
	
	// If Vector is enabled, add it as the first managed process (highest priority)
	if config.Logging.Vector.Enabled {
		if config.Logging.Vector.Config == "" {
			slog.Warn("Vector enabled but no config file specified")
		} else {
			vectorProc := ManagedProcessConfig{
				Name:        "vector",
				Command:     "vector",
				Args:        []string{"--config", config.Logging.Vector.Config},
				AutoRestart: true,
				StartDelay:  0, // Start immediately
			}
			managedProcs = append(managedProcs, vectorProc)
			slog.Info("Vector integration enabled", 
				"socket", config.Logging.Vector.Socket,
				"config", config.Logging.Vector.Config)
		}
	}
	
	// Add configured managed processes
	managedProcs = append(managedProcs, config.ManagedProcesses...)
	
	if len(managedProcs) > 0 {
		slog.Info("Starting managed processes", "count", len(managedProcs))
		processManager.StartAll(managedProcs)
	}

	// Create a mutable handler wrapper for configuration reloading
	handler := CreateHandler(config, manager, auth, idleManager)

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
				slog.Info("Received SIGHUP signal, reloading configuration")

				newConfig, err := LoadConfig(configFile)
				if err != nil {
					slog.Error("Error reloading configuration", "error", err)
					continue
				}

				slog.Info("Reloaded configuration",
					"locations", len(newConfig.Locations),
					"proxyRoutes", len(newConfig.ProxyRoutes))

				// Reload auth if configured
				var newAuth *BasicAuth
				if newConfig.AuthFile != "" {
					newAuth, err = LoadAuthFile(newConfig.AuthFile, newConfig.AuthRealm, newConfig.AuthExclude)
					if err != nil {
						slog.Warn("Failed to reload auth file", "file", newConfig.AuthFile, "error", err)
						// Keep existing auth on error
						newAuth = auth
					} else {
						slog.Info("Reloaded authentication", "file", newConfig.AuthFile)
					}
				}

				// Update manager configuration
				manager.UpdateConfig(newConfig)

				// Update suspend manager configuration
				idleManager.UpdateConfig(newConfig)

				// Update process manager configuration
				processManager.UpdateConfig(newConfig.ManagedProcesses)

				// Create new handler with updated config
				newHandler := CreateHandler(newConfig, manager, newAuth, idleManager)

				// Atomically swap the handler
				handlerMutex.Lock()
				currentHandler = newHandler
				config = newConfig
				auth = newAuth
				handlerMutex.Unlock()

				slog.Info("Configuration reload complete")

			case os.Interrupt, syscall.SIGTERM:
				slog.Info("Received interrupt signal, cleaning up")
				manager.Cleanup()        // Stop web apps first
				processManager.StopAll() // Then stop managed processes
				os.Exit(0)
			}
		}
	}()

	go manager.IdleChecker()

	addr := fmt.Sprintf(":%d", config.ListenPort)
	slog.Info("Starting Navigator server", "address", addr)
	slog.Info("Server configuration",
		"maxPoolSize", config.MaxPoolSize,
		"idleTimeout", manager.idleTimeout)
	slog.Info("Configuration reload available", "signal", "SIGHUP", "pid", os.Getpid())

	// Start the server in a goroutine so we can execute ready hooks
	server := &http.Server{
		Addr:    addr,
		Handler: mainHandler,
	}
	
	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("Server failed", "error", err)
			os.Exit(1)
		}
	}()
	
	// Wait a moment for the server to start
	time.Sleep(100 * time.Millisecond)
	
	// Execute server.ready hooks after server starts accepting requests
	if err := executeServerHooks(config.ServerHooks.Ready, "ready"); err != nil {
		slog.Error("Server ready hooks failed", "error", err)
	}
	
	// Block forever (signal handler will manage shutdown)
	select {}
}

// LoadConfig loads YAML configuration
func LoadConfig(filename string) (*Config, error) {
	content, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}

	slog.Debug("Loading YAML configuration")
	return ParseYAML(content)
}

// substituteVars replaces template variables with tenant values
func substituteVars(template string, tenant *Tenant) string {
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
		MaxPoolSize:   yamlConfig.Applications.Pools.MaxSize,
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
				slog.Warn("Invalid auth pattern", "pattern", pattern.Pattern, "error", err)
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
			// Support app, region, and machine based fly-replay
			var target string
			if flyReplay.Machine != "" && flyReplay.App != "" {
				target = fmt.Sprintf("machine=%s:%s", flyReplay.Machine, flyReplay.App)
			} else if flyReplay.App != "" {
				target = fmt.Sprintf("app=%s", flyReplay.App)
			} else {
				target = flyReplay.Region
			}

			config.RewriteRules = append(config.RewriteRules, &RewriteRule{
				Pattern:     re,
				Replacement: flyReplay.Path, // Keep original path for fly-replay
				Flag:        fmt.Sprintf("fly-replay:%s:%d", target, flyReplay.Status),
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

	// Set framework configuration
	config.Framework = yamlConfig.Applications.Framework

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
			Hooks:            tenant.Hooks, // Copy tenant-specific hooks
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
					value := substituteVars(template, &tenant)
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

	// Set app idle timeout from pools config
	if yamlConfig.Applications.Pools.Timeout != "" {
		duration, err := time.ParseDuration(yamlConfig.Applications.Pools.Timeout)
		if err != nil {
			slog.Warn("Invalid pools timeout format, using default", "timeout", yamlConfig.Applications.Pools.Timeout, "error", err)
			config.IdleTimeout = DefaultIdleTimeout
		} else {
			config.IdleTimeout = duration
		}
	} else {
		config.IdleTimeout = DefaultIdleTimeout
	}

	// Set start port for web apps
	if yamlConfig.Applications.Pools.StartPort > 0 {
		config.StartPort = yamlConfig.Applications.Pools.StartPort
	} else {
		config.StartPort = DefaultStartPort
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

	// Set logging configuration
	config.Logging = yamlConfig.Logging

	// Set machine idle configuration
	config.MachineIdleAction = yamlConfig.Server.Idle.Action
	if yamlConfig.Server.Idle.Timeout != "" {
		duration, err := time.ParseDuration(yamlConfig.Server.Idle.Timeout)
		if err != nil {
			slog.Warn("Invalid idle timeout format, using default", "timeout", yamlConfig.Server.Idle.Timeout, "error", err)
			config.MachineIdleTimeout = DefaultIdleTimeout
		} else {
			config.MachineIdleTimeout = duration
		}
	} else if config.MachineIdleAction != "" {
		// If action is specified but no timeout, use default
		config.MachineIdleTimeout = DefaultIdleTimeout
	}

	// Set hooks configuration
	config.ServerHooks = yamlConfig.Hooks.Server
	config.DefaultTenantHooks = yamlConfig.Hooks.Tenant

	return config, nil
}

// NewAppManager creates a new application manager
func NewAppManager(config *Config) *AppManager {
	idleTimeout := config.IdleTimeout
	if idleTimeout == 0 {
		idleTimeout = DefaultIdleTimeout
	}

	startPort := config.StartPort
	if startPort == 0 {
		startPort = DefaultStartPort
	}

	return &AppManager{
		apps:        make(map[string]*WebApp),
		config:      config,
		minPort:     startPort,
		maxPort:     startPort + MaxPortRange,
		idleTimeout: idleTimeout,
	}
}

// GetOrStartApp gets an existing app or starts a new one
func (m *AppManager) GetOrStartApp(location *Location) (*WebApp, error) {
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
		timeout := time.NewTimer(RailsStartupTimeout)
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
	app = &WebApp{
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
	timeout := time.NewTimer(RailsStartupTimeout)
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

// startApp starts a web application
func (m *AppManager) startApp(app *WebApp) {
	ctx, cancel := context.WithCancel(context.Background())
	app.ctx = ctx
	app.cancel = cancel

	// Get framework configuration
	framework := &m.config.Framework

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

	// Add port using configurable environment variable name
	portEnvVar := framework.PortEnvVar
	if portEnvVar == "" {
		portEnvVar = "PORT" // Default fallback
	}
	env = append(env, fmt.Sprintf("%s=%d", portEnvVar, app.Port))

	// Check for and clean up PID file before starting
	pidfilePath := getPidFilePath(app.Location.EnvVars)
	if pidfilePath != "" {
		if err := cleanupPidFile(pidfilePath); err != nil {
			slog.Warn("Error cleaning up PID file", "path", app.Location.Path, "error", err)
		}
	}

	// Determine application directory using framework configuration
	appDir := framework.AppDirectory
	if appDir == "" {
		appDir = "/app" // Generic fallback
	}

	// Use location root if specified, otherwise use framework app directory
	if app.Location.Root != "" {
		appDir = strings.TrimSuffix(app.Location.Root, "/public")
	}

	// Try to use the current working directory if configured directory doesn't exist
	if _, err := os.Stat(appDir); os.IsNotExist(err) {
		if cwd, err := os.Getwd(); err == nil {
			appDir = cwd
		}
	}

	// Build command using framework configuration
	if framework.Command == "" {
		slog.Error("Framework command not configured", "path", app.Location.Path)
		return // Cannot start without command configured
	}

	// Log the framework configuration being used
	slog.Info("Starting application with framework config", 
		"path", app.Location.Path,
		"command", framework.Command,
		"args", framework.Args,
		"appDirectory", appDir,
		"port", app.Port)

	// Expand args with port substitution
	args := make([]string, len(framework.Args))
	for i, arg := range framework.Args {
		if arg == "${port}" {
			args[i] = strconv.Itoa(app.Port)
		} else {
			args[i] = arg
		}
	}

	// Log the final command that will be executed
	slog.Info("Executing command", 
		"path", app.Location.Path,
		"command", framework.Command,
		"expandedArgs", args,
		"workingDir", appDir)

	// Create command with framework command and args
	cmd := exec.CommandContext(ctx, framework.Command, args...)

	cmd.Dir = appDir
	cmd.Env = env
	// Use the location path as the source identifier
	appName := strings.TrimPrefix(app.Location.Path, "/")
	if appName == "" {
		appName = "root"
	}
	
	// Extract tenant from environment if available
	tenant := ""
	for _, envVar := range env {
		if strings.HasPrefix(envVar, "TENANT=") {
			tenant = strings.TrimPrefix(envVar, "TENANT=")
			break
		}
	}
	
	// Set up output destinations
	outputs := []io.Writer{os.Stdout}
	
	// Add file output if configured
	if m.config.Logging.File != "" {
		if fileWriter, err := createFileWriter(m.config.Logging.File, appName); err == nil {
			outputs = append(outputs, fileWriter)
			// Note: File will be closed when process exits
		} else {
			slog.Warn("Failed to create log file for web app",
				"app", appName,
				"error", err)
		}
	}
	
	// Add Vector output if configured
	if m.config.Logging.Vector.Enabled && m.config.Logging.Vector.Socket != "" {
		vectorWriter := NewVectorWriter(m.config.Logging.Vector.Socket)
		outputs = append(outputs, vectorWriter)
	}
	
	// Create the appropriate output writer
	var outputWriter io.Writer
	if len(outputs) > 1 {
		outputWriter = &MultiLogWriter{outputs: outputs}
	} else {
		outputWriter = outputs[0]
	}
	
	// Set up output with appropriate format
	if m.config.Logging.Format == "json" {
		cmd.Stdout = &JSONLogWriter{source: appName, stream: "stdout", tenant: tenant, output: outputWriter}
		cmd.Stderr = &JSONLogWriter{source: appName, stream: "stderr", tenant: tenant, output: outputWriter}
	} else {
		cmd.Stdout = &LogWriter{source: appName, stream: "stdout", output: outputWriter}
		cmd.Stderr = &LogWriter{source: appName, stream: "stderr", output: outputWriter}
	}

	app.mutex.Lock()
	app.Process = cmd
	app.mutex.Unlock()

	slog.Info("Starting web app",
		"path", app.Location.Path,
		"port", app.Port,
		"directory", appDir)

	if err := cmd.Start(); err != nil {
		slog.Error("Failed to start web app", 
			"path", app.Location.Path, 
			"command", framework.Command,
			"args", args,
			"workingDir", appDir,
			"port", app.Port,
			"error", err)
		
		// Check if the command executable exists
		if _, statErr := os.Stat(framework.Command); statErr != nil {
			slog.Error("Command executable not found",
				"path", app.Location.Path,
				"command", framework.Command,
				"statError", statErr)
		}
		
		// Check if working directory exists
		if _, statErr := os.Stat(appDir); statErr != nil {
			slog.Error("Working directory not found",
				"path", app.Location.Path,
				"workingDir", appDir,
				"statError", statErr)
		}
		
		app.mutex.Lock()
		app.Starting = false
		app.mutex.Unlock()
		return
	}

	// Wait a moment for app to start, then mark as ready
	startupDelay := time.Duration(framework.StartupDelay) * time.Second
	if startupDelay == 0 {
		startupDelay = RailsStartupDelay // Default fallback
	}
	time.Sleep(startupDelay)
	app.mutex.Lock()
	app.Starting = false
	app.mutex.Unlock()
	slog.Info("Web app ready", "path", app.Location.Path, "port", app.Port)

	// Execute tenant start hooks with tenant environment
	tenantName := app.Location.Path
	if tenantName == "" {
		tenantName = "default"
	}
	
	// Build environment map for hooks (same env as the app)
	envMap := make(map[string]string)
	for _, e := range env {
		parts := strings.SplitN(e, "=", 2)
		if len(parts) == 2 {
			envMap[parts[0]] = parts[1]
		}
	}
	
	// Execute hooks (default hooks first, then tenant-specific from location)
	if err := executeTenantHooks(m.config.DefaultTenantHooks.Start, app.Location.Hooks.Start, envMap, tenantName, "start"); err != nil {
		slog.Error("Tenant start hooks failed", "tenant", tenantName, "error", err)
	}

	// Wait for process to exit in background
	go func() {
		cmd.Wait()
		slog.Info("Web app exited", "path", app.Location.Path, "port", app.Port)

		// Clean up PID file when app exits
		if pidfilePath != "" {
			if err := os.Remove(pidfilePath); err != nil && !os.IsNotExist(err) {
				slog.Warn("Error removing PID file", "file", pidfilePath, "error", err)
			}
		}

		// Remove from apps map when process exits
		m.mutex.Lock()
		delete(m.apps, app.Location.Path)
		m.mutex.Unlock()
	}()
}

// StopApp stops a web application
func (m *AppManager) StopApp(path string) {
	m.mutex.Lock()
	defer m.mutex.Unlock()

	app, exists := m.apps[path]
	if !exists {
		return
	}

	slog.Info("Stopping web app", "path", path)

	// Execute tenant stop hooks before stopping the app
	tenantName := app.Location.Path
	if tenantName == "" {
		tenantName = "default"
	}
	
	// Build environment map for hooks (same env as the app would have)
	envMap := make(map[string]string)
	// Add global env vars
	for k, v := range m.config.GlobalEnvVars {
		envMap[k] = v
	}
	// Add location-specific env vars
	for k, v := range app.Location.EnvVars {
		envMap[k] = v
	}
	// Add port
	portEnvVar := m.config.Framework.PortEnvVar
	if portEnvVar == "" {
		portEnvVar = "PORT"
	}
	envMap[portEnvVar] = fmt.Sprintf("%d", app.Port)
	
	// Execute hooks (default hooks first, then tenant-specific from location)
	if err := executeTenantHooks(m.config.DefaultTenantHooks.Stop, app.Location.Hooks.Stop, envMap, tenantName, "stop"); err != nil {
		slog.Error("Tenant stop hooks failed", "tenant", tenantName, "error", err)
	}

	// Clean up PID file
	pidfilePath := getPidFilePath(app.Location.EnvVars)
	if pidfilePath != "" {
		if err := os.Remove(pidfilePath); err != nil && !os.IsNotExist(err) {
			slog.Warn("Error removing PID file", "file", pidfilePath, "error", err)
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
			slog.Info("Stopping idle app", "path", path)
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
func CreateHandler(config *Config, manager *AppManager, auth *BasicAuth, idleManager *IdleManager) http.Handler {
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
		idleManager.RequestStarted()
		defer idleManager.RequestFinished()

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

		// Find matching location early to determine if this is a web app
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
		// while web apps (which would require auth if enabled) are always proxied
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
			proxyWithRetry(w, r, target, ProxyRetryTimeout)
			return
		}

		// Get or start the web app
		app, err := manager.GetOrStartApp(bestMatch)
		if err != nil {
			http.Error(w, "Failed to start application", http.StatusInternalServerError)
			return
		}

		// Proxy to web app
		target, _ := url.Parse(fmt.Sprintf("http://localhost:%d", app.Port))

		// For web apps, preserve the full path - don't strip the location prefix
		// App routing expects to see the full path like "/2025/adelaide/adelaide-combined/"
		// Only strip if the location is "/" (root)
		originalPath := r.URL.Path
		if bestMatch.Path != "/" {
			// Don't modify the path - app needs to see the full path
			// Framework-specific environment variables tell the app what prefix to expect
		} else {
			// Root location - path is already correct
		}

		// Add headers
		r.Header.Set("X-Forwarded-For", r.RemoteAddr)
		r.Header.Set("X-Forwarded-Host", r.Host)
		// Preserve X-Forwarded-Proto if it exists (from upstream proxy), otherwise default to http
		if r.Header.Get("X-Forwarded-Proto") == "" {
			r.Header.Set("X-Forwarded-Proto", "http")
		}

		slog.Info("Proxying to web app", "path", originalPath, "port", app.Port, "location", bestMatch.Path)

		// Use retry logic for web apps too
		proxyWithRetry(w, r, target, ProxyRetryTimeout)
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
				// Handle fly-replay: fly-replay:target:status (target can be region or app=name)
				parts := strings.Split(rule.Flag, ":")
				if len(parts) == 3 {
					target := parts[1]
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
							// Check if this is a retry
							if r.Header.Get("X-Navigator-Retry") == "true" {
								// Retry detected, serve maintenance page
								slog.Info("Retry detected, serving maintenance page",
									"path", path,
									"target", target,
									"method", r.Method,
									"navigatorRetry", r.Header.Get("X-Navigator-Retry"))

								serveMaintenancePage(w, r, config)
								return true
							}

							w.Header().Set("Content-Type", "application/vnd.fly.replay+json")
							statusCode := http.StatusTemporaryRedirect
							if code, err := strconv.Atoi(status); err == nil {
								statusCode = code
							}

							// Parse target to determine if it's machine, app, or region
							var responseMap map[string]interface{}
							if strings.HasPrefix(target, "machine=") {
								// Machine-based fly-replay: machine=machine_id:app_name
								machineAndApp := strings.TrimPrefix(target, "machine=")
								parts := strings.Split(machineAndApp, ":")
								if len(parts) == 2 {
									machineID := parts[0]
									appName := parts[1]
									slog.Info("Sending fly-replay response",
										"path", path,
										"machine", machineID,
										"app", appName,
										"status", statusCode,
										"method", r.Method,
										"contentLength", r.ContentLength)

									responseMap = map[string]interface{}{
										"app":             appName,
										"prefer_instance": machineID,
										"transform": map[string]interface{}{
											"set_headers": []map[string]string{
												{"name": "X-Navigator-Retry", "value": "true"},
											},
										},
									}
								}
							} else if strings.HasPrefix(target, "app=") {
								// App-based fly-replay
								appName := strings.TrimPrefix(target, "app=")
								slog.Info("Sending fly-replay response",
									"path", path,
									"app", appName,
									"status", statusCode,
									"method", r.Method,
									"contentLength", r.ContentLength)

								responseMap = map[string]interface{}{
									"app": appName,
									"transform": map[string]interface{}{
										"set_headers": []map[string]string{
											{"name": "X-Navigator-Retry", "value": "true"},
										},
									},
								}
							} else {
								// Region-based fly-replay
								slog.Info("Sending fly-replay response",
									"path", path,
									"region", target,
									"status", statusCode,
									"method", r.Method,
									"contentLength", r.ContentLength)

								responseMap = map[string]interface{}{
									"region": target + ",any",
									"transform": map[string]interface{}{
										"set_headers": []map[string]string{
											{"name": "X-Navigator-Retry", "value": "true"},
										},
									},
								}
							}

							w.WriteHeader(statusCode)

							responseBodyBytes, err := json.Marshal(responseMap)
							if err != nil {
								http.Error(w, "Internal Server Error", http.StatusInternalServerError)
								return true
							}
							slog.Debug("Fly replay response body", "body", string(responseBodyBytes))
							w.Write(responseBodyBytes)
							return true
						} else {
							// Automatically reverse proxy instead of fly-replay
							return handleFlyReplayFallback(w, r, target, config)
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

	// If Content-Length is explicitly set and >= 1MB, use reverse proxy
	if r.ContentLength >= MaxFlyReplaySize {
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
// Constructs the target URL based on target type:
// - Machine: http://<machine_id>.vm.<appname>.internal:<port><path>
// - App: http://<appname>.internal:<port><path>
// - Region: http://<region>.<FLY_APP_NAME>.internal:<port><path>
func handleFlyReplayFallback(w http.ResponseWriter, r *http.Request, target string, config *Config) bool {
	flyAppName := os.Getenv("FLY_APP_NAME")
	if flyAppName == "" {
		slog.Debug("FLY_APP_NAME not set, cannot construct fallback proxy URL")
		return false
	}

	// Construct the target URL based on target type
	listenPort := config.ListenPort
	if listenPort == 0 {
		listenPort = DefaultListenPort
	}

	var targetURL string
	if strings.HasPrefix(target, "machine=") {
		// Machine-based: http://<machine_id>.vm.<appname>.internal:<port><path>
		machineAndApp := strings.TrimPrefix(target, "machine=")
		parts := strings.Split(machineAndApp, ":")
		if len(parts) == 2 {
			machineID := parts[0]
			appName := parts[1]
			targetURL = fmt.Sprintf("http://%s.vm.%s.internal:%d%s", machineID, appName, listenPort, r.URL.Path)
		} else {
			slog.Debug("Invalid machine target format", "target", target)
			return false
		}
	} else if strings.HasPrefix(target, "app=") {
		// App-based: http://<appname>.internal:<port><path>
		appName := strings.TrimPrefix(target, "app=")
		targetURL = fmt.Sprintf("http://%s.internal:%d%s", appName, listenPort, r.URL.Path)
	} else {
		// Region-based: http://<region>.<FLY_APP_NAME>.internal:<port><path>
		targetURL = fmt.Sprintf("http://%s.%s.internal:%d%s", target, flyAppName, listenPort, r.URL.Path)
	}
	if r.URL.RawQuery != "" {
		targetURL += "?" + r.URL.RawQuery
	}

	targetParsed, err := url.Parse(targetURL)
	if err != nil {
		slog.Debug("Failed to parse fallback proxy URL", "url", targetURL, "error", err)
		return false
	}

	// Set forwarding headers
	r.Header.Set("X-Forwarded-Host", r.Host)

	slog.Info("Using automatic reverse proxy fallback for fly-replay",
		"originalPath", r.URL.Path,
		"targetURL", targetURL,
		"target", target,
		"method", r.Method,
		"contentLength", r.ContentLength)

	// Use the existing retry proxy logic
	proxyWithRetry(w, r, targetParsed, ProxyRetryTimeout)
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
	slog.Info("Serving static file", "path", path, "fsPath", fsPath)
	return true
}

// tryFiles implements try_files behavior for non-authenticated routes
// Attempts to serve static files with common extensions before falling back to web app
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
	slog.Info("Try files served", "requestPath", requestPath, "fsPath", fsPath)
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
	proxyWithRetry(w, r, target, ProxyRetryTimeout)
}
