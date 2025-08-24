package main

import (
	"bufio"
	"context"
	"fmt"
	"log"
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

// RewriteRule represents an nginx rewrite rule
type RewriteRule struct {
	Pattern     *regexp.Regexp
	Replacement string
	Flag        string // redirect, last, etc.
}

// AuthPattern represents an nginx auth exclusion pattern
type AuthPattern struct {
	Pattern *regexp.Regexp
	Action  string // "off" or realm name
}

// Config represents the parsed nginx/passenger configuration
type Config struct {
	ServerName      string
	ListenPort      int
	MaxPoolSize     int
	DefaultUser     string
	DefaultGroup    string
	LogFile         string
	ErrorLog        string
	AccessLog       string
	AuthFile        string
	AuthRealm       string
	AuthExclude     []string
	AuthPatterns    []*AuthPattern
	RewriteRules    []*RewriteRule
	ProxyRoutes     map[string]*ProxyRoute
	Locations       map[string]*Location
	GlobalEnvVars   map[string]string
	ClientMaxBody   string
	PassengerRuby   string
	MinInstances    int
	PreloadBundler  bool
	IdleTimeout     time.Duration  // Idle timeout for app processes
	StartPort       int            // Starting port for Rails apps
	StaticDirs      []*StaticDir   // Static directory mappings
	StaticExts      []string       // File extensions to serve statically
	TryFilesSuffixes []string      // Suffixes for try_files behavior
	PublicDir       string         // Default public directory
	ManagedProcesses []struct {    // Managed processes to start/stop with Navigator
		Name        string            `yaml:"name"`
		Command     string            `yaml:"command"`
		Args        []string          `yaml:"args"`
		WorkingDir  string            `yaml:"working_dir"`
		Env         map[string]string `yaml:"env"`
		AutoRestart bool              `yaml:"auto_restart"`
		StartDelay  int               `yaml:"start_delay"`
	}
}

// StaticDir represents a static directory mapping
type StaticDir struct {
	URLPath   string // URL path prefix (e.g., "/assets/")
	LocalPath string // Local filesystem path (e.g., "public/assets/")
	CacheTTL  int    // Cache TTL in seconds
}

// ProxyRoute represents a route that proxies to another server
type ProxyRoute struct {
	Pattern     string
	ProxyPass   string
	SetHeaders  map[string]string
	SSLVerify   bool
}

// Location represents a Rails application location
type Location struct {
	Path            string
	Root            string
	AppGroupName    string
	EnvVars         map[string]string
	BaseURI         string
	MatchPattern    string  // Pattern for matching request paths (e.g., "*/cable")
	StandaloneServer string  // If set, proxy to this server instead of Rails app
}

// RailsApp represents a running Rails application
type RailsApp struct {
	Location    *Location
	Process     *exec.Cmd
	Port        int
	LastAccess  time.Time
	Starting    bool
	mutex       sync.RWMutex
	ctx         context.Context
	cancel      context.CancelFunc
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
		Enabled        bool     `yaml:"enabled"`
		Realm          string   `yaml:"realm"`
		HTPasswd       string   `yaml:"htpasswd"`
		PublicPaths    []string `yaml:"public_paths"`
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
		GlobalEnv    map[string]string `yaml:"global_env"`
		StandardVars map[string]string `yaml:"standard_vars"`
		Tenants      []struct {
			Name                      string            `yaml:"name"`
			Path                      string            `yaml:"path"`
			Group                     string            `yaml:"group"`
			Database                  string            `yaml:"database"`
			Owner                     string            `yaml:"owner"`
			Storage                   string            `yaml:"storage"`
			Scope                     string            `yaml:"scope"`
			Root                      string            `yaml:"root"`
			Special                   bool              `yaml:"special"`
			MatchPattern              string            `yaml:"match_pattern"`
			StandaloneServer          string            `yaml:"standalone_server"`
			Env                       map[string]string `yaml:"env"`
			ForceMaxConcurrentRequests int              `yaml:"force_max_concurrent_requests"`
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
	
	ManagedProcesses []struct {
		Name        string            `yaml:"name"`
		Command     string            `yaml:"command"`
		Args        []string          `yaml:"args"`
		WorkingDir  string            `yaml:"working_dir"`
		Env         map[string]string `yaml:"env"`
		AutoRestart bool              `yaml:"auto_restart"`
		StartDelay  int               `yaml:"start_delay"`  // Delay in seconds before starting
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
	mutex       sync.RWMutex
}

// ProcessManager manages external processes
type ProcessManager struct {
	processes []*ManagedProcess
	mutex     sync.RWMutex
	wg        sync.WaitGroup
}

// AppManager manages Rails application processes
type AppManager struct {
	apps        map[string]*RailsApp
	config      *Config
	mutex       sync.RWMutex
	idleTimeout time.Duration
	minPort     int  // Minimum port for Rails apps
	maxPort     int  // Maximum port for Rails apps
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

// BasicAuth represents HTTP basic authentication
type BasicAuth struct {
	File    *htpasswd.File
	Realm   string
	Exclude []string
}

// Placeholder for removed APR1 implementation - now handled by go-htpasswd library

func main() {
	configFile := "config/navigator.yml"
	if len(os.Args) > 1 {
		configFile = os.Args[1]
	}

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
	
	// Create and start process manager for managed processes
	processManager := NewProcessManager()
	if len(config.ManagedProcesses) > 0 {
		log.Printf("Starting %d managed processes", len(config.ManagedProcesses))
		processManager.StartAll(config.ManagedProcesses)
	}
	
	// Set up signal handling for graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	
	// Start cleanup goroutine
	go func() {
		<-sigChan
		log.Println("Received interrupt signal, cleaning up...")
		manager.Cleanup()          // Stop Rails apps first
		processManager.StopAll()  // Then stop managed processes
		os.Exit(0)
	}()
	
	go manager.IdleChecker()

	handler := CreateHandler(config, manager, auth)
	
	addr := fmt.Sprintf(":%d", config.ListenPort)
	log.Printf("Starting Navigator server on %s", addr)
	log.Printf("Max pool size: %d, Idle timeout: %v", config.MaxPoolSize, manager.idleTimeout)
	
	if err := http.ListenAndServe(addr, handler); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

// LoadConfig auto-detects and loads either YAML or nginx configuration
func LoadConfig(filename string) (*Config, error) {
	ext := filepath.Ext(filename)
	content, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}
	
	// Auto-detect by extension or content
	switch {
	case ext == ".yaml" || ext == ".yml":
		log.Println("Detected YAML configuration format")
		return ParseYAML(content)
	case ext == ".conf" || strings.Contains(string(content), "server {"):
		log.Println("Warning: nginx format is deprecated, please migrate to YAML")
		return ParseNginxFile(filename)
	default:
		// Try to detect by content
		if strings.Contains(string(content), "server {") {
			log.Println("Warning: nginx format is deprecated, please migrate to YAML")
			return ParseNginxFile(filename)
		}
		// Default to YAML
		log.Println("Assuming YAML configuration format")
		return ParseYAML(content)
	}
}

// substituteVars replaces template variables with tenant values
func substituteVars(template string, tenant struct {
	Name                      string            `yaml:"name"`
	Path                      string            `yaml:"path"`
	Group                     string            `yaml:"group"`
	Database                  string            `yaml:"database"`
	Owner                     string            `yaml:"owner"`
	Storage                   string            `yaml:"storage"`
	Scope                     string            `yaml:"scope"`
	Root                      string            `yaml:"root"`
	Special                   bool              `yaml:"special"`
	MatchPattern              string            `yaml:"match_pattern"`
	StandaloneServer          string            `yaml:"standalone_server"`
	Env                       map[string]string `yaml:"env"`
	ForceMaxConcurrentRequests int              `yaml:"force_max_concurrent_requests"`
}) string {
	result := template
	result = strings.ReplaceAll(result, "${tenant.name}", tenant.Name)
	result = strings.ReplaceAll(result, "${tenant.database}", tenant.Database)
	result = strings.ReplaceAll(result, "${tenant.owner}", tenant.Owner)
	result = strings.ReplaceAll(result, "${tenant.storage}", tenant.Storage)
	result = strings.ReplaceAll(result, "${tenant.scope}", tenant.Scope)
	result = strings.ReplaceAll(result, "${tenant.group}", tenant.Group)
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
		GlobalEnvVars: yamlConfig.Applications.GlobalEnv,
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
	
	// Convert tenant applications to locations
	for _, tenant := range yamlConfig.Applications.Tenants {
		location := &Location{
			Path:             tenant.Path,
			AppGroupName:     tenant.Group,
			EnvVars:          make(map[string]string),
			MatchPattern:     tenant.MatchPattern,
			StandaloneServer: tenant.StandaloneServer,
		}
		
		// Copy tenant environment variables
		for k, v := range tenant.Env {
			location.EnvVars[k] = v
		}
		
		// Add standard variables (unless it's a special tenant)
		if !tenant.Special {
			for varName, template := range yamlConfig.Applications.StandardVars {
				value := substituteVars(template, tenant)
				location.EnvVars[varName] = value
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
	
	return config, nil
}

// ParseNginxFile parses the nginx/passenger configuration file
func ParseNginxFile(filename string) (*Config, error) {
	file, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	config := &Config{
		ListenPort:     3000,
		MaxPoolSize:    68,
		DefaultUser:    "root",
		DefaultGroup:   "root",
		Locations:      make(map[string]*Location),
		ProxyRoutes:    make(map[string]*ProxyRoute),
		GlobalEnvVars:  make(map[string]string),
		AuthExclude:    []string{},
		AuthPatterns:   []*AuthPattern{},
		RewriteRules:   []*RewriteRule{},
		MinInstances:   0,
		PreloadBundler: false,
		IdleTimeout:    10 * time.Minute,
		StartPort:      4000,
		// Default static configuration for nginx compatibility
		StaticDirs: []*StaticDir{
			{URLPath: "/assets/", LocalPath: "public/assets/", CacheTTL: 86400},
			{URLPath: "/docs/", LocalPath: "public/docs/", CacheTTL: 0},
			{URLPath: "/fonts/", LocalPath: "public/fonts/", CacheTTL: 86400},
			{URLPath: "/regions/", LocalPath: "public/regions/", CacheTTL: 0},
			{URLPath: "/studios/", LocalPath: "public/studios/", CacheTTL: 0},
		},
		StaticExts: []string{"html", "htm", "txt", "xml", "json", "css", "js",
			"png", "jpg", "jpeg", "gif", "svg", "ico", "pdf", "xlsx",
			"woff", "woff2", "ttf", "eot"},
		TryFilesSuffixes: []string{".html", ".htm", ".txt", ".xml", ".json"},
	}

	scanner := bufio.NewScanner(file)
	var currentLocation *Location
	var currentProxy *ProxyRoute
	inServer := false
	inLocation := false
	inProxyLocation := false

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		
		// Skip comments and empty lines
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// Handle server block
		if strings.HasPrefix(line, "server {") {
			inServer = true
			continue
		}

		// Handle location blocks
		if strings.HasPrefix(line, "location") {
			parts := strings.Fields(line)
			if len(parts) >= 2 {
				locPath := parts[1]
				
				// Check if it's a proxy location (PDF/XLSX)
				if strings.Contains(line, "~") && (strings.Contains(locPath, "\\.pdf$") || strings.Contains(locPath, "\\.xlsx$")) {
					inProxyLocation = true
					pattern := strings.Trim(locPath, "~")
					currentProxy = &ProxyRoute{
						Pattern:    pattern,
						SetHeaders: make(map[string]string),
					}
				} else if locPath != "/" && !strings.Contains(locPath, "/up") {
					inLocation = true
					currentLocation = &Location{
						Path:    locPath,
						EnvVars: make(map[string]string),
					}
				} else if locPath == "/" {
					// Handle root location
					inLocation = true
					currentLocation = &Location{
						Path:    "/",
						EnvVars: make(map[string]string),
					}
				}
			}
			continue
		}

		// End of location block
		if line == "}" {
			if inLocation && currentLocation != nil {
				config.Locations[currentLocation.Path] = currentLocation
				currentLocation = nil
				inLocation = false
			} else if inProxyLocation && currentProxy != nil {
				config.ProxyRoutes[currentProxy.Pattern] = currentProxy
				currentProxy = nil
				inProxyLocation = false
			}
			continue
		}

		// Parse directives
		if inProxyLocation && currentProxy != nil {
			if strings.HasPrefix(line, "proxy_pass ") {
				currentProxy.ProxyPass = strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "proxy_pass")), ";")
			} else if strings.HasPrefix(line, "proxy_set_header ") {
				parts := strings.SplitN(strings.TrimSuffix(strings.TrimPrefix(line, "proxy_set_header "), ";"), " ", 2)
				if len(parts) == 2 {
					currentProxy.SetHeaders[parts[0]] = parts[1]
				}
			} else if strings.HasPrefix(line, "proxy_ssl_server_name ") {
				currentProxy.SSLVerify = strings.Contains(line, "on")
			}
		} else if inLocation && currentLocation != nil {
			// Parse location-specific directives
			if strings.HasPrefix(line, "root ") {
				currentLocation.Root = strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "root")), ";")
			} else if strings.HasPrefix(line, "passenger_app_group_name ") {
				currentLocation.AppGroupName = strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "passenger_app_group_name")), ";")
			} else if strings.HasPrefix(line, "passenger_base_uri ") {
				currentLocation.BaseURI = strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "passenger_base_uri")), ";")
			} else if strings.HasPrefix(line, "passenger_env_var ") {
				parts := strings.SplitN(strings.TrimSuffix(strings.TrimPrefix(line, "passenger_env_var "), ";"), " ", 2)
				if len(parts) == 2 {
					key := parts[0]
					value := strings.Trim(parts[1], "\"")
					currentLocation.EnvVars[key] = value
				}
			}
		} else if inServer {
			// Parse server-level directives
			if strings.HasPrefix(line, "listen ") {
				portStr := strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "listen")), ";")
				portStr = strings.Fields(portStr)[0] // Handle "listen [::]:3000"
				if port, err := strconv.Atoi(portStr); err == nil {
					config.ListenPort = port
				}
			} else if strings.HasPrefix(line, "server_name ") {
				config.ServerName = strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "server_name")), ";")
			} else if strings.HasPrefix(line, "rewrite ") {
				// Parse rewrite rule: rewrite ^pattern$ replacement flag;
				rewriteStr := strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "rewrite")), ";")
				parts := strings.Fields(rewriteStr)
				if len(parts) >= 2 {
					patternStr := parts[0]
					replacement := parts[1]
					flag := ""
					if len(parts) >= 3 {
						flag = parts[2]
					}
					
					// Convert nginx regex to Go regex
					if pattern, err := regexp.Compile(patternStr); err == nil {
						config.RewriteRules = append(config.RewriteRules, &RewriteRule{
							Pattern:     pattern,
							Replacement: replacement,
							Flag:        flag,
						})
						log.Printf("Parsed rewrite rule: %s -> %s (%s)", patternStr, replacement, flag)
					} else {
						log.Printf("Warning: Invalid rewrite pattern %s: %v", patternStr, err)
					}
				}
			} else if strings.HasPrefix(line, "if (") && strings.Contains(line, "set $realm") {
				// Parse auth pattern: if ($request_uri ~ "pattern") { set $realm off; }
				if strings.Contains(line, "~") {
					// Extract the regex pattern between quotes
					start := strings.Index(line, "\"")
					end := strings.LastIndex(line, "\"")
					if start != -1 && end != -1 && start < end {
						patternStr := line[start+1 : end]
						action := "off" // Default action for exclusions
						
						// Convert nginx regex to Go regex
						if pattern, err := regexp.Compile(patternStr); err == nil {
							config.AuthPatterns = append(config.AuthPatterns, &AuthPattern{
								Pattern: pattern,
								Action:  action,
							})
							log.Printf("Parsed auth pattern: %s -> %s", patternStr, action)
						} else {
							log.Printf("Warning: Invalid auth pattern %s: %v", patternStr, err)
						}
					}
				}
			} else if strings.HasPrefix(line, "auth_basic_user_file ") {
				config.AuthFile = strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "auth_basic_user_file")), ";")
			} else if strings.HasPrefix(line, "set $realm ") {
				config.AuthRealm = strings.Trim(strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "set $realm")), ";"), "\"")
			} else if strings.HasPrefix(line, "client_max_body_size ") {
				config.ClientMaxBody = strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "client_max_body_size")), ";")
			} else if strings.HasPrefix(line, "passenger_ruby ") {
				config.PassengerRuby = strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "passenger_ruby")), ";")
			} else if strings.HasPrefix(line, "passenger_min_instances ") {
				if n, err := strconv.Atoi(strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "passenger_min_instances")), ";")); err == nil {
					config.MinInstances = n
				}
			} else if strings.HasPrefix(line, "passenger_preload_bundler ") {
				config.PreloadBundler = strings.Contains(line, "on")
			} else if strings.HasPrefix(line, "passenger_env_var ") {
				parts := strings.SplitN(strings.TrimSuffix(strings.TrimPrefix(line, "passenger_env_var "), ";"), " ", 2)
				if len(parts) == 2 {
					key := parts[0]
					value := strings.Trim(parts[1], "\"")
					config.GlobalEnvVars[key] = value
				}
			}
		} else {
			// Global directives
			if strings.HasPrefix(line, "passenger_max_pool_size ") {
				if n, err := strconv.Atoi(strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "passenger_max_pool_size")), ";")); err == nil {
					config.MaxPoolSize = n
				}
			} else if strings.HasPrefix(line, "passenger_default_user ") {
				config.DefaultUser = strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "passenger_default_user")), ";")
			} else if strings.HasPrefix(line, "passenger_default_group ") {
				config.DefaultGroup = strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "passenger_default_group")), ";")
			} else if strings.HasPrefix(line, "passenger_log_file ") {
				config.LogFile = strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "passenger_log_file")), ";")
			} else if strings.HasPrefix(line, "error_log ") {
				config.ErrorLog = strings.TrimSuffix(strings.TrimSpace(strings.TrimPrefix(line, "error_log")), ";")
			} else if strings.HasPrefix(line, "access_log ") {
				parts := strings.Fields(strings.TrimSuffix(strings.TrimPrefix(line, "access_log "), ";"))
				if len(parts) > 0 {
					config.AccessLog = parts[0]
				}
			}
		}
	}

	// Auth exclusions are now parsed from the config file as AuthPatterns
	// No need for hard-coded exclusions

	return config, scanner.Err()
}

// ParseConfig is deprecated, use LoadConfig instead
func ParseConfig(filename string) (*Config, error) {
	log.Println("Warning: ParseConfig is deprecated, use LoadConfig instead")
	return ParseNginxFile(filename)
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
func CreateHandler(config *Config, manager *AppManager, auth *BasicAuth) http.Handler {
	mux := http.NewServeMux()

	// Health check
	mux.HandleFunc("/up", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Main handler
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Handle nginx-style rewrites/redirects first
		if handleRewrites(w, r, config) {
			return
		}

		// Check if path should be excluded from auth using parsed patterns
		needsAuth := auth != nil && auth.Realm != "off" && !shouldExcludeFromAuth(r.URL.Path, config)

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

		// For non-authenticated routes, try nginx-style try_files behavior
		// This attempts to serve static files with common extensions before falling back to Rails
		if !needsAuth && tryFiles(w, r, config) {
			return
		}

		// Check for proxy routes (PDF/XLSX)
		for pattern, route := range config.ProxyRoutes {
			matched, _ := regexp.MatchString(pattern, r.URL.Path)
			if matched {
				proxyRequest(w, r, route)
				return
			}
		}

		// Find matching location
		var bestMatch *Location
		bestMatchLen := 0
		
		// First, check for pattern matches
		for _, location := range config.Locations {
			if location.MatchPattern != "" {
				if matched, _ := filepath.Match(location.MatchPattern, r.URL.Path); matched {
					bestMatch = location
					break  // Pattern matches take priority
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

		if bestMatch == nil {
			// Try root location
			if rootLoc, ok := config.Locations["/"]; ok {
				bestMatch = rootLoc
			} else {
				// Delegate to health check handler
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
			proxy := httputil.NewSingleHostReverseProxy(target)
			proxy.ServeHTTP(w, r)
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
		proxy := httputil.NewSingleHostReverseProxy(target)
		
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
		
		log.Printf("Proxying %s -> Rails on port %d (matched location: %s)", originalPath, app.Port, bestMatch.Path)
		
		proxy.ServeHTTP(w, r)
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

// handleRewrites handles nginx-style rewrite rules from config
func handleRewrites(w http.ResponseWriter, r *http.Request, config *Config) bool {
	path := r.URL.Path
	
	for _, rule := range config.RewriteRules {
		if rule.Pattern.MatchString(path) {
			// Apply the rewrite
			newPath := rule.Pattern.ReplaceAllString(path, rule.Replacement)
			
			if rule.Flag == "redirect" {
				http.Redirect(w, r, newPath, http.StatusFound)
				return true
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
	
	return false
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
	
	// First check static directories from config
	for _, staticDir := range config.StaticDirs {
		if strings.HasPrefix(path, staticDir.URLPath) {
			// Calculate the local file path
			relativePath := strings.TrimPrefix(path, staticDir.URLPath)
			fsPath := filepath.Join(config.PublicDir, staticDir.LocalPath, relativePath)
			
			// Check if file exists
			if info, err := os.Stat(fsPath); err == nil && !info.IsDir() {
				// Set cache headers if configured
				if staticDir.CacheTTL > 0 {
					w.Header().Set("Cache-Control", fmt.Sprintf("public, max-age=%d", staticDir.CacheTTL))
				}
				
				// Set content type and serve
				setContentType(w, fsPath)
				http.ServeFile(w, r, fsPath)
				log.Printf("Serving static file from directory: %s -> %s", path, fsPath)
				return true
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

// tryFiles implements nginx-style try_files behavior for non-authenticated routes
// Attempts to serve static files with common extensions before falling back to Rails
func tryFiles(w http.ResponseWriter, r *http.Request, config *Config) bool {
	path := r.URL.Path
	
	// Only try files for paths that don't already have an extension
	if filepath.Ext(path) != "" {
		return false
	}
	
	// Skip if try_files is disabled (no suffixes configured)
	if len(config.TryFilesSuffixes) == 0 {
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

// proxyRequest proxies a request to another server
func proxyRequest(w http.ResponseWriter, r *http.Request, route *ProxyRoute) {
	target, err := url.Parse(route.ProxyPass)
	if err != nil {
		http.Error(w, "Invalid proxy target", http.StatusInternalServerError)
		return
	}

	proxy := httputil.NewSingleHostReverseProxy(target)
	
	// Add custom headers
	for k, v := range route.SetHeaders {
		r.Header.Set(k, v)
	}
	
	proxy.ServeHTTP(w, r)
}