//! Main application entry point (Rust + QML)
//!
//! OmarchyLook: Lightweight Outlook clone
//! - Rust backend: Auth, Graph API, SQLite cache
//! - QML frontend: Native Qt UI with hot-reload support

use omarchy_look::{init_logging, AuthManager, Database, SettingsManager};
use log::{debug, error, info, warn};
use std::env;
use std::path::PathBuf;
use std::io::{Read, Write};
use std::net::TcpListener;

fn main() {
    // Initialize logging
    init_logging();
    info!("OmarchyLook starting");
    
    // Get configuration paths
    let config_dir = get_config_dir();
    let db_path = config_dir.join("omarchy.db");
    let settings_path = config_dir.join("settings.toml");
    
    info!("Config dir: {}", config_dir.display());
    info!("Database: {}", db_path.display());
    
    // Initialize core backend components
    match initialize_app(&config_dir, db_path.to_str().unwrap(), settings_path.to_str().unwrap()) {
        Ok(_) => {
            info!("Application backend initialized successfully");
            
            // Launch Qt/QML runtime
            launch_qml_app(&config_dir);
        }
        Err(e) => {
            error!("Failed to initialize application: {}", e);
            std::process::exit(1);
        }
    }
}

fn get_config_dir() -> PathBuf {
    // Use XDG standard: ~/.config/omarchy-look
    if let Ok(xdg_config) = env::var("XDG_CONFIG_HOME") {
        PathBuf::from(xdg_config).join("omarchy-look")
    } else if let Ok(home) = env::var("HOME") {
        PathBuf::from(home).join(".config").join("omarchy-look")
    } else {
        PathBuf::from("/tmp/omarchy-look")
    }
}

/// Launch the QML application window
fn launch_qml_app(config_dir: &PathBuf) {
    use std::process::{Command, Stdio};
    
    info!("Launching Qt/QML runtime...");
    
    // Determine QML directory: prefer QML_DIR env var, then fall back to project root
    let qml_dir = if let Ok(qml_env) = env::var("QML_DIR") {
        PathBuf::from(qml_env)
    } else {
        // Fallback: look for qml/ in the project root (parent of src/ or current directory)
        PathBuf::from("qml")
    };
    
    info!("QML directory: {}", qml_dir.display());
    
    // Check if main.qml exists
    let main_qml = qml_dir.join("main.qml");
    if !main_qml.exists() {
        eprintln!("❌ QML file not found: {}", main_qml.display());
        eprintln!("   Create qml/main.qml before running");
        std::process::exit(1);
    }
    
    // Write a qml-config.json file so QML can read the config directory path
    let qml_config_file = config_dir.join("qml-config.json");
    let qml_config = format!(r#"{{"configDir":"{}"}}"#, config_dir.display());
    if let Err(e) = std::fs::write(&qml_config_file, &qml_config) {
        warn!("Failed to write QML config file: {}", e);
    } else {
        debug!("QML config written to: {}", qml_config_file.display());
    }
    
    // Launch qml command (modern Qt 6.11+ tool, replaces deprecated qmlscene)
    // The /usr/lib/qt6/bin/qml command is the modern replacement for qmlscene.
    // It is the officially supported way to run QML applications in Qt 6.
    // Future versions of Qt will continue to support this tool.
    let qml_binary = "/usr/lib/qt6/bin/qml";
    
    let mut cmd = Command::new(qml_binary);
    cmd.arg(main_qml.to_str().unwrap())
        .env("QML_DIR", &qml_dir)
        .env("CONFIG_DIR", config_dir.to_str().unwrap())
        .env("RUST_LOG", "omarchy_look=debug,info")
        .env("QML_XHR_ALLOW_FILE_READ", "1") // Allow local file reads in QML
        .env("XDG_RUNTIME_DIR", env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/run/user/1000".to_string()))
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    
    debug!("Launching QML with CONFIG_DIR={}", config_dir.display());
    debug!("Launching QML with QML_XHR_ALLOW_FILE_READ=1");
    
    // Attempt to launch qml
    match cmd.status() {
        Ok(status) => {
            if !status.success() {
                eprintln!("⚠️  QML process exited with status: {}", status);
            }
            info!("Qt/QML window closed");
        }
        Err(e) => {
            eprintln!("❌ Failed to launch Qt/QML: {}", e);
            eprintln!("   Ensure Qt 6 is installed: sudo apt install qt6-qml qt6-declarative");
            std::process::exit(1);
        }
    }
}

fn initialize_app(config_dir: &PathBuf, db_path: &str, settings_path: &str) -> omarchy_look::errors::Result<()> {
    // Initialize database
    let _db = Database::open(db_path)?;
    info!("Database initialized");
    
    // Initialize settings
    let _settings = SettingsManager::open(settings_path)?;
    info!("Settings initialized");
    
    // Initialize auth (check if already authenticated, but don't auto-prompt)
    let auth = AuthManager::new();
    if auth.is_authenticated() {
        info!("User already authenticated (cached tokens available)");
        auth.write_state_file(config_dir)?;
    } else {
        info!("User not authenticated; waiting for UI trigger");
    }
    
    // Start background thread to watch for device flow trigger file
    let config_dir_clone = config_dir.clone();
    std::thread::spawn(move || {
        watch_for_device_flow_trigger(&config_dir_clone);
    });

    // Start HTTP trigger server (QML posts to this to trigger auth/logout)
    let config_dir_http = config_dir.clone();
    std::thread::spawn(move || {
        start_http_trigger_server(&config_dir_http);
    });
    
    Ok(())
}

/// Watch for device flow and logout trigger files
fn watch_for_device_flow_trigger(config_dir: &PathBuf) {
    use std::fs;
    use std::thread;
    use std::time::Duration;
    
    let trigger_file = "/tmp/omarchylook-trigger-device-flow";
    let logout_trigger_file = "/tmp/omarchylook-trigger-logout";
    
    loop {
        thread::sleep(Duration::from_millis(500));
        
        // Check login trigger
        if fs::metadata(trigger_file).is_ok() {
            info!("🔔 Device Flow trigger file detected - starting device flow");
            let _ = fs::remove_file(trigger_file);
            
            let mut auth = AuthManager::new();
            info!("📱 Calling trigger_device_flow with config_dir: {}", config_dir.display());
            match auth.trigger_device_flow(config_dir) {
                Ok(true) => info!("✅ Device Flow triggered successfully"),
                Ok(false) => info!("❌ Device Flow cancelled by user"),
                Err(e) => error!("❌ Device Flow failed: {}", e),
            }
        }
        
        // Check logout trigger
        if fs::metadata(logout_trigger_file).is_ok() {
            info!("🔔 Logout trigger file detected - logging out");
            let _ = fs::remove_file(logout_trigger_file);
            
            let mut auth = AuthManager::new();
            match auth.logout() {
                Ok(()) => {
                    info!("✅ Logout successful");
                    // Write cleared auth state for QML to pick up
                    let _ = auth.write_state_file(config_dir);
                }
                Err(e) => error!("❌ Logout failed: {}", e),
            }
        }
    }
}

/// Minimal HTTP trigger server — listens on localhost:27182
/// QML uses XMLHttpRequest to POST to this endpoint to trigger auth/logout.
/// This avoids the limitation of QML not being able to write files directly.
///
/// Endpoints:
///   POST /auth/login   → triggers device flow
///   POST /auth/logout  → triggers logout
fn start_http_trigger_server(config_dir: &PathBuf) {
    eprintln!("[HTTP] Attempting to bind 127.0.0.1:27182");
    let listener = match TcpListener::bind("127.0.0.1:27182") {
        Ok(l) => {
            eprintln!("[HTTP] ✅ Bound OK");
            info!("🌐 HTTP trigger server listening on http://127.0.0.1:27182");
            l
        }
        Err(e) => {
            eprintln!("[HTTP] ❌ BIND FAILED: {}", e);
            warn!("HTTP trigger server failed to bind: {} (falling back to file triggers)", e);
            return;
        }
    };

    for stream in listener.incoming() {
        match stream {
            Ok(mut stream) => {
                let mut buf = [0u8; 512];
                let n = stream.read(&mut buf).unwrap_or(0);
                let request = String::from_utf8_lossy(&buf[..n]);
                let first_line = request.lines().next().unwrap_or("");

                let (status, action) = if first_line.contains("POST /auth/login") {
                    ("200 OK", "login")
                } else if first_line.contains("POST /auth/logout") {
                    ("200 OK", "logout")
                } else {
                    ("404 Not Found", "")
                };

                // Always respond with CORS headers so QML XHR doesn't block
                let response = format!(
                    "HTTP/1.1 {}\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\nok",
                    status
                );
                let _ = stream.write_all(response.as_bytes());
                drop(stream);

                match action {
                    "login" => {
                        info!("🔔 HTTP trigger: device flow login requested");
                        let config_dir = config_dir.clone();
                        std::thread::spawn(move || {
                            let mut auth = AuthManager::new();
                            match auth.trigger_device_flow(&config_dir) {
                                Ok(true) => info!("✅ HTTP-triggered device flow succeeded"),
                                Ok(false) => info!("❌ HTTP-triggered device flow cancelled"),
                                Err(e) => error!("❌ HTTP-triggered device flow failed: {}", e),
                            }
                        });
                    }
                    "logout" => {
                        info!("🔔 HTTP trigger: logout requested");
                        let mut auth = AuthManager::new();
                        match auth.logout() {
                            Ok(()) => {
                                info!("✅ HTTP-triggered logout succeeded");
                                let _ = auth.write_state_file(config_dir);
                            }
                            Err(e) => error!("❌ HTTP-triggered logout failed: {}", e),
                        }
                    }
                    _ => {}
                }
            }
            Err(e) => warn!("HTTP trigger server accept error: {}", e),
        }
    }
}
