/// Auth Bridge module - handles Microsoft Graph OAuth2 Device Flow
/// Phase 2: QML integration via cxx-qt (deferred until bindings are tested)

use log::info;

/// AuthBridge - Rust-Qt bridge for authentication flow
pub struct AuthBridge {
    user_code: String,
    device_code: String,
    is_logging_in: bool,
}

impl Default for AuthBridge {
    fn default() -> Self {
        AuthBridge {
            user_code: String::new(),
            device_code: String::new(),
            is_logging_in: false,
        }
    }
}

impl AuthBridge {
    pub fn new() -> Self {
        Self::default()
    }

    /// Initiate Microsoft Device Flow authentication
    pub fn login(&mut self) -> Result<(), String> {
        info!("AuthBridge::login() - Device Flow authentication initiated");
        self.is_logging_in = true;

        // TODO: Call crate::auth::device_flow_login()
        // For now, placeholder
        Ok(())
    }

    /// Logout and clear credentials
    pub fn logout(&mut self) {
        info!("AuthBridge::logout()");
        self.user_code.clear();
        self.device_code.clear();
        self.is_logging_in = false;
    }

    /// Copy text to system clipboard
    pub fn copy_to_clipboard(&self, text: &str) {
        info!("AuthBridge::copy_to_clipboard() - text length: {}", text.len());
        // TODO: Integrate with Qt's QClipboard via cxx-qt
    }

    pub fn get_user_code(&self) -> &str {
        &self.user_code
    }

    pub fn set_device_code(&mut self, user_code: String, device_code: String) {
        self.user_code = user_code;
        self.device_code = device_code;
    }

    pub fn is_logging_in(&self) -> bool {
        self.is_logging_in
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_auth_bridge_default() {
        let bridge = AuthBridge::default();
        assert_eq!(bridge.get_user_code(), "");
        assert!(!bridge.is_logging_in());
    }

    #[test]
    fn test_auth_bridge_logout() {
        let mut bridge = AuthBridge::new();
        bridge.set_device_code("ABC123".to_string(), "xyz".to_string());
        bridge.logout();
        assert_eq!(bridge.get_user_code(), "");
        assert!(!bridge.is_logging_in());
    }
}
