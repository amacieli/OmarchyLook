//! Email synchronization daemon with pluggable provider support
//!
//! This module runs an async task that:
//! - Polls for new emails at a configured interval (default: 2 minutes)
//! - Syncs folder list every 10 minutes (folders change rarely)
//! - Fetches messages per-folder, storing folder_id on each message
//! - Deduplicates against SQLite before insertion
//! - Respects token validity and retries on auth failure

use crate::db::Database;
use crate::models::Settings;
use crate::providers::EmailProvider;
use crate::errors::Result;
use log::{debug, error, info, warn};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::time::interval;

/// Configuration for the email daemon
pub struct DaemonConfig {
    pub poll_interval_secs: u64,
    pub folder_sync_interval_secs: u64,
    pub max_retries: usize,
}

impl Default for DaemonConfig {
    fn default() -> Self {
        Self {
            poll_interval_secs: 120,         // 2 minutes for messages
            folder_sync_interval_secs: 600,  // 10 minutes for folders
            max_retries: 10,
        }
    }
}

impl From<&Settings> for DaemonConfig {
    fn from(settings: &Settings) -> Self {
        Self {
            poll_interval_secs: settings.sync.poll_interval_secs as u64,
            folder_sync_interval_secs: 600,
            max_retries: 10,
        }
    }
}

/// Email daemon that periodically syncs folders and messages
pub struct EmailDaemon {
    config: DaemonConfig,
    db: Arc<Database>,
    provider: Arc<dyn EmailProvider>,
}

impl EmailDaemon {
    pub fn new(
        config: DaemonConfig,
        db: Arc<Database>,
        provider: Arc<dyn EmailProvider>,
    ) -> Self {
        Self { config, db, provider }
    }

    /// Start the daemon (runs indefinitely until cancelled)
    pub async fn start(&self) {
        info!(
            "Email daemon started (messages every {}s, folders every {}s)",
            self.config.poll_interval_secs, self.config.folder_sync_interval_secs
        );

        let mut message_tick = interval(Duration::from_secs(self.config.poll_interval_secs));
        let folder_interval = Duration::from_secs(self.config.folder_sync_interval_secs);
        let mut last_folder_sync: Option<Instant> = None;

        loop {
            // Check token validity before doing anything
            match self.provider.is_token_valid().await {
                Ok(true) => {
                    debug!("Token valid, proceeding with email sync");

                    // Sync folders if due (first run or interval elapsed)
                    let should_sync_folders = last_folder_sync
                        .map(|t| t.elapsed() >= folder_interval)
                        .unwrap_or(true); // always sync on first run

                    if should_sync_folders {
                        match self.sync_folders().await {
                            Ok(count) => {
                                info!("Synced {} folders", count);
                                last_folder_sync = Some(Instant::now());
                            }
                            Err(e) => {
                                error!("Failed to sync folders: {}", e);
                            }
                        }
                    }

                    // Sync messages across all cached folders
                    match self.sync_messages().await {
                        Ok(count) => {
                            if count > 0 {
                                info!("Successfully synced {} new emails", count);
                            } else {
                                debug!("No new emails");
                            }
                        }
                        Err(e) => {
                            error!("Failed to sync messages: {}", e);
                        }
                    }
                }
                Ok(false) => {
                    warn!("Auth token not valid, waiting for authentication...");
                }
                Err(e) => {
                    error!("Failed to check token validity: {}", e);
                }
            }

            message_tick.tick().await;
        }
    }

    /// Fetch and upsert all top-level folders
    async fn sync_folders(&self) -> Result<usize> {
        debug!("Syncing folders...");
        let folders = self.provider.fetch_folders().await?;
        let count = folders.len();
        for folder in &folders {
            if let Err(e) = self.db.upsert_folder(folder) {
                error!("Failed to upsert folder {}: {}", folder.display_name, e);
            }
        }
        debug!("Folder sync complete: {} folders", count);
        Ok(count)
    }

    /// Sync messages for all known folders (10 most recent per folder)
    async fn sync_messages(&self) -> Result<usize> {
        // Get cached folders to determine which ones to fetch from
        let folders = self.db.get_folders()?;

        if folders.is_empty() {
            // Fall back to inbox if no folders cached yet
            return self.sync_folder_messages("inbox").await;
        }

        let mut total = 0;
        for folder in &folders {
            match self.sync_folder_messages(&folder.id).await {
                Ok(count) => total += count,
                Err(e) => error!("Failed to sync folder {}: {}", folder.display_name, e),
            }
        }
        Ok(total)
    }

    /// Fetch and insert new messages for a single folder
    async fn sync_folder_messages(&self, folder_id: &str) -> Result<usize> {
        debug!("Syncing messages for folder: {}", folder_id);
        let emails = self.provider.fetch_folder_messages(folder_id, 10).await?;
        let mut inserted = 0;

        for email in emails {
            match self.db.email_exists(&email.id) {
                Ok(false) => {
                    self.db.insert_email(&email)?;
                    inserted += 1;
                    debug!("Inserted email: {} from {}", email.subject, email.from);
                }
                Ok(true) => {
                    debug!("Email already exists, skipping: {}", email.id);
                }
                Err(e) => {
                    error!("Failed to check email existence: {}", e);
                }
            }
        }

        Ok(inserted)
    }
}

/// Trigger an immediate email sync (used by HTTP trigger)
pub async fn trigger_sync(daemon: &EmailDaemon) {
    match daemon.sync_messages().await {
        Ok(count) => {
            info!("Triggered sync: stored {} new emails", count);
        }
        Err(e) => {
            error!("Triggered sync failed: {}", e);
        }
    }
}
