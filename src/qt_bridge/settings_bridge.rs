/// Settings bridge module - exposes SettingsManager to QML
/// Phase 2: Font and UI settings exposed to QML components

use crate::settings::SettingsManager;
use crate::errors::Result;
use log::info;

/// SettingsBridge - QML-accessible settings interface
pub struct SettingsBridge {
    settings_manager: SettingsManager,
}

impl SettingsBridge {
    pub fn new(settings_manager: SettingsManager) -> Self {
        SettingsBridge { settings_manager }
    }

    /// Get the font family (monospace for terminal style)
    pub fn get_font_family(&self) -> String {
        self.settings_manager
            .get()
            .ok()
            .map(|s| s.font.family)
            .unwrap_or_else(|| "monospace".to_string())
    }

    /// Get base font size (in pixels)
    pub fn get_base_size(&self) -> i32 {
        self.settings_manager
            .get()
            .ok()
            .map(|s| s.font.base_size)
            .unwrap_or(10)
    }

    /// Get title font size (larger than base)
    pub fn get_title_size(&self) -> i32 {
        let base = self.get_base_size();
        (base as f32 * 1.2) as i32
    }

    /// Get hint/small font size
    pub fn get_hint_size(&self) -> i32 {
        let base = self.get_base_size();
        (base as f32 * 0.8) as i32
    }

    /// Update font family
    pub fn set_font_family(&mut self, family: String) -> Result<()> {
        info!("SettingsBridge::set_font_family() - {}", family);
        let mut settings = self.settings_manager.get()?;
        settings.font.family = family;
        self.settings_manager.set(settings)
    }

    /// Update font size
    pub fn set_font_size(&mut self, size: i32) -> Result<()> {
        info!("SettingsBridge::set_font_size() - {}", size);
        let mut settings = self.settings_manager.get()?;
        settings.font.base_size = size.max(8); // Enforce 8px minimum
        self.settings_manager.set(settings)
    }
}
