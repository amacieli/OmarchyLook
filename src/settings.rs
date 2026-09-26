//! Settings manager with TOML config and file watching

use crate::errors::{OmarchyError, Result};
use crate::models::Settings;
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
