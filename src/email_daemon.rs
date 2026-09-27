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
use tokio::time::sleep;

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

        let folder_interval = Duration::from_secs(self.config.folder_sync_interval_secs);
        let mut last_folder_sync: Option<Instant> = None;
        let mut last_message_sync: Option<Instant> = None;
        let message_interval = Duration::from_secs(self.config.poll_interval_secs);

        // Poll every 5s while waiting for auth; switch to normal interval once synced
        let mut authenticated_once = false;

        loop {
            match self.provider.is_token_valid().await {
                Ok(true) => {
                    debug!("Token valid, proceeding with email sync");

                    let is_first_run = !authenticated_once;
                    authenticated_once = true;

                    // Sync folders: on first authenticated run, or when interval elapsed
                    let should_sync_folders = last_folder_sync
                        .map(|t| t.elapsed() >= folder_interval)
                        .unwrap_or(true);

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

                    // One-shot backfill: runs only on the first authenticated run,
                    // and only if there are messages with folder_id IS NULL.
                    // Spawned as a separate task so it doesn't block the sync loop.
                    if is_first_run {
                        // Re-borrow via Arc isn't available here; run inline but yield frequently
                        // (fetch_message_folder_map yields between pages; backfill_folder_ids yields every 500)
                        info!("First authenticated run — checking if folder_id backfill is needed");
                        if let Err(e) = self.backfill_folder_ids().await {
                            error!("Backfill failed: {}", e);
                        }
                    }

                    // Sync messages: on first authenticated run, or when interval elapsed
                    let should_sync_messages = is_first_run || last_message_sync
                        .map(|t| t.elapsed() >= message_interval)
                        .unwrap_or(true);

                    if should_sync_messages {
                        match self.sync_messages(is_first_run).await {
                            Ok(count) => {
                                if count > 0 {
                                    info!("Successfully synced {} new emails", count);
                                } else {
                                    debug!("No new emails");
                                }
                                last_message_sync = Some(Instant::now());
                            }
                            Err(e) => {
                                error!("Failed to sync messages: {}", e);
                            }
                        }
                    }

                    // After a successful sync, sleep for the normal poll interval
                    tokio::time::sleep(message_interval).await;
                }
                Ok(false) => {
                    warn!("Auth token not valid, waiting for authentication...");
                    // Poll every 5s while unauthenticated so we pick up login quickly
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }
                Err(e) => {
                    error!("Failed to check token validity: {}", e);
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }
            }
        }
    }

    /// One-shot backfill: fetch (id, parentFolderId) for all messages in every folder,
    /// then bulk-UPDATE any rows in the DB that still have folder_id IS NULL.
    /// Runs once on the first authenticated launch; skipped if all rows already filled.
    async fn backfill_folder_ids(&self) -> Result<()> {
        let unfilled = self.db.count_unfilled_folder_ids().unwrap_or(0);
        if unfilled == 0 {
            debug!("Backfill: all rows already have folder_id — skipping");
            return Ok(());
        }
        info!("Backfill: {} messages missing folder_id — starting one-shot backfill", unfilled);

        let folders = self.db.get_folders()?;
        if folders.is_empty() {
            info!("Backfill: no folders cached yet — will retry after folder sync");
            return Ok(());
        }

        let mut total_updated = 0usize;
        for folder in &folders {
            debug!("Backfill: fetching id map for folder '{}'", folder.display_name);
            match self.provider.fetch_message_folder_map(&folder.id).await {
                Ok(pairs) => {
                    // Write in chunks of 500 so we yield between DB bursts
                    for chunk in pairs.chunks(500) {
                        match self.db.backfill_folder_ids(chunk) {
                            Ok(n) => total_updated += n,
                            Err(e) => error!("Backfill DB write error: {}", e),
                        }
                        tokio::task::yield_now().await;
                    }
                    debug!("Backfill: folder '{}' done", folder.display_name);
                }
                Err(e) => error!("Backfill: failed to fetch id map for '{}': {}", folder.display_name, e),
            }
        }

        info!("Backfill complete: updated {} rows with folder_id", total_updated);
        Ok(())
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

    /// Sync messages for all known folders
    /// - First run (is_initial): full paginated sync via channel, non-blocking
    /// - Subsequent runs: fetch 50 most recent per folder for incremental updates
    async fn sync_messages(&self, is_initial: bool) -> Result<usize> {
        let folders = self.db.get_folders()?;

        if folders.is_empty() {
            // Fall back to inbox if no folders cached yet
            return self.sync_folder_messages("inbox", is_initial).await;
        }

        let mut total = 0;
        for folder in &folders {
            match self.sync_folder_messages(&folder.id, is_initial).await {
                Ok(count) => total += count,
                Err(e) => error!("Failed to sync folder {}: {}", folder.display_name, e),
            }
        }
        Ok(total)
    }

    /// Fetch and insert messages for a single folder.
    /// is_initial=true: paginate all messages; false: fetch 50 most recent only.
    async fn sync_folder_messages(&self, folder_id: &str, is_initial: bool) -> Result<usize> {
        if is_initial {
            debug!("Full paginated sync for folder: {}", folder_id);
            let (tx, mut rx) = tokio::sync::mpsc::channel::<Vec<crate::models::EmailMessage>>(4);

            let provider = Arc::clone(&self.provider);
            let folder_id_owned = folder_id.to_string();

            // Spawn the paginator so it runs concurrently with DB writes
            let fetch_handle = tokio::spawn(async move {
                provider.fetch_all_folder_messages(&folder_id_owned, tx).await
            });

            let db = Arc::clone(&self.db);
            let mut inserted = 0usize;

            // Consume and persist each batch as it arrives
            while let Some(batch) = rx.recv().await {
                for email in &batch {
                    match db.email_exists(&email.id) {
                        Ok(false) => {
                            if let Err(e) = db.insert_email(email) {
                                error!("Failed to insert email {}: {}", email.id, e);
                            } else {
                                inserted += 1;
                            }
                        }
                        Ok(true) => {}
                        Err(e) => error!("DB existence check failed: {}", e),
                    }
                }
                debug!("Wrote batch of {} to DB (folder {})", batch.len(), folder_id);
                tokio::task::yield_now().await;
            }

            if let Ok(Err(e)) = fetch_handle.await {
                error!("Paginated fetch error for {}: {}", folder_id, e);
            }

            Ok(inserted)
        } else {
            // Incremental: 50 most recent
            debug!("Incremental sync for folder: {}", folder_id);
            let emails = self.provider.fetch_folder_messages(folder_id, 50).await?;
            let mut inserted = 0;
            for email in emails {
                match self.db.email_exists(&email.id) {
                    Ok(false) => {
                        self.db.insert_email(&email)?;
                        inserted += 1;
                        debug!("Inserted email: {} from {}", email.subject, email.from);
                    }
                    Ok(true) => {}
                    Err(e) => error!("Failed to check email existence: {}", e),
                }
            }
            Ok(inserted)
        }
    }
}

/// Trigger an immediate email sync (used by HTTP trigger)
pub async fn trigger_sync(daemon: &EmailDaemon) {
    match daemon.sync_messages(false).await {
        Ok(count) => {
            info!("Triggered sync: stored {} new emails", count);
        }
        Err(e) => {
            error!("Triggered sync failed: {}", e);
        }
    }
}
