//! Data models for OmarchyLook

use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

/// Device Flow OAuth response from Microsoft
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DeviceFlowResponse {
    pub device_code: String,
    pub user_code: String,
    pub verification_uri: String,
    pub expires_in: i64,
    #[serde(default)]
    pub interval: i64,
}

/// Token response from Microsoft
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct TokenResponse {
    pub access_token: String,
    pub token_type: String,
    pub expires_in: i64,
    #[serde(default)]
    pub refresh_token: Option<String>,
    #[serde(default)]
    pub scope: String,
}

/// Cached token in keyring
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct CachedToken {
    pub access_token: String,
    pub refresh_token: Option<String>,
}

/// Mail message from Graph API
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Message {
    pub id: String,
    pub subject: String,
    pub from: Option<Recipient>,
    pub to_recipients: Option<Vec<Recipient>>,
    pub body: Option<ItemBody>,
    pub received_date_time: Option<String>,
    pub sent_date_time: Option<String>,
    pub is_read: Option<bool>,
    pub has_attachments: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Recipient {
    pub email_address: Option<EmailAddress>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct EmailAddress {
    pub address: String,
    pub name: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ItemBody {
    pub content_type: Option<String>,
    pub content: String,
}

/// Cached mail entry in SQLite
#[derive(Debug, Clone)]
pub struct CachedMessage {
    pub id: String,
    pub subject: String,
    pub from_email: String,
    pub from_name: Option<String>,
    pub body: String,
    pub received_at: DateTime<Utc>,
    pub is_read: bool,
    pub cached_at: DateTime<Utc>,
}

/// Settings structure (mirrors TOML config)
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Settings {
    pub font: FontSettings,
    pub color: ColorSettings,
    pub ui: UiSettings,
    pub sync: SyncSettings,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct FontSettings {
    pub family: String,
    pub base_size: i32,
    pub scale_factor: f64,
}

impl FontSettings {
    /// Calculate effective font size: base_size * scale_factor
    pub fn effective_size(&self) -> i32 {
        (self.base_size as f64 * self.scale_factor).round() as i32
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ColorSettings {
    pub bg_dark: String,
    pub bg_surface: String,
    pub border: String,
    pub text_primary: String,
    pub text_secondary: String,
    pub accent_purple: String,
    pub danger_red: String,
    pub success_green: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct UiSettings {
    pub window_width: i32,
    pub window_height: i32,
    pub use_tui_style: bool,
    pub animation_enabled: bool,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SyncSettings {
    /// Poll interval in seconds (default 60, min 10)
    pub poll_interval_secs: i32,
    /// Auto-sync on startup
    pub auto_sync: bool,
    /// Keep messages cached for N days (0 = forever)
    pub cache_retention_days: i32,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            font: FontSettings {
                family: "JetBrainsMono Nerd Font".to_string(),
                base_size: 14,
                scale_factor: 1.0,
            },
            color: ColorSettings {
                bg_dark: "#0d0d0d".to_string(),
                bg_surface: "#242424".to_string(),
                border: "#333333".to_string(),
                text_primary: "#e8e8e8".to_string(),
                text_secondary: "#888888".to_string(),
                accent_purple: "#7c6af7".to_string(),
                danger_red: "#ff6b6b".to_string(),
                success_green: "#51cf66".to_string(),
            },
            ui: UiSettings {
                window_width: 1280,
                window_height: 800,
                use_tui_style: true,
                animation_enabled: true,
            },
            sync: SyncSettings {
                poll_interval_secs: 60,
                auto_sync: true,
                cache_retention_days: 30,
            },
        }
    }
}
