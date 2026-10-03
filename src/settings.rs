//! Settings manager with TOML config and file watching

use crate::errors::{OmarchyError, Result};
use crate::models::{CalendarSettings, Settings};
use log::{debug, info, warn};
use std::path::{Path, PathBuf};
use std::fs;
use std::sync::{Arc, Mutex};

pub struct SettingsManager {
    path: PathBuf,
    settings: Arc<Mutex<Settings>>,
    _watcher: Option<notify::RecommendedWatcher>,
}

impl SettingsManager {
    /// Load or create settings from TOML file
    pub fn open(path: &str) -> Result<Self> {
        let path = PathBuf::from(path);
        debug!("Loading settings from: {}", path.display());
        
        // Create parent directory if needed
        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() {
                fs::create_dir_all(parent)?;
            }
        }
        
        // Load or create settings
        let settings = if path.exists() {
            let content = fs::read_to_string(&path)?;
            toml::from_str(&content)
                .map_err(|e| OmarchyError::SettingsError(e.to_string()))?
        } else {
            let default = Settings::default();
            let content = toml::to_string_pretty(&default)
                .map_err(|e| OmarchyError::SettingsError(e.to_string()))?;
            fs::write(&path, content)?;
            default
        };
        
        info!("Settings loaded from: {}", path.display());
        
        let settings = Arc::new(Mutex::new(settings));
        
        // Set up file watcher (optional, non-fatal if it fails)
        let watcher = Self::setup_watcher(&path, Arc::clone(&settings)).ok();
        
        Ok(Self {
            path,
            settings,
            _watcher: watcher,
        })
    }
    
    /// Set up file watcher for settings changes
    fn setup_watcher(
        path: &Path,
        settings: Arc<Mutex<Settings>>,
    ) -> Result<notify::RecommendedWatcher> {
        use notify::{Watcher, RecursiveMode, Result as NotifyResult};
        
        let path = path.to_path_buf();
        let path_clone = path.clone();
        let path_for_read = path.clone();
        
        let mut watcher = notify::recommended_watcher(move |res: NotifyResult<_>| {
            if let Ok(event) = res {
                // Reload settings on file change
                if let notify::Event { ref paths, .. } = event {
                    if paths.iter().any(|p| p == &path_clone) {
                        match fs::read_to_string(&path_for_read) {
                            Ok(content) => {
                                match toml::from_str::<Settings>(&content) {
                                    Ok(new_settings) => {
                                        if let Ok(mut s) = settings.lock() {
                                            *s = new_settings;
                                            info!("Settings reloaded from file");
                                        }
                                    }
                                    Err(e) => {
                                        warn!("Failed to parse settings file: {}", e);
                                    }
                                }
                            }
                            Err(e) => {
                                warn!("Failed to read settings file: {}", e);
                            }
                        }
                    }
                }
            }
        })
        .map_err(|e| OmarchyError::SettingsError(e.to_string()))?;
        
        if let Some(parent) = path.parent() {
            watcher.watch(parent, RecursiveMode::NonRecursive)
                .map_err(|e| OmarchyError::SettingsError(e.to_string()))?;
        }
        
        debug!("File watcher set up for settings");
        Ok(watcher)
    }
    
    /// Get current settings (read-only)
    pub fn get(&self) -> Result<Settings> {
        self.settings.lock()
            .map(|guard| guard.clone())
            .map_err(|_| OmarchyError::SettingsError("Settings lock poisoned".to_string()))
    }
    
    /// Update settings and write to disk
    pub fn set(&self, new_settings: Settings) -> Result<()> {
        let content = toml::to_string_pretty(&new_settings)
            .map_err(|e| OmarchyError::SettingsError(e.to_string()))?;
        
        fs::write(&self.path, &content)?;
        debug!("Settings written to: {}", self.path.display());
        
        self.settings.lock()
            .map(|mut guard| *guard = new_settings)
            .map_err(|_| OmarchyError::SettingsError("Settings lock poisoned".to_string()))
    }
    
    /// Update a specific setting field
    pub fn update_sync_interval(&self, seconds: i32) -> Result<()> {
        let mut settings = self.get()?;
        settings.sync.poll_interval_secs = seconds.max(10); // Enforce 10s minimum
        self.set(settings)
    }
    
    /// Get sync interval (with validation)
    pub fn get_sync_interval(&self) -> Result<i32> {
        let settings = self.get()?;
        Ok(settings.sync.poll_interval_secs.max(10))
    }
}

/// Calendar settings from a settings.toml, defaulting when the file is missing, unreadable or
/// has no [calendar] section. Always within the supported range.
pub fn read_calendar_settings(path: &Path) -> CalendarSettings {
    fs::read_to_string(path)
        .ok()
        .and_then(|s| toml::from_str::<Settings>(&s).ok())
        .map(|s| s.calendar)
        .unwrap_or_default()
        .sanitized()
}

/// Persist calendar settings (clamped) into settings.toml, leaving every other setting as it
/// was. Refuses to touch a file that does not parse. Returns what was stored.
pub fn write_calendar_settings(path: &Path, wanted: &CalendarSettings) -> Result<CalendarSettings> {
    let mut settings: Settings = match fs::read_to_string(path) {
        Ok(content) => toml::from_str(&content).map_err(|e| OmarchyError::SettingsError(e.to_string()))?,
        Err(_) => Settings::default(),
    };
    settings.calendar = wanted.sanitized();
    let content = toml::to_string_pretty(&settings).map_err(|e| OmarchyError::SettingsError(e.to_string()))?;
    fs::write(path, content)?;
    Ok(settings.calendar)
}

#[cfg(test)]
mod calendar_settings_tests {
    use super::*;

    fn temp(name: &str) -> PathBuf {
        let p = std::env::temp_dir().join(format!("omarchylook-settings-{}-{}.toml", name, std::process::id()));
        let _ = fs::remove_file(&p);
        p
    }

    #[test]
    fn defaults_are_five_years_back_and_ten_ahead() {
        assert_eq!(read_calendar_settings(&temp("missing")), CalendarSettings { recurrence_years_back: 5, recurrence_years_ahead: 10 });
    }

    #[test]
    fn a_settings_file_from_before_this_section_still_loads() {
        let p = temp("legacy");
        let mut old = toml::to_string_pretty(&Settings::default()).unwrap();
        old = old.split("[calendar]").next().unwrap().to_string();       // simulate the old file
        assert!(!old.contains("calendar"));
        fs::write(&p, old).unwrap();
        assert!(toml::from_str::<Settings>(&fs::read_to_string(&p).unwrap()).is_ok(), "must not break app start-up");
        assert_eq!(read_calendar_settings(&p).recurrence_years_ahead, 10);
        let _ = fs::remove_file(&p);
    }

    #[test]
    fn write_round_trips_clamps_and_preserves_other_settings() {
        let p = temp("write");
        let mut base = Settings::default();
        base.ui.sidebar_expanded = false;
        base.font.family = "Custom Font".into();
        fs::write(&p, toml::to_string_pretty(&base).unwrap()).unwrap();

        let stored = write_calendar_settings(&p, &CalendarSettings { recurrence_years_back: 7, recurrence_years_ahead: 12 }).unwrap();
        assert_eq!((stored.recurrence_years_back, stored.recurrence_years_ahead), (7, 12));
        assert_eq!(read_calendar_settings(&p), stored);
        let back: Settings = toml::from_str(&fs::read_to_string(&p).unwrap()).unwrap();
        assert!(!back.ui.sidebar_expanded && back.font.family == "Custom Font", "other settings untouched");

        let clamped = write_calendar_settings(&p, &CalendarSettings { recurrence_years_back: -3, recurrence_years_ahead: 99 }).unwrap();
        assert_eq!((clamped.recurrence_years_back, clamped.recurrence_years_ahead), (0, 30));
        let _ = fs::remove_file(&p);
    }

    #[test]
    fn an_unparseable_settings_file_is_not_overwritten() {
        let p = temp("broken");
        fs::write(&p, "this is = not [valid toml").unwrap();
        assert!(write_calendar_settings(&p, &CalendarSettings::default()).is_err());
        assert_eq!(fs::read_to_string(&p).unwrap(), "this is = not [valid toml");
        let _ = fs::remove_file(&p);
    }
}
