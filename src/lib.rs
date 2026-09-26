//! OmarchyLook: Rust backend for Outlook-style QML client
//! 
//! Modules:
//! - auth: Device Flow OAuth2 (Microsoft public client)
//! - graph: Microsoft Graph API wrapper
//! - db: SQLite cache with FTS5 for mail
//! - settings: TOML configuration with file watching
//! - keyring: SecretService integration for token storage

pub mod auth;
pub mod graph;
pub mod db;
pub mod settings;
pub mod keyring_mgr;
pub mod models;
pub mod errors;
pub mod qt_bridge;

pub use auth::AuthManager;
pub use graph::GraphClient;
pub use db::Database;
pub use settings::SettingsManager;

use log::warn;

/// Initialize logging for the application
pub fn init_logging() {
    if std::env::var("RUST_LOG").is_err() {
        std::env::set_var("RUST_LOG", "omarchy_look=debug,info");
    }
    env_logger::init();
}
