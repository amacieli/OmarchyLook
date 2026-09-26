//! Main application entry point (Rust + QML)
//!
//! OmarchyLook: Lightweight Outlook clone
//! - Rust backend: Auth, Graph API, SQLite cache
//! - QML frontend: Native Qt UI with hot-reload support

use omarchy_look::{init_logging, AuthManager, Database, SettingsManager};
use log::{info, error};
use std::env;
use std::path::PathBuf;

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
    
    // Initialize core components
    match initialize_app(&config_dir, db_path.to_str().unwrap(), settings_path.to_str().unwrap()) {
        Ok(_) => {
            info!("Application initialized successfully");
            
            // TODO: Initialize QML/Qt runtime
            // For now, this is a headless demo showing backend initialization
            println!("\n✅ OmarchyLook backend initialized");
            println!("   Config: {}", config_dir.display());
            println!("   Next: Qt/QML UI integration\n");
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

fn initialize_app(_config_dir: &PathBuf, db_path: &str, settings_path: &str) -> omarchy_look::errors::Result<()> {
    // Initialize database
    let _db = Database::open(db_path)?;
    info!("Database initialized");
    
    // Initialize settings
    let _settings = SettingsManager::open(settings_path)?;
    info!("Settings initialized");
    
    // Initialize auth (check if already authenticated)
    let auth = AuthManager::new();
    if auth.is_authenticated() {
        info!("User already authenticated (cached tokens available)");
    } else {
        info!("User not authenticated; will prompt for Device Flow login");
    }
    
    Ok(())
}
