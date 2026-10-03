//! Main application entry point (Rust + QML)
//!
//! OmarchyLook: Lightweight Outlook clone
//! - Rust backend: Auth, Graph API, SQLite cache
//! - QML frontend: Native Qt UI with hot-reload support

use omarchylook::{init_logging, AuthManager, Database, SettingsManager, email_daemon::{EmailDaemon, DaemonConfig}, providers::graph::GraphEmailProvider};
use log::{debug, error, info, warn};
use std::env;
use std::path::PathBuf;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::Arc;
use tokio::runtime::Runtime;

/// Process-wide sync scheduler (one mail + one calendar thread per signed-in account).
static SCHEDULER: std::sync::OnceLock<Arc<omarchylook::scheduler::SyncScheduler>> = std::sync::OnceLock::new();

/// Value of `?key=` in a request line (percent-decoded).
fn query_param(first_line: &str, key: &str) -> Option<String> {
    let needle = format!("{}=", key);
    first_line.split_once('?').and_then(|(_, q)| {
        q.split(|c| c == ' ' || c == '\r' || c == '\n').next().and_then(|q| {
            q.split('&').find_map(|kv| kv.strip_prefix(needle.as_str()).map(url_decode))
        })
    }).filter(|v| !v.is_empty())
}

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

/// Directory holding the Omarchy shell UI kit (`Commons/`, `Ui/`).
const OMARCHY_KIT_DIR: &str = "/usr/share/omarchy/shell";

/// Locate the QML app directory: `QML_DIR` env, then `./qml`, then the
/// `qml/` next to the sources this binary was built from (so it also works
/// when launched from the app menu with an arbitrary cwd).
fn resolve_qml_dir() -> PathBuf {
    if let Ok(dir) = env::var("QML_DIR") {
        return PathBuf::from(dir);
    }
    let cwd_qml = PathBuf::from("qml");
    if cwd_qml.join("shell.qml").exists() {
        return cwd_qml;
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("qml")
}

/// The UI is built on the Omarchy shell kit (`qs.Commons`, `qs.Ui`). Quickshell
/// resolves `qs.*` relative to the config root, so link the installed kit into
/// the QML dir (idempotent; the links are git-ignored).
fn ensure_omarchy_kit(qml_dir: &PathBuf) -> std::io::Result<()> {
    use std::os::unix::fs::symlink;
    for name in ["Commons", "Ui"] {
        let target = PathBuf::from(OMARCHY_KIT_DIR).join(name);
        if !target.exists() {
            return Err(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                format!("{} not found - OmarchyLook needs the Omarchy shell UI kit", target.display()),
            ));
        }
        let link = qml_dir.join(name);
        if link.symlink_metadata().is_err() {
            symlink(&target, &link)?;
            debug!("Linked {} -> {}", link.display(), target.display());
        }
    }
    Ok(())
}

/// Launch the QML application window (Quickshell used as a standalone Qt Quick host).
fn launch_qml_app(config_dir: &PathBuf) {
    use std::process::{Command, Stdio};

    info!("Launching Quickshell UI...");

    let qml_dir = resolve_qml_dir();
    info!("QML directory: {}", qml_dir.display());

    let shell_qml = qml_dir.join("shell.qml");
    if !shell_qml.exists() {
        eprintln!("❌ QML entry point not found: {}", shell_qml.display());
        std::process::exit(1);
    }

    if let Err(e) = ensure_omarchy_kit(&qml_dir) {
        eprintln!("❌ {}", e);
        eprintln!("   Install/upgrade Omarchy (pacman -Q omarchy) so {} exists", OMARCHY_KIT_DIR);
        std::process::exit(1);
    }

    // `quickshell -p <dir>` runs <dir>/shell.qml as its own instance, independent
    // of the running omarchy-shell. CONFIG_DIR tells the UI where the backend
    // writes auth_state.json / device_code.json.
    let mut cmd = Command::new("quickshell");
    cmd.arg("-p").arg(&qml_dir)
        .env("QML_DIR", &qml_dir)
        .env("CONFIG_DIR", config_dir.to_str().unwrap())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());

    match cmd.status() {
        Ok(status) => {
            if !status.success() {
                eprintln!("⚠️  Quickshell exited with status: {}", status);
            }
            info!("UI window closed");
        }
        Err(e) => {
            eprintln!("❌ Failed to launch quickshell: {}", e);
            eprintln!("   Install it with: pacman -S quickshell");
            std::process::exit(1);
        }
    }
}

fn initialize_app(config_dir: &PathBuf, db_path: &str, settings_path: &str) -> omarchylook::errors::Result<()> {
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
    
    // Per-account sync (mail + calendar threads for every signed-in account)
    let scheduler = Arc::new(omarchylook::scheduler::SyncScheduler::new(config_dir));
    let _ = SCHEDULER.set(Arc::clone(&scheduler));
    std::thread::spawn(move || scheduler.start_all());
    
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
        
        // Legacy trigger files go through the same account code as the HTTP routes, so a
        // login creates a normal <provider>-<suffix> account and starts its sync.
        // login:  file content = provider (default "exchange")
        // logout: file content = account id (empty = sign out every account)
        if fs::metadata(trigger_file).is_ok() {
            let provider = fs::read_to_string(trigger_file).unwrap_or_default().trim().to_string();
            let provider = if provider.is_empty() { "exchange".to_string() } else { provider };
            let _ = fs::remove_file(trigger_file);
            info!("🔔 Trigger file: add {} account", provider);
            match SCHEDULER.get() {
                Some(scheduler) => {
                    if let Err(e) = omarchylook::account_ops::begin_add_account(config_dir, &provider, Arc::clone(scheduler)) {
                        error!("❌ Add account failed: {}", e);
                    }
                }
                None => warn!("Trigger file ignored: scheduler not ready yet"),
            }
        }

        if fs::metadata(logout_trigger_file).is_ok() {
            let id = fs::read_to_string(logout_trigger_file).unwrap_or_default().trim().to_string();
            let _ = fs::remove_file(logout_trigger_file);
            info!("🔔 Trigger file: log out {}", if id.is_empty() { "all accounts" } else { &id });
            match SCHEDULER.get() {
                Some(scheduler) => {
                    let result = if id.is_empty() {
                        omarchylook::account_ops::sign_out_all(config_dir, scheduler).map(|n| info!("✅ Signed out {} account(s)", n))
                    } else {
                        omarchylook::account_ops::sign_out_account(config_dir, &id, scheduler)
                    };
                    if let Err(e) = result {
                        error!("❌ Logout failed: {}", e);
                    }
                }
                None => warn!("Trigger file ignored: scheduler not ready yet"),
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

                // ── GET /accounts — configured accounts and whether each is signed in ──
                if first_line.contains("GET /accounts") {
                    let body = omarchylook::account_ops::accounts_json(config_dir);
                    let response = format!(
                        "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                        body.len(), body
                    );
                    let _ = stream.write_all(response.as_bytes());
                    continue;
                }

                // ── GET /contacts?view=all|favorites|lists&sort=first|last|company|recent ──
                if first_line.contains("GET /contacts") {
                    let view = query_param(first_line, "view").unwrap_or_else(|| "all".to_string());
                    let sort = query_param(first_line, "sort").unwrap_or_else(|| "first".to_string());
                    let body = match Database::open(config_dir.join("messages.db").to_str().unwrap_or("messages.db")) {
                        Ok(db) => match db.query_contacts(&view, &sort) {
                            Ok(rows) => serde_json::to_string(&rows).unwrap_or_else(|_| "[]".to_string()),
                            Err(e) => {
                                warn!("GET /contacts: query failed: {}", e);
                                "[]".to_string()
                            }
                        },
                        Err(e) => {
                            warn!("GET /contacts: DB open failed: {}", e);
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

                // ── POST /contacts/favorite?id=ID&value=true|false — local favorite flag ──
                if first_line.contains("POST /contacts/favorite") {
                    let id = query_param(first_line, "id").unwrap_or_default();
                    let value = query_param(first_line, "value").as_deref() == Some("true");
                    let ok = Database::open(config_dir.join("messages.db").to_str().unwrap_or("messages.db"))
                        .and_then(|db| db.set_contact_favorite(&id, value))
                        .is_ok();
                    let body = if ok { "ok" } else { "error" };
                    let response = format!(
                        "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                        body.len(), body
                    );
                    let _ = stream.write_all(response.as_bytes());
                    continue;
                }

                // ── POST /auth/confirm?pending=ID&decision=replace|cancel — answer the
                // "this mailbox is already signed in — replace its sign-in?" prompt ──
                if first_line.contains("POST /auth/confirm") {
                    let pending_id = query_param(first_line, "pending").unwrap_or_default();
                    let replace = query_param(first_line, "decision").as_deref() == Some("replace");
                    let ok = SCHEDULER
                        .get()
                        .map(|sch| omarchylook::account_ops::resolve_reauth(config_dir, &pending_id, replace, sch))
                        .map(|r| r.map_err(|e| error!("❌ re-authentication answer failed: {}", e)).is_ok())
                        .unwrap_or(false);
                    let body = if ok { "ok" } else { "error" };
                    let response = format!(
                        "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                        body.len(), body
                    );
                    let _ = stream.write_all(response.as_bytes());
                    continue;
                }

                // ── POST /accounts/login?account=ID — log in an existing account ──
                // Reuses the kept token when there is one; otherwise tells the UI to run a device flow.
                if first_line.contains("POST /accounts/login") {
                    let id = query_param(first_line, "account").unwrap_or_default();
                    let body = match SCHEDULER.get() {
                        Some(scheduler) => match omarchylook::account_ops::log_in_existing(config_dir, &id, scheduler) {
                            Ok(omarchylook::account_ops::ResumeOutcome::Resumed) => "{\"result\":\"resumed\"}".to_string(),
                            Ok(omarchylook::account_ops::ResumeOutcome::LoginRequired(provider)) => {
                                serde_json::json!({ "result": "login_required", "provider": provider }).to_string()
                            }
                            Err(e) => {
                                error!("❌ log in {} failed: {}", id, e);
                                "{\"result\":\"error\"}".to_string()
                            }
                        },
                        None => "{\"result\":\"error\"}".to_string(),
                    };
                    let response = format!(
                        "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                        body.len(), body
                    );
                    let _ = stream.write_all(response.as_bytes());
                    continue;
                }

                // ── GET /calendar/events?month=YYYY-MM — cached calendar events ──
                if first_line.contains("GET /calendar/events") {
                    let month: String = first_line
                        .split_once("month=")
                        .map(|(_, rest)| {
                            rest.split(|c| c == ' ' || c == '&' || c == '\r' || c == '\n')
                                .next()
                                .unwrap_or("")
                                .to_string()
                        })
                        .unwrap_or_default();

                    let body = match Database::open(config_dir.join("messages.db").to_str().unwrap_or("messages.db")) {
                        Ok(db) => match db.get_events_for_month(&month) {
                            Ok(events) => serde_json::to_string(
                                &events.iter().map(|e| serde_json::json!({
                                    "id": e.id,
                                    "subject": e.subject,
                                    "body": e.body,
                                    "start": e.start,
                                    "end": e.end,
                                    "is_all_day": e.is_all_day,
                                    "time_zone": e.time_zone,
                                })).collect::<Vec<_>>()
                            ).unwrap_or_else(|_| "[]".to_string()),
                            Err(e) => {
                                warn!("GET /calendar/events: query failed: {}", e);
                                "[]".to_string()
                            }
                        },
                        Err(e) => {
                            warn!("GET /calendar/events: DB open failed: {}", e);
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
                        .and_then(|s| toml::from_str::<omarchylook::models::Settings>(&s).ok())
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

                // ── GET|POST /settings/calendar — recurring-meeting window (years back / ahead) ──
                if first_line.contains("GET /settings/calendar") || first_line.contains("POST /settings/calendar") {
                    use omarchylook::models::CalendarSettings;
                    let settings_path = config_dir.join("settings.toml");
                    let current = if first_line.contains("POST /settings/calendar") {
                        let cur = omarchylook::settings::read_calendar_settings(&settings_path);
                        let wanted = CalendarSettings {
                            recurrence_years_back: query_param(first_line, "back").and_then(|v| v.parse().ok()).unwrap_or(cur.recurrence_years_back),
                            recurrence_years_ahead: query_param(first_line, "ahead").and_then(|v| v.parse().ok()).unwrap_or(cur.recurrence_years_ahead),
                        };
                        match omarchylook::settings::write_calendar_settings(&settings_path, &wanted) {
                            Ok(stored) => stored,
                            Err(e) => {
                                warn!("POST /settings/calendar: could not save: {}", e);
                                cur
                            }
                        }
                    } else {
                        omarchylook::settings::read_calendar_settings(&settings_path)
                    };
                    let body = serde_json::json!({
                        "recurrence_years_back": current.recurrence_years_back,
                        "recurrence_years_ahead": current.recurrence_years_ahead,
                        "max_years_back": CalendarSettings::MAX_YEARS_BACK,
                        "max_years_ahead": CalendarSettings::MAX_YEARS_AHEAD,
                    }).to_string();
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
                        .and_then(|s| toml::from_str::<omarchylook::models::Settings>(&s).ok())
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
                } else if first_line.contains("POST /accounts/remove") {
                    "remove"
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
                        // New account: its id is generated as <provider>-<suffix>
                        let provider = query_param(first_line, "provider").unwrap_or_else(|| "exchange".to_string());
                        info!("🔔 HTTP trigger: add {} account requested", provider);
                        if let Some(scheduler) = SCHEDULER.get() {
                            let (config_dir, scheduler) = (config_dir.clone(), Arc::clone(scheduler));
                            std::thread::spawn(move || {
                                if let Err(e) = omarchylook::account_ops::begin_add_account(&config_dir, &provider, scheduler) {
                                    error!("❌ Add account failed: {}", e);
                                }
                            });
                        }
                    }
                    "logout" | "remove" => {
                        let id = query_param(first_line, "account")
                            .unwrap_or_else(|| omarchylook::token_store::DEFAULT_ACCOUNT.to_string());
                        info!("🔔 HTTP trigger: {} account {}", action, id);
                        if let Some(scheduler) = SCHEDULER.get() {
                            let result = if action == "remove" {
                                omarchylook::account_ops::remove_account(config_dir, &id, scheduler)
                            } else {
                                omarchylook::account_ops::sign_out_account(config_dir, &id, scheduler)
                            };
                            match result {
                                Ok(()) => info!("✅ {} succeeded for {}", action, id),
                                Err(e) => error!("❌ {} failed for {}: {}", action, id, e),
                            }
                        }
                    }
                    _ => {}
                }
            }
            Err(e) => warn!("HTTP trigger server accept error: {}", e),
        }
    }
}
