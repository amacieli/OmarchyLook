//! Email synchronization daemon with pluggable provider support
//!
//! This module runs an async task that:
//! - Polls for new emails at a configured interval (default: 2 minutes)
//! - Supports multiple auth providers (Graph API, IMAP future)
//! - Deduplicates against SQLite before insertion
//! - Respects token validity and retries on auth failure
//! - Triggers immediate sync when token becomes valid

use crate::db::Database;
use crate::models::Settings;
use crate::providers::EmailProvider;
use crate::errors::Result;
use log::{debug, error, info, warn};
use std::sync::Arc;
use std::time::Duration;
use tokio::time::{sleep, interval};

/// Configuration for the email daemon
pub struct DaemonConfig {
    pub poll_interval_secs: u64,
    pub max_retries: usize,
}

impl Default for DaemonConfig {
    fn default() -> Self {
        Self {
            poll_interval_secs: 120, // 2 minutes
            max_retries: 10,
        }
    }
}

impl From<&Settings> for DaemonConfig {
    fn from(settings: &Settings) -> Self {
        Self {
            poll_interval_secs: settings.sync.poll_interval_secs as u64,
            max_retries: 10,
        }
    }
}

/// Email daemon that periodically syncs inbox
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
            "Email daemon started (polling every {} seconds)",
            self.config.poll_interval_secs
        );

        let mut poll_interval = interval(Duration::from_secs(self.config.poll_interval_secs));
        let mut retry_count = 0;

        loop {
            // Check token validity before polling
            match self.provider.is_token_valid().await {
                Ok(true) => {
                    // Token is valid, reset retry counter
                    retry_count = 0;
                    debug!("Token valid, proceeding with email sync");

                    // Fetch and store emails
                    match self.sync_inbox().await {
                        Ok(count) => {
                            info!("Successfully synced {} new emails", count);
                        }
                        Err(e) => {
                            error!("Failed to sync inbox: {}", e);
                        }
                    }
                }
                Ok(false) => {
                    // Token is invalid/missing
                    warn!("Auth token not valid, waiting for authentication...");
                }
                Err(e) => {
                    error!("Failed to check token validity: {}", e);
                }
            }

            // Wait for next poll interval
            poll_interval.tick().await;
        }
    }

    /// Perform one sync cycle: fetch inbox and store new emails
    async fn sync_inbox(&self) -> Result<usize> {
        debug!("Syncing inbox...");

        // Fetch emails from provider (first 10)
        let emails = self.provider.fetch_inbox(10).await?;

        let mut inserted_count = 0;
        for email in emails {
            // Check if email already exists
            match self.db.email_exists(&email.id) {
                Ok(exists) => {
                    if !exists {
                        // Insert new email
                        self.db.insert_email(&email)?;
                        inserted_count += 1;
                        debug!("Inserted email: {} from {}", email.subject, email.from);
                    } else {
                        debug!("Email already exists, skipping: {}", email.id);
                    }
                }
                Err(e) => {
                    error!("Failed to check email existence: {}", e);
                }
            }
        }

        Ok(inserted_count)
    }
}

/// Trigger an immediate email sync
pub async fn trigger_sync(daemon: &EmailDaemon) {
    match daemon.sync_inbox().await {
        Ok(count) => {
            info!("Triggered sync: stored {} new emails", count);
        }
        Err(e) => {
            error!("Triggered sync failed: {}", e);
        }
    }
}
