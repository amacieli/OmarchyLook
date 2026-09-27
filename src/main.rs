//! Main application entry point (Rust + QML)
//!
//! OmarchyLook: Lightweight Outlook clone
//! - Rust backend: Auth, Graph API, SQLite cache
//! - QML frontend: Native Qt UI with hot-reload support

use omarchy_look::{init_logging, AuthManager, Database, SettingsManager, email_daemon::{EmailDaemon, DaemonConfig}, providers::graph::GraphEmailProvider};
use log::{debug, error, info, warn};
use std::env;
use std::path::PathBuf;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::Arc;
use tokio::runtime::Runtime;

/// Percent-decode a URL query parameter value (e.g. %3D → =, %2F → /)
fn url_decode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(hex) = std::str::from_utf8(&bytes[i+1..i+3]) {
                if let Ok(byte) = u8::from_str_radix(hex, 16) {
                    out.push(byte as char);
                    i += 3;
                    continue;
                }
            }
        } else if bytes[i] == b'+' {
            out.push(' ');
            i += 1;
            continue;
        }
        out.push(bytes[i] as char);
        i += 1;
    }
    out
}

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
    // Use XDG standard: ~/.config/omarchylook
    if let Ok(xdg_config) = env::var("XDG_CONFIG_HOME") {
        PathBuf::from(xdg_config).join("omarchylook")
    } else if let Ok(home) = env::var("HOME") {
        PathBuf::from(home).join(".config").join("omarchylook")
    } else {
        PathBuf::from("/tmp/omarchylook")
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
    let db = Arc::new(Database::open(db_path)?);
    info!("Database initialized");
    
    // Initialize settings
    let _settings = SettingsManager::open(settings_path)?;
    info!("Settings initialized");
    
    // Initialize auth (check if already authenticated, but don't auto-prompt)
    let auth = AuthManager::new();
    if auth.is_authenticated() {
        info!("User already authenticated (cached tokens available)");
        auth.write_state_file(config_dir)?;
        
        // Note: Email daemon will start in the background thread below
        // It will self-trigger on token availability
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
    
    // Start email daemon in a separate thread with tokio runtime
    let config_dir_daemon = config_dir.clone();
    std::thread::spawn(move || {
        start_email_daemon_thread(&config_dir_daemon);
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
                let mut buf = [0u8; 1024];
                let n = stream.read(&mut buf).unwrap_or(0);
                let request = String::from_utf8_lossy(&buf[..n]);
                let first_line = request.lines().next().unwrap_or("");

                // ── GET /folders — return cached folder list as JSON ──────────────
                if first_line.contains("GET /folders") {
                    let db_path = config_dir.join("messages.db");
                    let body = match rusqlite::Connection::open(&db_path) {
                        Ok(conn) => {
                            let mut stmt = conn.prepare(
                                "SELECT id, display_name, unread_item_count, well_known_name \
                                 FROM folders ORDER BY sort_order ASC, display_name ASC"
                            ).unwrap();
                            let rows: Vec<String> = stmt.query_map([], |row| {
                                let id: String = row.get(0)?;
                                let display_name: String = row.get(1)?;
                                let unread: i32 = row.get::<_, Option<i32>>(2)?.unwrap_or(0);
                                let well_known: String = row.get::<_, Option<String>>(3)?.unwrap_or_default();
                                Ok(format!(
                                    "{{\"id\":{},\"display_name\":{},\"unread_item_count\":{},\"well_known_name\":{}}}",
                                    serde_json::to_string(&id).unwrap(),
                                    serde_json::to_string(&display_name).unwrap(),
                                    unread,
                                    serde_json::to_string(&well_known).unwrap(),
                                ))
                            }).unwrap()
                            .filter_map(|r| r.ok())
                            .collect();
                            format!("[{}]", rows.join(","))
                        }
                        Err(e) => {
                            warn!("GET /folders: DB open failed: {}", e);
                            "[]".to_string()
                        }
                    };
                    let response = format!(
                        "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                        body.len(), body
                    );
                    let _ = stream.write_all(response.as_bytes());
                    continue;
                }

                // ── GET /messages — return messages as JSON (optional ?folder_id=) ──────────────
                if first_line.contains("GET /messages") {
                    // Parse optional ?folder_id= query parameter
                    let folder_id: Option<String> = first_line
                        .split_once("folder_id=")
                        .map(|(_, rest)| {
                            let raw = rest.split(|c| c == ' ' || c == '&' || c == '\r' || c == '\n')
                                .next()
                                .unwrap_or("");
                            // URL-decode: folder IDs contain = and / which QML encodeURIComponent encodes
                            url_decode(raw)
                        })
                        .filter(|s| !s.is_empty());

                    let db_path = config_dir.join("messages.db");
                    let body = match rusqlite::Connection::open(&db_path) {
                        Ok(conn) => {
                            let map_row = |row: &rusqlite::Row| {
                                let id: String = row.get(0)?;
                                let subject: String = row.get(1)?;
                                let from_email: String = row.get(2)?;
                                let from_name: String = row.get::<_, Option<String>>(3)?.unwrap_or_default();
                                let received_at: String = row.get(4)?;
                                let is_read: bool = row.get(5)?;
                                Ok(format!(
                                    "{{\"id\":{},\"subject\":{},\"from_email\":{},\"from_name\":{},\"received_at\":{},\"is_read\":{}}}",
                                    serde_json::to_string(&id).unwrap(),
                                    serde_json::to_string(&subject).unwrap(),
                                    serde_json::to_string(&from_email).unwrap(),
                                    serde_json::to_string(&from_name).unwrap(),
                                    serde_json::to_string(&received_at).unwrap(),
                                    is_read
                                ))
                            };

                            let rows: Vec<String> = if let Some(ref fid) = folder_id {
                                // Try folder-filtered first; fall back to unfiltered if nothing found
                                // (covers existing messages whose folder_id was not yet backfilled)
                                let mut stmt = conn.prepare(
                                    "SELECT id, subject, from_email, from_name, received_at, is_read \
                                     FROM messages WHERE folder_id = ?1 ORDER BY received_at DESC LIMIT 50"
                                ).unwrap();
                                let filtered: Vec<String> = stmt
                                    .query_map([fid.as_str()], map_row)
                                    .unwrap()
                                    .filter_map(|r| r.ok())
                                    .collect();

                                if filtered.is_empty() {
                                    // No folder_id matches — show all (pre-backfill state)
                                    let mut stmt2 = conn.prepare(
                                        "SELECT id, subject, from_email, from_name, received_at, is_read \
                                         FROM messages ORDER BY received_at DESC LIMIT 50"
                                    ).unwrap();
                                    stmt2.query_map([], map_row)
                                        .unwrap()
                                        .filter_map(|r| r.ok())
                                        .collect()
                                } else {
                                    filtered
                                }
                            } else {
                                let mut stmt = conn.prepare(
                                    "SELECT id, subject, from_email, from_name, received_at, is_read \
                                     FROM messages ORDER BY received_at DESC LIMIT 50"
                                ).unwrap();
                                stmt.query_map([], map_row)
                                    .unwrap()
                                    .filter_map(|r| r.ok())
                                    .collect()
                            };
                            format!("[{}]", rows.join(","))
                        }
                        Err(e) => {
                            warn!("GET /messages: DB open failed: {}", e);
                            "[]".to_string()
                        }
                    };
                    let response = format!(
                        "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                        body.len(), body
                    );
                    let _ = stream.write_all(response.as_bytes());
                    continue;
                }

                // ── GET /settings/ui — return UI settings as JSON ─────────────
                if first_line.contains("GET /settings/ui") {
                    let settings_path = config_dir.join("settings.toml");
                    let body = match std::fs::read_to_string(&settings_path)
                        .ok()
                        .and_then(|s| toml::from_str::<omarchy_look::models::Settings>(&s).ok())
                    {
                        Some(settings) => format!(
                            "{{\"sidebar_expanded\":{},\"window_width\":{},\"window_height\":{}}}",
                            settings.ui.sidebar_expanded,
                            settings.ui.window_width,
                            settings.ui.window_height,
                        ),
                        None => "{\"sidebar_expanded\":true,\"window_width\":1280,\"window_height\":800}".to_string(),
                    };
                    let response = format!(
                        "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                        body.len(), body
                    );
                    let _ = stream.write_all(response.as_bytes());
                    continue;
                }

                // ── POST /settings/sidebar_expanded — persist sidebar state ────
                if first_line.contains("POST /settings/sidebar_expanded") {
                    // Body is "true" or "false" — read remaining request bytes
                    let body_start = request.find("\r\n\r\n").map(|i| i + 4).unwrap_or(0);
                    let body_str = request[body_start..].trim();
                    let expanded = body_str == "true";

                    let settings_path = config_dir.join("settings.toml");
                    let result = std::fs::read_to_string(&settings_path)
                        .ok()
                        .and_then(|s| toml::from_str::<omarchy_look::models::Settings>(&s).ok())
                        .map(|mut settings| {
                            settings.ui.sidebar_expanded = expanded;
                            toml::to_string_pretty(&settings)
                                .ok()
                                .map(|content| std::fs::write(&settings_path, content))
                        });
                    let ok = result.is_some();
                    debug!("POST /settings/sidebar_expanded {} → {}", expanded, ok);

                    let response = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\nok";
                    let _ = stream.write_all(response.as_bytes());
                    continue;
                }

                // ── POST trigger routes ────────────────────────────────────
                let action = if first_line.contains("POST /auth/login") {
                    "login"
                } else if first_line.contains("POST /auth/logout") {
                    "logout"
                } else {
                    ""
                };

                let status = if action.is_empty() { "404 Not Found" } else { "200 OK" };

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
                            // Clear any stale error from auth_state.json immediately
                            // so QML poller doesn't keep displaying the old error
                            let _ = std::fs::write(
                                config_dir.join("auth_state.json"),
                                "{\"is_authenticated\":false}",
                            );
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

/// Start the email daemon with its own tokio runtime
/// This runs in a separate thread and continuously syncs emails
fn start_email_daemon_thread(config_dir: &PathBuf) {
    let config_dir_clone = config_dir.clone();
    
    // Create a new tokio runtime for this thread
    let rt = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build() {
        Ok(r) => r,
        Err(e) => {
            error!("Failed to create tokio runtime for email daemon: {}", e);
            return;
        }
    };
    
    info!("Email daemon thread starting...");
    
    // Run the daemon in the tokio context
    rt.block_on(async {
        // Create the email provider (Graph API)
        let auth = AuthManager::new();
        let provider = Arc::new(omarchy_look::providers::graph::GraphEmailProvider::new(auth));
        
        // Open database (will be accessed synchronously from blocking context)
        let db_path = config_dir_clone.join("messages.db");
        let db_str = db_path.to_str().unwrap_or("messages.db").to_string();
        let daemon_db = match Database::open(&db_str) {
            Ok(db) => Arc::new(db),
            Err(e) => {
                error!("Failed to open database for email daemon: {}", e);
                return;
            }
        };
        
        // Create the daemon with config
        let daemon_config = DaemonConfig {
            poll_interval_secs: 120,
            folder_sync_interval_secs: 600,
            max_retries: 10,
        };
        let daemon = EmailDaemon::new(daemon_config, daemon_db, provider);
        
        // Run the daemon (this will loop indefinitely)
        daemon.start().await;
    });
}
