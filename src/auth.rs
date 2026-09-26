//! Authentication manager using Device Flow OAuth (Microsoft public client)

use crate::errors::{OmarchyError, Result};
use crate::models::{DeviceFlowResponse, TokenResponse, CachedToken};
use crate::keyring_mgr;
use log::{info, debug, warn};
use std::time::{SystemTime, Duration};

const PUBLIC_CLIENT_ID: &str = "04b07795-8ddb-461a-bbee-02f9e1bf7b46";
// const TENANT_ID: &str = "common";  // Unused; part of OAuth spec but not needed for public client flow
const GRAPH_SCOPE: &str = "https://graph.microsoft.com/.default offline_access";
const DEVICE_AUTH_URL: &str = "https://login.microsoftonline.com/common/oauth2/v2.0/devicecode";
const TOKEN_URL: &str = "https://login.microsoftonline.com/common/oauth2/v2.0/token";

pub struct AuthManager {
    pub access_token: Option<String>,
    pub refresh_token: Option<String>,
    token_expires_at: Option<SystemTime>,
}

impl AuthManager {
    pub fn new() -> Self {
        Self {
            access_token: None,
            refresh_token: None,
            token_expires_at: None,
        }
    }
    
    /// Initiate Device Flow login (user sees code on screen)
    pub fn login(&mut self, device_code_callback: Option<&dyn Fn(&str, &str)>) -> Result<bool> {
        info!("Starting Device Flow login...");
        
        // Request device code from Microsoft
        let device_response = self.acquire_device_code()?;
        
        // Invoke callback if provided (for QML integration)
        if let Some(cb) = device_code_callback {
            cb(&device_response.user_code, &device_response.verification_uri);
        } else {
            // Print to terminal for CLI testing
            println!("\n{}", "=".repeat(70));
            println!("🔐 Device Login Required");
            println!("{}", "=".repeat(70));
            println!("1. Open this URL on any device (phone, tablet, another computer):");
            println!("   → {}", device_response.verification_uri);
            println!("2. Enter this code when prompted:");
            println!("   → {}", device_response.user_code);
            println!("\nWaiting for authentication...");
            println!("{}\n", "=".repeat(70));
        }
        
        // Poll for token
        match self.poll_for_token(&device_response)? {
            Some(_token_data) => {
                info!("Device Flow login successful");
                Ok(true)
            }
            None => {
                warn!("Device Flow login timed out or was denied");
                Ok(false)
            }
        }
    }
    
    /// Request device code from Microsoft
    fn acquire_device_code(&self) -> Result<DeviceFlowResponse> {
        debug!("Requesting device code from {}", DEVICE_AUTH_URL);
        
        let params = [
            ("client_id", PUBLIC_CLIENT_ID),
            ("scope", GRAPH_SCOPE),
        ];
        
        let resp = ureq::post(DEVICE_AUTH_URL)
            .send_form(&params)
            .map_err(|e| OmarchyError::HttpError(e.to_string()))?;
        
        if resp.status() < 200 || resp.status() >= 300 {
            return Err(OmarchyError::InvalidDeviceFlow(
                format!("Status {}: {}", resp.status(), resp.into_string().unwrap_or_default())
            ));
        }
        
        let device_response: DeviceFlowResponse = resp
            .into_json()
            .map_err(|e| OmarchyError::HttpError(e.to_string()))?;
        
        debug!("Device code received, expires in {} seconds", device_response.expires_in);
        
        // Log the actual device code for debugging
        info!("Device Code: {} | Verification URI: {}", device_response.user_code, device_response.verification_uri);
        
        Ok(device_response)
    }
    
    /// Poll Microsoft for token (blocks until success, timeout, or denial)
    fn poll_for_token(&mut self, device_response: &DeviceFlowResponse) -> Result<Option<()>> {
        let start_time = SystemTime::now();
        let expires_at = start_time + Duration::from_secs(device_response.expires_in as u64);
        let interval = Duration::from_secs((device_response.interval.max(5)) as u64);
        let mut poll_count = 0;
        
        // Give user 10 seconds to authenticate before we start polling
        // This prevents race condition where backend polls before user enters code
        debug!("Waiting 10 seconds for user to authenticate...");
        std::thread::sleep(Duration::from_secs(10));
        
        loop {
            if SystemTime::now() >= expires_at {
                warn!("Device code expired");
                return Err(OmarchyError::AuthError("Device code expired".to_string()));
            }
            
            std::thread::sleep(interval);
            poll_count += 1;
            
            let params = [
                ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
                ("client_id", PUBLIC_CLIENT_ID),
                ("device_code", &device_response.device_code),
            ];
            
            let resp = match ureq::post(TOKEN_URL).send_form(&params) {
                Ok(r) => r,
                Err(e) => {
                    eprintln!("🔍 DEBUG: Error debug: {:?}", e);
                    // Check if this is a Status error (400) which we can recover from
                    match e {
                        ureq::Error::Status(code, response) => {
                            eprintln!("🔴 HTTP {} from token endpoint (will handle below)", code);
                            response
                        }
                        ureq::Error::Transport(te) => {
                            eprintln!("❌ Transport error: {:?}", te);
                            return Err(OmarchyError::HttpError(format!("Transport error: {}", te)));
                        }
                    }
                }
            };
            
            match resp.status() {
                200 => {
                    let token_data: TokenResponse = resp
                        .into_json()
                        .map_err(|e| OmarchyError::HttpError(e.to_string()))?;
                    
                    info!("Device Flow complete (polled {} times)", poll_count);
                    self.cache_tokens(&token_data)?;
                    self.access_token = Some(token_data.access_token);
                    self.refresh_token = token_data.refresh_token;
                    self.token_expires_at = Some(SystemTime::now() + Duration::from_secs(token_data.expires_in as u64));
                    println!("✅ Authentication successful!\n");
                    return Ok(Some(()));
                }
                400 => {
                    let body_str = resp.into_string().unwrap_or_default();
                    eprintln!("🔴 HTTP 400 raw response: {}", body_str);
                    
                    match serde_json::from_str::<serde_json::Value>(&body_str) {
                        Ok(error_json) => {
                            debug!("🔍 Token polling received 400 error: {}", error_json);
                            
                            if let Some(error) = error_json.get("error").and_then(|v| v.as_str()) {
                                match error {
                                    "authorization_pending" => {
                                        // Still waiting; continue polling
                                        debug!("⏳ authorization_pending - continuing to poll");
                                        continue;
                                    }
                                    "expired_token" => {
                                        return Err(OmarchyError::AuthError("Device code expired".to_string()));
                                    }
                                    "access_denied" => {
                                        return Err(OmarchyError::AuthError("Authentication denied by user".to_string()));
                                    }
                                    _ => {
                                        debug!("❌ Unrecognized error: {}", error);
                                        return Err(OmarchyError::AuthError(format!("Auth failed: {}", error)));
                                    }
                                }
                            }
                        }
                        Err(json_err) => {
                            eprintln!("❌ Failed to parse JSON from 400 response: {}", json_err);
                            eprintln!("Raw body was: {}", body_str);
                            return Err(OmarchyError::HttpError(format!("HTTP 400 with unparseable JSON: {}", body_str)));
                        }
                    }
                }
                _ => {
                    return Err(OmarchyError::HttpError(
                        format!("Unexpected status {}: {}", resp.status(), resp.into_string().unwrap_or_default())
                    ));
                }
            }
        }
    }
    
    /// Get a valid access token (refresh if needed)
    pub fn get_token(&mut self) -> Result<String> {
        // Check if cached token is still valid
        if let Some(token) = &self.access_token {
            if let Some(expires) = self.token_expires_at {
                if SystemTime::now() < expires - Duration::from_secs(60) {
                    // Token still valid (with 60-second buffer)
                    return Ok(token.clone());
                }
            }
        }
        
        // Try to refresh from cache
        self.acquire_token_silent()?;
        
        match &self.access_token {
            Some(token) => Ok(token.clone()),
            None => Err(OmarchyError::TokenError("No valid token available".to_string())),
        }
    }
    
    /// Refresh token silently from cached refresh token
    fn acquire_token_silent(&mut self) -> Result<()> {
        // Try to get cached refresh token
        if let Some(cached_json) = keyring_mgr::get_cached_token()? {
            if let Ok(cached) = serde_json::from_str::<CachedToken>(&cached_json) {
                if let Some(refresh_token) = cached.refresh_token {
                    debug!("Attempting silent token refresh...");
                    
                    let params = [
                        ("grant_type", "refresh_token"),
                        ("client_id", PUBLIC_CLIENT_ID),
                        ("refresh_token", &refresh_token),
                        ("scope", GRAPH_SCOPE),
                    ];
                    
                    match ureq::post(TOKEN_URL).send_form(&params) {
                        Ok(resp) if resp.status() == 200 => {
                            if let Ok(token_data) = resp.into_json::<TokenResponse>() {
                                debug!("Token refreshed silently");
                                self.cache_tokens(&token_data)?;
                                self.access_token = Some(token_data.access_token);
                                self.refresh_token = token_data.refresh_token;
                                self.token_expires_at = Some(SystemTime::now() + Duration::from_secs(token_data.expires_in as u64));
                                return Ok(());
                            }
                        }
                        _ => {
                            warn!("Silent token refresh failed; clearing cache");
                            let _ = keyring_mgr::clear_cache();
                        }
                    }
                }
            }
        }
        
        Ok(())
    }
    
    /// Check if user is authenticated (has cached tokens)
    pub fn is_authenticated(&self) -> bool {
        // A valid access_token (or refresh_token for silent renewal) counts as authenticated
        if let Ok(Some(cached_json)) = keyring_mgr::get_cached_token() {
            if let Ok(cached) = serde_json::from_str::<CachedToken>(&cached_json) {
                return cached.refresh_token.is_some() || !cached.access_token.is_empty();
            }
        }
        false
    }
    
    /// Trigger device flow (can be called from external signal)
    pub fn trigger_device_flow(&mut self, config_dir: &std::path::Path) -> Result<bool> {
        info!("Device Flow triggered from Settings");
        
        // First logout any existing session
        let _ = self.logout();
        
        // Now start device flow
        self.start_device_flow_interactive(config_dir)
    }
    
    /// Logout and clear tokens
    pub fn logout(&mut self) -> Result<()> {
        info!("Logging out...");
        self.access_token = None;
        self.refresh_token = None;
        self.token_expires_at = None;
        keyring_mgr::clear_cache()?;
        info!("Logout successful");
        Ok(())
    }
    
    /// Write auth state to a JSON file for QML to read
    pub fn write_state_file(&self, config_dir: &std::path::Path) -> Result<()> {
        use std::fs;
        
        // Prefer in-memory token over keyring read — the background auth thread
        // has just written the token to keyring and set self.access_token.
        // Using is_authenticated() (which reads keyring) can race or fail silently.
        let authenticated = self.access_token.is_some() || self.is_authenticated();
        
        let state = serde_json::json!({
            "is_authenticated": authenticated,
            "has_access_token": self.access_token.is_some(),
            "token_expires_at": self.token_expires_at.and_then(|t| {
                t.duration_since(SystemTime::UNIX_EPOCH)
                    .ok()
                    .map(|d| d.as_secs())
            }),
        });
        
        let state_file = config_dir.join("auth_state.json");
        let json_str = serde_json::to_string_pretty(&state)
            .map_err(|e| OmarchyError::JsonError(e))?;
        
        fs::write(&state_file, json_str)
            .map_err(OmarchyError::from)?;
        
        debug!("Auth state written to {}", state_file.display());
        Ok(())
    }
    
    /// Write auth error to a JSON file for QML to display
    fn write_auth_error(&self, config_dir: &std::path::Path, error_msg: &str) -> Result<()> {
        use std::fs;
        
        let error_state = serde_json::json!({
            "is_authenticated": false,
            "error": error_msg,
        });
        
        let state_file = config_dir.join("auth_state.json");
        let json_str = serde_json::to_string_pretty(&error_state)
            .map_err(|e| OmarchyError::JsonError(e))?;
        
        fs::write(&state_file, json_str)
            .map_err(OmarchyError::from)?;
        
        warn!("Auth error written: {}", error_msg);
        Ok(())
    }

    /// Start device flow and write code to file for QML display (non-blocking)
    pub fn start_device_flow_interactive(&mut self, config_dir: &std::path::Path) -> Result<bool> {
        info!("Starting Device Flow login...");
        
        // Request device code from Microsoft
        let device_response = match self.acquire_device_code() {
            Ok(resp) => resp,
            Err(e) => {
                let err_msg = format!("Failed to get device code: {}", e);
                let _ = self.write_auth_error(config_dir, &err_msg);
                return Err(e);
            }
        };
        
        // Write device code to file for QML to read
        let device_code_file = config_dir.join("device_code.json");
        let device_code_data = serde_json::json!({
            "device_code": device_response.device_code,
            "user_code": device_response.user_code,
            "verification_uri": device_response.verification_uri,
            "expires_in": device_response.expires_in,
            "interval": device_response.interval,
        });
        
        let json_str = serde_json::to_string_pretty(&device_code_data)
            .map_err(|e| OmarchyError::JsonError(e))?;
        std::fs::write(&device_code_file, json_str).map_err(OmarchyError::from)?;
        
        info!("Device code written to {}", device_code_file.display());
        
        // Display to console for testing
        println!("\n{}", "=".repeat(70));
        println!("📱 Device Flow Authentication");
        println!("==================================");
        println!("User Code: {}", device_response.user_code);
        println!("Verification URL: {}", device_response.verification_uri);
        println!("Expires in: {} seconds", device_response.expires_in);
        println!("\n1. Open: {}", device_response.verification_uri);
        println!("2. Enter code: {}", device_response.user_code);
        println!("\nWaiting for authentication in background...");
        println!("{}\n", "=".repeat(70));
        
        // Spawn a background thread to poll for token (non-blocking)
        // This allows QML UI to remain responsive while polling happens
        let device_response_clone = device_response.clone();
        let config_dir_clone = config_dir.to_path_buf();
        
        std::thread::spawn(move || {
            let mut auth = AuthManager::default();
            match auth.poll_for_token(&device_response_clone) {
                Ok(Some(_)) => {
                    match auth.write_state_file(&config_dir_clone) {
                        Ok(()) => {
                            info!("✅ Background token polling succeeded - state file written");
                        }
                        Err(e) => {
                            warn!("Failed to write state file: {}", e);
                            let _ = auth.write_auth_error(&config_dir_clone, &format!("Token acquired but failed to write state: {}", e));
                        }
                    }
                }
                Ok(None) => {
                    let _ = auth.write_auth_error(&config_dir_clone, "Authentication failed or was cancelled");
                    warn!("Background token polling returned None");
                }
                Err(e) => {
                    let err_msg = format!("Background auth error: {}", e);
                    let _ = auth.write_auth_error(&config_dir_clone, &err_msg);
                    warn!("Background token polling failed: {}", e);
                }
            }
        });
        
        // Return immediately so QML can display code to user
        Ok(true)
    }
    
    /// Cache tokens to keyring
    fn cache_tokens(&self, token_data: &TokenResponse) -> Result<()> {
        let cached = CachedToken {
            access_token: token_data.access_token.clone(),
            refresh_token: token_data.refresh_token.clone(),
        };
        
        let json = serde_json::to_string(&cached)
            .map_err(|e| OmarchyError::JsonError(e))?;
        
        keyring_mgr::cache_token(&json)?;
        debug!("Tokens cached to keyring");
        Ok(())
    }
}

impl Default for AuthManager {
    fn default() -> Self {
        Self::new()
    }
}
