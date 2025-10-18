# OAuth Implementation Plan for Navigator

**Status:** Planning Document - For Future Consideration
**Last Updated:** 2025-10-18
**Authors:** Sam Ruby, Claude Code

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Configuration Design](#configuration-design)
- [Google OAuth Setup](#google-oauth-setup)
- [Database Schema Options](#database-schema-options)
- [Implementation Phases](#implementation-phases)
- [Security Considerations](#security-considerations)
- [Testing Strategy](#testing-strategy)
- [Migration Path](#migration-path)

---

## Overview

### Goal

Add OAuth 2.0 authentication support to Navigator while maintaining backward compatibility with existing HTTP Basic Authentication. Navigator is the ideal place for OAuth since it's always running, while Rails apps start on demand.

### Key Principles

1. **Configuration-driven**: No hardcoded database paths, table names, or column names
2. **Flexible schema**: Support both extending existing tables and creating new tables
3. **Backward compatible**: HTTP Basic Auth continues to work
4. **Security-first**: Strip untrusted headers, validate all inputs
5. **Multi-provider**: Design supports Google, GitHub, Microsoft, etc.

### Why Navigator for OAuth

- ✅ Navigator is always running (Rails apps start on demand)
- ✅ Navigator already handles authentication early in request pipeline
- ✅ Centralized user database (index.sqlite3) already exists
- ✅ Single place to manage sessions/tokens
- ✅ Rails apps can trust headers from Navigator (they're behind the proxy)

---

## Architecture

### Authentication Flow

```mermaid
sequenceDiagram
    participant Browser
    participant Navigator
    participant Google as Google OAuth
    participant Rails

    Browser->>Navigator: 1. GET /showcase/admin
    Note over Navigator: 2. No session/auth
    Navigator-->>Browser: 3. Redirect to /auth/google

    Browser->>Navigator: 4. GET /auth/google
    Navigator-->>Browser: 5. Redirect to Google OAuth

    Browser->>Google: 6. User authenticates
    Google-->>Browser: 7. Redirect to callback with code

    Browser->>Navigator: 8. GET /auth/google/callback?code=...
    Note over Navigator: 9. Exchange code for token<br/>Get user email from Google<br/>Query users by email<br/>Create session
    Navigator-->>Browser: 10. Set-Cookie + Redirect to /showcase/admin

    Browser->>Navigator: 11. GET /showcase/admin<br/>(Cookie: navigator_session)
    Note over Navigator: 12. Validate session<br/>Extract userid<br/>Strip client headers<br/>Set X-Auth-User header
    Navigator->>Rails: 13. Proxy request<br/>(X-Auth-User: rubys)
    Note over Rails: 14. Trust X-Auth-User<br/>Query sites column<br/>Validate authorization
    Rails-->>Navigator: 15. Response
    Navigator-->>Browser: 16. Response
```

### Component Responsibilities

#### Navigator Responsibilities

1. **OAuth Provider Integration**
   - Handle OAuth redirect flow
   - Exchange authorization codes for tokens
   - Extract user info (email, name) from providers

2. **User Lookup** (Authentication Only)
   - Query configured database for user by email or oauth_uid
   - Retrieve userid for authenticated user
   - Handle user provisioning (create/link accounts)
   - **Note:** Navigator does NOT check site authorization - that's Rails' job

3. **Session Management**
   - Issue session cookies or JWT tokens
   - Validate sessions on every request
   - Handle session expiration and logout

4. **Security**
   - Strip untrusted authentication headers from client requests
   - Set X-Auth-User header only after successful authentication
   - Protect against replay attacks, session hijacking

5. **Header Injection**
   - After auth, set `X-Auth-User: <userid>` for Rails
   - Rails trusts this header (Navigator is the only entry point)

#### Rails Responsibilities

1. **Trust Navigator Headers & Authorize**
   - Read `X-Auth-User` header set by Navigator
   - **Authorization:** Check `sites` column to validate user can access requested event/site
   - Enforce per-event, per-studio permissions
   - Fall back to HTTP Basic Auth for direct access (dev/test)

2. **User Management**
   - CRUD operations on users table
   - Manage site/event authorization lists (`sites` column)
   - Handle user provisioning UI (if needed)

---

## Configuration Design

### YAML Configuration Structure

```yaml
# config/navigator.yml

auth:
  enabled: true
  realm: Showcase

  # Existing HTTP Basic Auth (backward compatible)
  htpasswd: "/path/to/db/htpasswd"

  # NEW: OAuth Configuration
  oauth:
    enabled: true

    # Database Configuration (fully configurable)
    database:
      path: "${DB_PATH}/index.sqlite3"          # Supports env var expansion
      driver: "sqlite3"                          # Future: "postgres", "mysql"

      # Table and column mapping (no hardcoded assumptions)
      users_table: "users"
      columns:
        userid: "userid"                         # Internal username/identifier
        email: "email"                           # For OAuth email matching
        oauth_provider: "oauth_provider"         # 'google', 'github', etc.
        oauth_uid: "oauth_uid"                   # Provider's unique user ID
        oauth_data: "oauth_data"                 # JSON blob for extra data
        last_login_at: "last_login_at"          # Optional: track logins
        last_login_method: "last_login_method"  # Optional: 'oauth' or 'password'

    # Session configuration
    session:
      cookie_name: "navigator_session"
      cookie_max_age: "24h"                      # Duration format
      cookie_secure: true                        # HTTPS only
      cookie_httponly: true                      # No JavaScript access
      cookie_samesite: "Lax"                     # CSRF protection

      # Session storage strategy
      type: "signed_cookie"                      # Options: signed_cookie, jwt, database
      secret_env: "NAVIGATOR_SESSION_SECRET"     # For signing cookies/JWTs

    # OAuth Providers
    providers:
      - name: google
        enabled: true
        client_id: "123456789-abcdefg.apps.googleusercontent.com"
        client_secret_env: "GOOGLE_CLIENT_SECRET"
        redirect_url: "https://showcase.example.com/auth/google/callback"
        scopes: [openid, email, profile]

        # User provisioning options (for future Rails integration)
        auto_create: false                       # Auto-create user on first OAuth login?
        require_admin_approval: true             # Require manual approval?
        # Note: Site authorization (which events user can access) is handled by Rails
        # via the 'sites' column in the users table. Navigator only handles authentication.

      - name: github
        enabled: false
        client_id: "Iv1.abc123def456"
        client_secret_env: "GITHUB_CLIENT_SECRET"
        redirect_url: "https://showcase.example.com/auth/github/callback"
        scopes: [user:email]
        auto_create: false

      - name: microsoft
        enabled: false
        client_id: "12345678-1234-1234-1234-123456789012"
        client_secret_env: "MICROSOFT_CLIENT_SECRET"
        redirect_url: "https://showcase.example.com/auth/microsoft/callback"
        tenant: "common"                         # Azure AD tenant
        scopes: [openid, email, profile]
        auto_create: false

    # Account linking
    account_linking:
      enabled: true                              # Allow linking OAuth to existing accounts?
      require_password: true                     # Require password to link?
      link_by_email: true                        # Auto-link if email matches?

  # Public paths (existing + OAuth endpoints)
  public_paths:
    - "/showcase/assets/"
    - "/showcase/cable"
    - "/showcase/docs/"
    - "/auth/*"                                  # OAuth endpoints are public
    - "*.css"
    - "*.js"
    - "*.png"
```

### Environment Variables

```bash
# Database path (can be overridden)
export DB_PATH="/var/lib/showcase/db"

# OAuth Client Secrets (NEVER in config files)
export GOOGLE_CLIENT_SECRET="GOCSPX-xxxxxxxxxxxxxxxxxxxxxxxx"
export GITHUB_CLIENT_SECRET="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export MICROSOFT_CLIENT_SECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Session Secret (for signing cookies/JWTs)
export NAVIGATOR_SESSION_SECRET="$(openssl rand -base64 32)"
```

### Configuration Validation

Navigator will validate configuration on startup:

```go
// Validate database configuration
if cfg.OAuth.Enabled {
    if cfg.OAuth.Database.Path == "" {
        return errors.New("oauth.database.path is required")
    }
    if cfg.OAuth.Database.UsersTable == "" {
        return errors.New("oauth.database.users_table is required")
    }

    // Validate required columns are mapped
    requiredCols := []string{"userid", "email"}
    for _, col := range requiredCols {
        if cfg.OAuth.Database.Columns[col] == "" {
            return fmt.Errorf("oauth.database.columns.%s is required", col)
        }
    }

    // Validate at least one provider is enabled
    hasProvider := false
    for _, p := range cfg.OAuth.Providers {
        if p.Enabled {
            hasProvider = true
            break
        }
    }
    if !hasProvider {
        return errors.New("at least one OAuth provider must be enabled")
    }
}
```

---

## Google OAuth Setup

### Prerequisites

1. Google Account
2. Access to Google Cloud Console
3. Domain or public URL for callback (HTTPS required for production)

### Step-by-Step Setup

#### 1. Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click "Select a project" → "New Project"
3. Enter project name: `showcase-oauth` (or your preference)
4. Click "Create"
5. Wait for project creation (takes ~30 seconds)

#### 2. Enable Google+ API

1. In the Cloud Console, go to "APIs & Services" → "Library"
2. Search for "Google+ API"
3. Click on "Google+ API"
4. Click "Enable"
5. Wait for API to be enabled

**Note:** Even though Google+ is deprecated, the API is still used for OAuth user info.

#### 3. Configure OAuth Consent Screen

1. Go to "APIs & Services" → "OAuth consent screen"
2. Select user type:
   - **Internal**: Only for Google Workspace domains (if you have one)
   - **External**: For public use (most common)
3. Click "Create"

4. Fill in App Information:
   - **App name**: `Showcase Dance Events` (or your app name)
   - **User support email**: Your email address
   - **App logo**: (optional) Upload logo image
   - **Application home page**: `https://showcase.example.com`
   - **Application privacy policy**: `https://showcase.example.com/privacy` (optional)
   - **Application terms of service**: `https://showcase.example.com/terms` (optional)
   - **Authorized domains**: `showcase.example.com` (your domain)
   - **Developer contact information**: Your email address

5. Click "Save and Continue"

6. Scopes:
   - Click "Add or Remove Scopes"
   - Select these scopes:
     - `openid`
     - `userinfo.email`
     - `userinfo.profile`
   - Click "Update"
   - Click "Save and Continue"

7. Test users (for External apps in testing mode):
   - Add your Google account email
   - Add other test user emails
   - Click "Save and Continue"

8. Review and click "Back to Dashboard"

#### 4. Create OAuth Client ID

1. Go to "APIs & Services" → "Credentials"
2. Click "Create Credentials" → "OAuth client ID"
3. Application type: "Web application"
4. Name: `Showcase Navigator`

5. **Authorized JavaScript origins** (optional for OAuth flow):
   - `https://showcase.example.com`
   - `http://localhost:3000` (for local development)

6. **Authorized redirect URIs** (CRITICAL):
   - `https://showcase.example.com/auth/google/callback`
   - `http://localhost:3000/auth/google/callback` (for local development)

   **Important:** These MUST match exactly what you configure in Navigator YAML.

7. Click "Create"

8. **Save your credentials** (shown in popup):
   - **Client ID**: `123456789012-abcdefghijklmnopqrstuvwxyz123456.apps.googleusercontent.com`
   - **Client Secret**: `GOCSPX-xxxxxxxxxxxxxxxxxxxxxxxx`

   **CRITICAL:** Save these now! You won't see the client secret again.

9. Click "OK"

#### 5. Configure Navigator

1. Add Client ID to `config/navigator.yml`:
   ```yaml
   oauth:
     providers:
       - name: google
         client_id: "123456789012-abcdefghijklmnopqrstuvwxyz123456.apps.googleusercontent.com"
         redirect_url: "https://showcase.example.com/auth/google/callback"
   ```

2. Set Client Secret as environment variable (NEVER commit to git):
   ```bash
   export GOOGLE_CLIENT_SECRET="GOCSPX-xxxxxxxxxxxxxxxxxxxxxxxx"
   ```

3. Generate session secret:
   ```bash
   export NAVIGATOR_SESSION_SECRET="$(openssl rand -base64 32)"
   ```

#### 6. Testing OAuth Flow

1. Start Navigator with configuration
2. Visit `https://showcase.example.com/auth/google`
3. Should redirect to Google login
4. Log in with test user (must be in OAuth consent screen test users list)
5. Should redirect back to `/auth/google/callback`
6. Navigator should:
   - Exchange code for token
   - Get user info from Google
   - Look up user in database by email
   - Create session cookie
   - Redirect to original URL or home page

#### 7. Publishing App (Optional)

**During Testing:**
- App stays in "Testing" mode
- Only test users can log in
- Warning shown to users: "This app hasn't been verified by Google"

**For Production:**
1. Go to "OAuth consent screen"
2. Click "Publish App"
3. Review publishing requirements
4. Submit for verification (if you want to remove warnings)
5. Verification process can take days/weeks

**Note:** For internal use (dance studios), you can stay in testing mode indefinitely.

#### 8. Security Best Practices

```bash
# Store secrets in environment, not in files
echo 'export GOOGLE_CLIENT_SECRET="GOCSPX-xxx"' >> ~/.bashrc

# Or use a secrets manager
# - Fly.io Secrets
# - AWS Secrets Manager
# - HashiCorp Vault
# - 1Password CLI

# Rotate secrets periodically
# 1. Create new OAuth client in Google Console
# 2. Update environment variable
# 3. Restart Navigator
# 4. Delete old OAuth client after verification
```

#### 9. Troubleshooting

**Error: redirect_uri_mismatch**
- Check that redirect URL in config exactly matches Google Console
- Must include protocol (http:// or https://)
- Cannot have trailing slash unless configured that way
- Check for typos in domain name

**Error: access_denied**
- User clicked "Cancel" on consent screen
- User is not in test users list (for testing mode apps)

**Error: invalid_client**
- Client ID or Client Secret is wrong
- Client was deleted from Google Console
- Environment variable not set correctly

**Can't see consent screen / stuck in loop**
- Clear cookies for your domain
- Try incognito/private browsing mode
- Check that redirect URI is publicly accessible

---

## Database Schema Options

### Option 1: Extend Existing `users` Table (Recommended)

**Pros:**
- Single table, simple queries
- Backward compatible with existing users
- Users can have both password and OAuth

**Cons:**
- Couples OAuth data to user table
- Limited to one OAuth account per user (can be worked around with JSON)

**Migration:**

```sql
-- Add OAuth columns to existing users table
ALTER TABLE users ADD COLUMN oauth_provider varchar;
ALTER TABLE users ADD COLUMN oauth_uid varchar;
ALTER TABLE users ADD COLUMN oauth_data text;
ALTER TABLE users ADD COLUMN last_login_at datetime;
ALTER TABLE users ADD COLUMN last_login_method varchar;

-- Add indexes for performance
CREATE INDEX index_users_on_email ON users(email);
CREATE UNIQUE INDEX index_users_on_oauth_provider_and_uid
  ON users(oauth_provider, oauth_uid)
  WHERE oauth_provider IS NOT NULL;

-- Add index for last login queries
CREATE INDEX index_users_on_last_login_at ON users(last_login_at);
```

**Configuration:**

```yaml
oauth:
  database:
    users_table: "users"
    columns:
      userid: "userid"
      email: "email"
      oauth_provider: "oauth_provider"
      oauth_uid: "oauth_uid"
      oauth_data: "oauth_data"
      last_login_at: "last_login_at"
      last_login_method: "last_login_method"
```

**Query examples:**

```go
// Lookup by OAuth provider + uid (most reliable)
SELECT userid FROM users
WHERE oauth_provider = ? AND oauth_uid = ?

// Lookup by email (for first-time OAuth or linking)
SELECT userid, oauth_provider FROM users
WHERE email = ?

// Update OAuth data after login
UPDATE users
SET oauth_provider = ?, oauth_uid = ?, oauth_data = ?,
    last_login_at = ?, last_login_method = 'oauth'
WHERE userid = ?

// Note: The 'sites' column (which events user can access) is queried by Rails
// for authorization, not by Navigator. Navigator only handles authentication.
```

### Option 2: Separate `oauth_accounts` Table

**Pros:**
- Clean separation of concerns
- Supports multiple OAuth providers per user
- Can link/unlink providers without affecting user
- Easy to extend with provider-specific fields

**Cons:**
- Requires JOIN for user lookup
- More complex queries
- Two tables to manage

**Migration:**

```sql
-- Create separate OAuth accounts table
CREATE TABLE oauth_accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  provider VARCHAR NOT NULL,
  uid VARCHAR NOT NULL,
  email VARCHAR,
  display_name VARCHAR,
  data TEXT,  -- JSON blob for extra provider data
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  last_login_at DATETIME,
  FOREIGN KEY (user_id) REFERENCES users(id),
  UNIQUE(provider, uid)
);

-- Indexes
CREATE INDEX index_oauth_accounts_on_user_id ON oauth_accounts(user_id);
CREATE INDEX index_oauth_accounts_on_email ON oauth_accounts(email);
CREATE UNIQUE INDEX index_oauth_accounts_on_provider_uid ON oauth_accounts(provider, uid);

-- Optional: Add index on users.email if doesn't exist
CREATE INDEX index_users_on_email ON users(email);
```

**Configuration:**

```yaml
oauth:
  database:
    users_table: "users"
    oauth_accounts_table: "oauth_accounts"  # NEW

    # Users table columns
    users_columns:
      id: "id"
      userid: "userid"
      email: "email"
      # Note: 'sites' column exists for Rails authorization but Navigator doesn't query it

    # OAuth accounts table columns
    oauth_columns:
      user_id: "user_id"
      provider: "provider"
      uid: "uid"
      email: "email"
      data: "data"
      last_login_at: "last_login_at"
```

**Query examples:**

```go
// Lookup by OAuth provider + uid
SELECT u.userid
FROM users u
JOIN oauth_accounts oa ON u.id = oa.user_id
WHERE oa.provider = ? AND oa.uid = ?

// Lookup by email (for linking)
SELECT u.userid, u.id
FROM users u
WHERE u.email = ?

// Link OAuth to existing user
INSERT INTO oauth_accounts (user_id, provider, uid, email, data, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?)

// Update last login
UPDATE oauth_accounts
SET last_login_at = ?, updated_at = ?
WHERE provider = ? AND uid = ?

// Note: Navigator only needs userid for authentication.
// Rails queries the 'sites' column separately for authorization.
```

### Option 3: JSON Column in Existing Table (Minimal)

**Pros:**
- Minimal schema changes
- Supports multiple providers
- Flexible for future providers

**Cons:**
- Cannot efficiently query/index JSON in SQLite
- Requires application-level filtering
- Harder to debug

**Not recommended** unless you need absolute minimal schema changes and have very few users.

### Recommendation

**Use Option 1 (Extend users table)** for the showcase application because:

1. ✅ Simple implementation
2. ✅ Fast queries (single table)
3. ✅ Most users will use one OAuth provider
4. ✅ Backward compatible
5. ✅ Easy to migrate to Option 2 later if needed

---

## Implementation Phases

### Phase 0: Preparation (Before Coding)

**Tasks:**
- [ ] Review and approve this plan
- [ ] Decide on database schema (Option 1 vs 2)
- [ ] Set up Google OAuth credentials (see setup guide above)
- [ ] Create test accounts for development
- [ ] Generate session secret

**Deliverables:**
- Configuration file with OAuth section
- Environment variables documented
- Test credentials available

---

### Phase 1: Configuration & Database (Week 1)

**Goals:**
- Set up configurable database access
- Implement schema migration
- Add configuration validation

**Tasks:**

1. **Add Go Dependencies**
   ```bash
   cd navigator
   go get github.com/mattn/go-sqlite3
   go get golang.org/x/oauth2
   go get github.com/coreos/go-oidc/v3
   go get github.com/golang-jwt/jwt/v5  # Optional: for JWT sessions
   ```

2. **Create Database Package**
   - `navigator/internal/oauth/database.go`
   - Configurable connection
   - User lookup functions
   - No hardcoded table/column names

3. **Configuration Types**
   - `navigator/internal/config/types.go` - Add OAuth config structs
   - Validation for required fields
   - Environment variable expansion

4. **Schema Migration**
   - Rails migration to add OAuth columns
   - Or SQL script for manual application
   - Documentation for both approaches

**Testing:**
- [ ] Configuration loads successfully
- [ ] Database connection works
- [ ] User lookup by email works
- [ ] User lookup by oauth_provider + oauth_uid works
- [ ] Handles missing columns gracefully

**Code Example:**

```go
// navigator/internal/oauth/database.go

type DatabaseConfig struct {
    Path        string
    Driver      string
    UsersTable  string
    Columns     ColumnMapping
}

type ColumnMapping struct {
    UserID         string
    Email          string
    OAuthProvider  string
    OAuthUID       string
    OAuthData      string
    LastLoginAt    string
    LastLoginMethod string
}

type OAuthDatabase struct {
    db     *sql.DB
    config DatabaseConfig
}

func NewOAuthDatabase(config DatabaseConfig) (*OAuthDatabase, error) {
    db, err := sql.Open(config.Driver, config.Path)
    if err != nil {
        return nil, fmt.Errorf("failed to open database: %w", err)
    }

    return &OAuthDatabase{db: db, config: config}, nil
}

// LookupByEmail finds user by email address
func (d *OAuthDatabase) LookupByEmail(email string) (*User, error) {
    query := fmt.Sprintf(
        "SELECT %s, %s, %s FROM %s WHERE %s = ?",
        d.config.Columns.UserID,
        d.config.Columns.Email,
        d.config.Columns.OAuthProvider,
        d.config.UsersTable,
        d.config.Columns.Email,
    )

    var user User
    err := d.db.QueryRow(query, email).Scan(
        &user.UserID,
        &user.Email,
        &user.OAuthProvider,
    )

    if err == sql.ErrNoRows {
        return nil, ErrUserNotFound
    }
    if err != nil {
        return nil, fmt.Errorf("database query failed: %w", err)
    }

    return &user, nil
}

// LookupByOAuth finds user by OAuth provider and UID
func (d *OAuthDatabase) LookupByOAuth(provider, uid string) (*User, error) {
    query := fmt.Sprintf(
        "SELECT %s, %s FROM %s WHERE %s = ? AND %s = ?",
        d.config.Columns.UserID,
        d.config.Columns.Email,
        d.config.UsersTable,
        d.config.Columns.OAuthProvider,
        d.config.Columns.OAuthUID,
    )

    var user User
    err := d.db.QueryRow(query, provider, uid).Scan(
        &user.UserID,
        &user.Email,
    )

    if err == sql.ErrNoRows {
        return nil, ErrUserNotFound
    }
    if err != nil {
        return nil, fmt.Errorf("database query failed: %w", err)
    }

    return &user, nil
}

// UpdateOAuthInfo links OAuth to user
func (d *OAuthDatabase) UpdateOAuthInfo(userid, provider, uid string, data map[string]interface{}) error {
    jsonData, _ := json.Marshal(data)

    query := fmt.Sprintf(
        "UPDATE %s SET %s = ?, %s = ?, %s = ?, %s = ?, %s = ? WHERE %s = ?",
        d.config.UsersTable,
        d.config.Columns.OAuthProvider,
        d.config.Columns.OAuthUID,
        d.config.Columns.OAuthData,
        d.config.Columns.LastLoginAt,
        d.config.Columns.LastLoginMethod,
        d.config.Columns.UserID,
    )

    _, err := d.db.Exec(query, provider, uid, jsonData, time.Now(), "oauth", userid)
    return err
}
```

---

### Phase 2: OAuth Provider Integration (Week 2)

**Goals:**
- Implement Google OAuth flow
- Handle authorization code exchange
- Extract user info from tokens

**Tasks:**

1. **Create OAuth Package**
   - `navigator/internal/oauth/provider.go`
   - `navigator/internal/oauth/google.go`
   - Support for OpenID Connect discovery

2. **OAuth Handlers**
   - `/auth/google` - Initiates OAuth flow
   - `/auth/google/callback` - Handles OAuth callback
   - State parameter for CSRF protection

3. **User Info Extraction**
   - Get email from ID token
   - Get name, picture from userinfo endpoint
   - Store in configurable oauth_data column

**Testing:**
- [ ] OAuth redirect works
- [ ] State parameter prevents CSRF
- [ ] Code exchange successful
- [ ] User info extracted correctly
- [ ] Handles OAuth errors gracefully

**Code Example:**

```go
// navigator/internal/oauth/google.go

type GoogleProvider struct {
    config   *oauth2.Config
    verifier *oidc.IDTokenVerifier
}

func NewGoogleProvider(clientID, clientSecret, redirectURL string) (*GoogleProvider, error) {
    ctx := context.Background()

    provider, err := oidc.NewProvider(ctx, "https://accounts.google.com")
    if err != nil {
        return nil, fmt.Errorf("failed to create OIDC provider: %w", err)
    }

    config := &oauth2.Config{
        ClientID:     clientID,
        ClientSecret: clientSecret,
        RedirectURL:  redirectURL,
        Endpoint:     provider.Endpoint(),
        Scopes:       []string{oidc.ScopeOpenID, "email", "profile"},
    }

    verifier := provider.Verifier(&oidc.Config{ClientID: clientID})

    return &GoogleProvider{
        config:   config,
        verifier: verifier,
    }, nil
}

func (g *GoogleProvider) GetAuthURL(state string) string {
    return g.config.AuthCodeURL(state)
}

func (g *GoogleProvider) ExchangeCode(ctx context.Context, code string) (*UserInfo, error) {
    // Exchange authorization code for token
    token, err := g.config.Exchange(ctx, code)
    if err != nil {
        return nil, fmt.Errorf("code exchange failed: %w", err)
    }

    // Extract ID token
    rawIDToken, ok := token.Extra("id_token").(string)
    if !ok {
        return nil, errors.New("no id_token in token response")
    }

    // Verify ID token
    idToken, err := g.verifier.Verify(ctx, rawIDToken)
    if err != nil {
        return nil, fmt.Errorf("failed to verify ID token: %w", err)
    }

    // Extract claims
    var claims struct {
        Sub           string `json:"sub"`
        Email         string `json:"email"`
        EmailVerified bool   `json:"email_verified"`
        Name          string `json:"name"`
        Picture       string `json:"picture"`
    }
    if err := idToken.Claims(&claims); err != nil {
        return nil, fmt.Errorf("failed to parse claims: %w", err)
    }

    if !claims.EmailVerified {
        return nil, errors.New("email not verified")
    }

    return &UserInfo{
        Provider:    "google",
        UID:         claims.Sub,
        Email:       claims.Email,
        DisplayName: claims.Name,
        Picture:     claims.Picture,
        RawData: map[string]interface{}{
            "sub":            claims.Sub,
            "email":          claims.Email,
            "email_verified": claims.EmailVerified,
            "name":           claims.Name,
            "picture":        claims.Picture,
        },
    }, nil
}
```

---

### Phase 3: Session Management (Week 3)

**Goals:**
- Implement session creation
- Session validation on requests
- Secure cookie handling

**Tasks:**

1. **Session Package**
   - `navigator/internal/oauth/session.go`
   - Signed cookie implementation
   - Session data structure

2. **Session Lifecycle**
   - Create session after OAuth success
   - Validate session on every request
   - Handle expiration
   - Logout endpoint

3. **Security**
   - HMAC signing of cookies
   - HTTPOnly, Secure, SameSite flags
   - Session expiration

**Testing:**
- [ ] Session created correctly
- [ ] Session validated successfully
- [ ] Invalid sessions rejected
- [ ] Expired sessions rejected
- [ ] Tampered cookies rejected
- [ ] Logout clears session

**Code Example:**

```go
// navigator/internal/oauth/session.go

type SessionManager struct {
    secret   []byte
    maxAge   time.Duration
    cookieCfg CookieConfig
}

type CookieConfig struct {
    Name     string
    Secure   bool
    HTTPOnly bool
    SameSite http.SameSite
}

type SessionData struct {
    UserID    string    `json:"userid"`
    Provider  string    `json:"provider"`
    IssuedAt  time.Time `json:"iat"`
    ExpiresAt time.Time `json:"exp"`
}

func NewSessionManager(secret string, maxAge time.Duration, cfg CookieConfig) *SessionManager {
    return &SessionManager{
        secret:    []byte(secret),
        maxAge:    maxAge,
        cookieCfg: cfg,
    }
}

func (s *SessionManager) CreateSession(w http.ResponseWriter, userid, provider string) error {
    now := time.Now()

    session := SessionData{
        UserID:    userid,
        Provider:  provider,
        IssuedAt:  now,
        ExpiresAt: now.Add(s.maxAge),
    }

    // Serialize session data
    data, err := json.Marshal(session)
    if err != nil {
        return fmt.Errorf("failed to marshal session: %w", err)
    }

    // Sign the session data
    mac := hmac.New(sha256.New, s.secret)
    mac.Write(data)
    signature := mac.Sum(nil)

    // Combine data + signature
    cookieValue := base64.URLEncoding.EncodeToString(data) + "." +
                   base64.URLEncoding.EncodeToString(signature)

    // Set cookie
    http.SetCookie(w, &http.Cookie{
        Name:     s.cookieCfg.Name,
        Value:    cookieValue,
        Path:     "/",
        MaxAge:   int(s.maxAge.Seconds()),
        Secure:   s.cookieCfg.Secure,
        HttpOnly: s.cookieCfg.HTTPOnly,
        SameSite: s.cookieCfg.SameSite,
    })

    return nil
}

func (s *SessionManager) ValidateSession(r *http.Request) (*SessionData, error) {
    cookie, err := r.Cookie(s.cookieCfg.Name)
    if err != nil {
        return nil, ErrNoSession
    }

    // Split data and signature
    parts := strings.Split(cookie.Value, ".")
    if len(parts) != 2 {
        return nil, ErrInvalidSession
    }

    data, err := base64.URLEncoding.DecodeString(parts[0])
    if err != nil {
        return nil, ErrInvalidSession
    }

    signature, err := base64.URLEncoding.DecodeString(parts[1])
    if err != nil {
        return nil, ErrInvalidSession
    }

    // Verify signature
    mac := hmac.New(sha256.New, s.secret)
    mac.Write(data)
    expectedSignature := mac.Sum(nil)

    if !hmac.Equal(signature, expectedSignature) {
        return nil, ErrInvalidSession
    }

    // Deserialize session data
    var session SessionData
    if err := json.Unmarshal(data, &session); err != nil {
        return nil, ErrInvalidSession
    }

    // Check expiration
    if time.Now().After(session.ExpiresAt) {
        return nil, ErrSessionExpired
    }

    return &session, nil
}

func (s *SessionManager) ClearSession(w http.ResponseWriter) {
    http.SetCookie(w, &http.Cookie{
        Name:     s.cookieCfg.Name,
        Value:    "",
        Path:     "/",
        MaxAge:   -1,
        Secure:   s.cookieCfg.Secure,
        HttpOnly: s.cookieCfg.HTTPOnly,
        SameSite: s.cookieCfg.SameSite,
    })
}
```

---

### Phase 4: Handler Integration (Week 4)

**Goals:**
- Integrate OAuth with Navigator's HTTP handler
- Strip untrusted headers
- Set X-Auth-User after authentication

**Tasks:**

1. **Update Handler**
   - `navigator/internal/server/handler.go`
   - Strip authentication headers early
   - Check session before Basic Auth
   - Set X-Auth-User header

2. **OAuth Endpoints**
   - Register `/auth/:provider` route
   - Register `/auth/:provider/callback` route
   - Register `/auth/logout` route

3. **Public Path Updates**
   - Add `/auth/*` to public paths
   - Ensure OAuth endpoints don't require auth

**Testing:**
- [ ] Client headers stripped
- [ ] Session validated before Basic Auth
- [ ] X-Auth-User set correctly
- [ ] OAuth endpoints accessible without auth
- [ ] Fallback to Basic Auth works

**Code Example:**

```go
// navigator/internal/server/handler.go

func (h *handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    // CRITICAL SECURITY: Strip authentication headers from client
    // These headers are ONLY set by Navigator after successful authentication
    untrustedAuthHeaders := []string{
        "X-Auth-User",
        "X-Remote-User",
        "X-Forwarded-User",
        "Remote-User",
        "X-Authenticated-User",
    }
    for _, header := range untrustedAuthHeaders {
        r.Header.Del(header)
    }

    // Set up request tracking
    requestID := generateRequestID()
    r.Header.Set("X-Request-Id", requestID)
    recorder := NewResponseRecorder(w, requestID, time.Now())

    // Check if this is an OAuth endpoint (always public)
    if strings.HasPrefix(r.URL.Path, "/auth/") {
        h.handleOAuthEndpoint(recorder, r)
        return
    }

    // Authenticate user
    var authUser string
    var authMethod string

    // 1. Try session-based auth (OAuth) first
    if h.oauth != nil && h.oauth.Enabled {
        if session, err := h.sessionMgr.ValidateSession(r); err == nil {
            authUser = session.UserID
            authMethod = "oauth"
            slog.Debug("Request authenticated via OAuth session",
                "user", authUser,
                "provider", session.Provider)
        }
    }

    // 2. Fall back to HTTP Basic Auth
    if authUser == "" {
        isPublic := auth.ShouldExcludeFromAuth(r.URL.Path, h.config)
        needsAuth := h.auth.IsEnabled() && !isPublic

        if needsAuth {
            if user, authenticated := h.auth.CheckAuth(r); authenticated {
                authUser = user
                authMethod = "basic"
                slog.Debug("Request authenticated via HTTP Basic Auth", "user", authUser)
            } else {
                recorder.SetMetadata("response_type", "auth-failure")
                h.auth.RequireAuth(recorder)
                return
            }
        }
    }

    // 3. Set X-Auth-User header for Rails (only if authenticated)
    if authUser != "" {
        r.Header.Set("X-Auth-User", authUser)
        slog.Debug("Set X-Auth-User header", "user", authUser, "method", authMethod)
    }

    // Continue with request handling
    // (sticky sessions, rewrites, reverse proxies, static files, web app proxy)
    // ...
}

func (h *handler) handleOAuthEndpoint(w http.ResponseWriter, r *http.Request) {
    parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/auth/"), "/")
    if len(parts) < 1 {
        http.Error(w, "Invalid OAuth endpoint", http.StatusNotFound)
        return
    }

    provider := parts[0]

    switch len(parts) {
    case 1:
        // /auth/:provider - Initiate OAuth flow
        h.handleOAuthStart(w, r, provider)
    case 2:
        if parts[1] == "callback" {
            // /auth/:provider/callback - Handle OAuth callback
            h.handleOAuthCallback(w, r, provider)
        } else if parts[1] == "logout" {
            // /auth/:provider/logout - Logout
            h.handleOAuthLogout(w, r)
        } else {
            http.Error(w, "Invalid OAuth endpoint", http.StatusNotFound)
        }
    default:
        http.Error(w, "Invalid OAuth endpoint", http.StatusNotFound)
    }
}
```

---

### Phase 5: Rails Integration (Week 5)

**Goals:**
- Update Rails to trust X-Auth-User header
- Maintain backward compatibility
- Test end-to-end flow

**Tasks:**

1. **Update ApplicationController**
   - Trust X-Auth-User from Navigator
   - Fall back to Basic Auth for dev/test
   - Validate user authorization

2. **Add OAuth UI (Optional)**
   - Login page with OAuth buttons
   - Account linking UI
   - User profile showing OAuth providers

3. **Testing**
   - End-to-end OAuth flow
   - Mixed auth scenarios (OAuth + Basic)
   - Session expiration handling

**Code Example:**

```ruby
# app/controllers/application_controller.rb

def get_authentication
  # Trust X-Auth-User from Navigator (set after OAuth or Basic Auth)
  if request.headers['HTTP_X_AUTH_USER'].present?
    @authuser = request.headers['HTTP_X_AUTH_USER']
    slog.info("Authentication via Navigator header", user: @authuser)

    # Still validate user authorization for this site
    unless User.authorized?(@authuser)
      User.reload_auth
      forbidden unless User.authorized?(@authuser)
    end

    return true
  end

  # Fall back to HTTP Basic Auth (for direct access in dev/test)
  return nil unless Rails.env.production?
  return nil if ENV['RAILS_APP_OWNER'] == 'Demo'

  authenticate_or_request_with_http_basic do |id, password|
    id = id.strip
    @authuser = id

    if @@htpasswd&.has_entry?(id)
      authenticated = @@htpasswd.authenticated?(id, password)
      Rails.logger.info "Auth attempt: id=#{id.inspect}, authenticated=#{authenticated.inspect}"
      return true if authenticated
    else
      Rails.logger.info "Auth attempt: id=#{id.inspect}, has_entry=false"
    end

    # Reload and try again
    dbpath = ENV.fetch('RAILS_DB_VOLUME') { 'db' }
    htpasswd_file = "#{dbpath}/htpasswd"
    @@htpasswd = HTAuth::PasswdFile.open(htpasswd_file)

    if @@htpasswd.has_entry?(id)
      authenticated = @@htpasswd.authenticated?(id, password)
      Rails.logger.info "Auth retry: id=#{id.inspect}, authenticated=#{authenticated.inspect}"
      authenticated
    else
      Rails.logger.info "Auth retry: id=#{id.inspect}, has_entry=false"
      false
    end
  end
end
```

---

### Phase 6: Additional Providers (Optional)

**Goals:**
- Add GitHub OAuth
- Add Microsoft OAuth
- Generalize provider interface

**Tasks:**

1. **Create Provider Interface**
   - `navigator/internal/oauth/provider_interface.go`
   - Standardize provider methods

2. **Implement GitHub**
   - `navigator/internal/oauth/github.go`
   - Similar to Google implementation

3. **Implement Microsoft**
   - `navigator/internal/oauth/microsoft.go`
   - Handle Azure AD tenants

**Testing:**
- [ ] Multiple providers work simultaneously
- [ ] User can choose provider at login
- [ ] Account linking works across providers

---

## Security Considerations

### Critical Security Requirements

1. **Strip Untrusted Headers** (CRITICAL)
   - Strip all auth headers from client requests
   - Only set X-Auth-User after successful authentication
   - Test with malicious header injection

2. **HTTPS Required for Production** (CRITICAL)
   - OAuth requires HTTPS for callback URLs
   - Session cookies must have Secure flag
   - No plaintext transmission of tokens

3. **CSRF Protection**
   - Use state parameter in OAuth flow
   - Generate random state per request
   - Validate state in callback
   - Store state in secure cookie or Redis

4. **Session Security**
   - Sign all session cookies with HMAC
   - Use HTTPOnly flag (no JavaScript access)
   - Use SameSite=Lax or Strict
   - Implement session expiration
   - Consider session rotation

5. **Secret Management**
   - NEVER commit secrets to git
   - Use environment variables
   - Consider secrets manager (Fly.io Secrets, Vault, etc.)
   - Rotate secrets periodically

6. **Input Validation**
   - Validate all OAuth responses
   - Check email format
   - Verify email is verified by provider
   - Sanitize user data before storing

7. **Database Security**
   - Use parameterized queries (prevent SQL injection)
   - Validate column names from config
   - Limit database permissions
   - Encrypt oauth_data column (optional)

### Defense in Depth

**Layer 1: Navigator strips headers**
```go
r.Header.Del("X-Auth-User")
```

**Layer 2: Network isolation**
- Rails apps only accessible via Navigator
- Bind to 127.0.0.1, not 0.0.0.0

**Layer 3: Rails validates authorization**
```ruby
unless User.authorized?(@authuser)
  forbidden
end
```

**Layer 4: Session validation**
- HMAC signature verification
- Expiration checking
- Replay protection

### Security Testing Checklist

- [ ] Malicious header injection blocked
- [ ] Tampered session cookies rejected
- [ ] Expired sessions rejected
- [ ] CSRF state validation works
- [ ] SQL injection attempts fail
- [ ] XSS in OAuth data prevented
- [ ] Session fixation prevented
- [ ] Logout clears all session data
- [ ] HTTPS enforcement in production
- [ ] Secrets not logged or exposed

---

## Testing Strategy

### Unit Tests

**Navigator OAuth Package:**
```go
// navigator/internal/oauth/database_test.go
func TestDatabaseLookup(t *testing.T) {
    // Test user lookup by email
    // Test user lookup by OAuth provider + UID
    // Test missing users
    // Test SQL injection attempts
}

// navigator/internal/oauth/session_test.go
func TestSessionManagement(t *testing.T) {
    // Test session creation
    // Test session validation
    // Test signature verification
    // Test expiration
    // Test tampering detection
}

// navigator/internal/oauth/google_test.go
func TestGoogleProvider(t *testing.T) {
    // Test auth URL generation
    // Test code exchange (with mock)
    // Test token validation
    // Test user info extraction
}
```

**Navigator Handler:**
```go
// navigator/internal/server/oauth_test.go
func TestOAuthFlow(t *testing.T) {
    // Test OAuth initiation
    // Test callback handling
    // Test session creation
    // Test header stripping
    // Test X-Auth-User header setting
}

func TestSecurityHeaders(t *testing.T) {
    // Test malicious headers stripped
    // Test legitimate headers preserved
    // Test X-Auth-User only set after auth
}
```

### Integration Tests

**End-to-End OAuth Flow:**
```go
func TestOAuthEndToEnd(t *testing.T) {
    // 1. Start Navigator with test config
    // 2. Start mock OAuth provider
    // 3. Start test Rails app
    // 4. Simulate OAuth flow
    // 5. Verify session created
    // 6. Verify Rails receives X-Auth-User
    // 7. Verify authorization works
}
```

**Mixed Authentication:**
```go
func TestMixedAuth(t *testing.T) {
    // Test OAuth user access
    // Test Basic Auth user access
    // Test user with both OAuth and password
    // Test fallback scenarios
}
```

### Manual Testing

**OAuth Flow:**
1. Visit protected page → redirects to Navigator login
2. Click "Sign in with Google" → redirects to Google
3. Authenticate with Google → redirects to callback
4. Navigator creates session → redirects to original page
5. Access granted, session persists

**Session Management:**
1. Log in via OAuth
2. Close browser (session cookie persists)
3. Reopen browser → still logged in
4. Wait for session expiration → requires re-login
5. Click logout → session cleared

**Security Testing:**
1. Try to send X-Auth-User header → should be stripped
2. Tamper with session cookie → should be rejected
3. Use expired session → should require re-login
4. Change CSRF state → should be rejected
5. Try SQL injection in email → should be sanitized

---

## Migration Path

### For Existing Deployments

**Step 1: Database Migration**
```bash
# Rails migration
bin/rails generate migration AddOAuthToUsers

# Or manual SQL
sqlite3 db/index.sqlite3 < migrations/add_oauth_columns.sql
```

**Step 2: Update Navigator Configuration**
```yaml
# Add OAuth section to config/navigator.yml
# Set environment variables
# Test configuration loads
```

**Step 3: Gradual Rollout**
```
Week 1: Deploy Navigator with OAuth, disabled
Week 2: Enable OAuth for test users only
Week 3: Enable for all users, keep Basic Auth
Week 4: Monitor, fix issues
Week 5: Consider deprecating Basic Auth (optional)
```

**Step 4: User Communication**
```
- Email users about new OAuth option
- Provide instructions for linking accounts
- Keep Basic Auth as fallback
- Offer support for migration issues
```

### Rollback Plan

If issues occur:

1. **Disable OAuth in config:**
   ```yaml
   oauth:
     enabled: false
   ```

2. **Restart Navigator:**
   ```bash
   kill -HUP $(cat /tmp/navigator.pid)
   ```

3. **Revert Rails changes:**
   - Comment out X-Auth-User trust code
   - Keep Basic Auth only

4. **Database rollback (optional):**
   ```sql
   -- OAuth columns are nullable, safe to leave
   -- Or drop if needed
   ALTER TABLE users DROP COLUMN oauth_provider;
   ALTER TABLE users DROP COLUMN oauth_uid;
   ALTER TABLE users DROP COLUMN oauth_data;
   ```

---

## Appendix A: Configuration Examples

### Minimal Configuration

```yaml
auth:
  enabled: true
  htpasswd: "db/htpasswd"

  oauth:
    enabled: true
    database:
      path: "db/index.sqlite3"
      driver: "sqlite3"
      users_table: "users"
      columns:
        userid: "userid"
        email: "email"
        oauth_provider: "oauth_provider"
        oauth_uid: "oauth_uid"

    session:
      cookie_name: "navigator_session"
      secret_env: "NAVIGATOR_SESSION_SECRET"

    providers:
      - name: google
        client_id: "YOUR_CLIENT_ID"
        client_secret_env: "GOOGLE_CLIENT_SECRET"
        redirect_url: "https://your-domain.com/auth/google/callback"
```

### Full Configuration with All Options

```yaml
auth:
  enabled: true
  realm: "Showcase"
  htpasswd: "${DB_PATH}/htpasswd"
  public_paths:
    - "/showcase/assets/"
    - "/auth/*"

  oauth:
    enabled: true

    database:
      path: "${DB_PATH}/index.sqlite3"
      driver: "sqlite3"
      users_table: "users"
      columns:
        userid: "userid"
        email: "email"
        oauth_provider: "oauth_provider"
        oauth_uid: "oauth_uid"
        oauth_data: "oauth_data"
        last_login_at: "last_login_at"
        last_login_method: "last_login_method"

    session:
      cookie_name: "navigator_session"
      cookie_max_age: "24h"
      cookie_secure: true
      cookie_httponly: true
      cookie_samesite: "Lax"
      type: "signed_cookie"
      secret_env: "NAVIGATOR_SESSION_SECRET"

    providers:
      - name: google
        enabled: true
        client_id: "123456789-abc.apps.googleusercontent.com"
        client_secret_env: "GOOGLE_CLIENT_SECRET"
        redirect_url: "https://showcase.example.com/auth/google/callback"
        scopes: [openid, email, profile]
        auto_create: false
        require_admin_approval: true

      - name: github
        enabled: true
        client_id: "Iv1.abc123def456"
        client_secret_env: "GITHUB_CLIENT_SECRET"
        redirect_url: "https://showcase.example.com/auth/github/callback"
        scopes: [user:email]
        auto_create: false

      - name: microsoft
        enabled: false
        client_id: "12345678-1234-1234-1234-123456789012"
        client_secret_env: "MICROSOFT_CLIENT_SECRET"
        redirect_url: "https://showcase.example.com/auth/microsoft/callback"
        tenant: "common"
        scopes: [openid, email, profile]
        auto_create: false

    account_linking:
      enabled: true
      require_password: true
      link_by_email: true
```

---

## Appendix B: Error Codes & Messages

| Error Code | Message | Cause | Resolution |
|------------|---------|-------|------------|
| `oauth_disabled` | OAuth is not enabled | OAuth config missing or disabled | Enable OAuth in config |
| `invalid_provider` | Unknown OAuth provider | Provider not in config | Check provider name |
| `missing_client_secret` | Client secret not found | Env var not set | Set client secret env var |
| `state_mismatch` | CSRF state validation failed | State cookie missing/tampered | Clear cookies, retry |
| `code_exchange_failed` | Failed to exchange code | Invalid code or network error | Check OAuth app settings |
| `email_not_verified` | Email not verified by provider | User's email unverified | Ask user to verify email |
| `user_not_found` | No user with this email | User doesn't exist in DB | Create user or enable auto_create |
| `account_disabled` | User account disabled | User marked inactive | Contact admin |
| `approval_required` | Account pending approval | require_admin_approval=true | Admin must approve account |
| `session_expired` | Session has expired | Session older than max_age | Log in again |
| `invalid_session` | Session validation failed | Cookie tampered or malformed | Clear cookies, log in again |

---

## Appendix C: Monitoring & Logging

### Recommended Log Points

**OAuth Flow:**
```
[INFO] OAuth: Starting authentication for provider=google
[DEBUG] OAuth: Redirecting to provider auth_url=https://accounts.google.com/...
[INFO] OAuth: Received callback code=xxx... state=xxx...
[DEBUG] OAuth: Exchanged code for token
[INFO] OAuth: Extracted user email=user@example.com uid=1234567890
[DEBUG] OAuth: Looking up user by email
[INFO] OAuth: User found userid=rubys
[INFO] OAuth: Created session userid=rubys provider=google
[DEBUG] OAuth: Set session cookie max_age=24h
```

**Authentication:**
```
[DEBUG] Auth: Stripped untrusted headers count=3
[DEBUG] Auth: Validating session cookie
[INFO] Auth: Session valid userid=rubys method=oauth
[DEBUG] Auth: Set X-Auth-User header value=rubys
```

### Metrics to Track

- OAuth login attempts (success/failure)
- OAuth provider distribution (Google vs GitHub vs ...)
- Session duration (average, p50, p95)
- Authentication errors by type
- Session expiration vs logout
- Account creation rate
- Account linking rate

### Monitoring Alerts

- High OAuth failure rate (> 5%)
- Database connection failures
- Session validation failures spike
- Expired session secret (sessions all fail)
- Provider API downtime

---

## Appendix D: Resources

### OAuth 2.0 Resources

- [OAuth 2.0 RFC 6749](https://datatracker.ietf.org/doc/html/rfc6749)
- [OpenID Connect Core](https://openid.net/specs/openid-connect-core-1_0.html)
- [OAuth 2.0 Security Best Practices](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-security-topics)

### Provider Documentation

- [Google OAuth 2.0](https://developers.google.com/identity/protocols/oauth2)
- [GitHub OAuth Apps](https://docs.github.com/en/developers/apps/building-oauth-apps)
- [Microsoft Identity Platform](https://docs.microsoft.com/en-us/azure/active-directory/develop/)

### Go Libraries

- [golang.org/x/oauth2](https://pkg.go.dev/golang.org/x/oauth2)
- [github.com/coreos/go-oidc](https://pkg.go.dev/github.com/coreos/go-oidc/v3/oidc)
- [github.com/mattn/go-sqlite3](https://github.com/mattn/go-sqlite3)

### Security Resources

- [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
- [OWASP Session Management](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html)

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-18 | Sam Ruby, Claude Code | Initial plan created |
| 1.1 | 2025-10-18 | Sam Ruby, Claude Code | **Removed `sites` from Navigator concerns** - Authorization is Rails' responsibility, Navigator only handles authentication |

