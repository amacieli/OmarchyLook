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
use crate::perf;
use crate::sync_state;
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

        let acct = self.db.account_id().to_string();
        perf::mark(&format!("mail[{}] daemon started", acct));
        loop {
            let tok_t = Instant::now();
            let token_check = self.provider.is_token_valid().await;
            if !authenticated_once {
                perf::mark(&format!("mail[{}] token check {:?} in {:.1}ms", acct, token_check.as_ref().ok(), tok_t.elapsed().as_secs_f64() * 1000.0));
            }
            match token_check {
                Ok(true) => {
                    debug!("Token valid, proceeding with email sync");

                    let is_first_run = !authenticated_once;
                    authenticated_once = true;

                    // Stage 1 (first cycle after launch): the 50 newest Inbox messages, before
                    // anything else, so the UI can show fresh mail at once.
                    if is_first_run {
                        self.sync_recent(50).await;
                    }

                    // Sync folders: on first authenticated run, or when interval elapsed
                    let should_sync_folders = last_folder_sync
                        .map(|t| t.elapsed() >= folder_interval)
                        .unwrap_or(true);

                    if should_sync_folders {
                        let _t = perf::span(format!("mail[{}] sync_folders", acct));
                        match self.sync_folders().await {
                            Ok(count) => {
                                info!("Synced {} folders", count);
                                last_folder_sync = Some(Instant::now());
                                sync_state::bump_mail("folder counts updated");
                            }
                            Err(e) => {
                                error!("Failed to sync folders: {}", e);
                            }
                        }
                    }

                    // Sync messages: on first authenticated run, or when interval elapsed
                    let should_sync_messages = is_first_run || last_message_sync
                        .map(|t| t.elapsed() >= message_interval)
                        .unwrap_or(true);

                    if should_sync_messages {
                        let _t = perf::span(format!("mail[{}] sync_messages(first_run={}) TOTAL", acct, is_first_run));
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

                    // Safety net: whatever happened above, never hold calendar/contacts back.
                    sync_state::open_gate(&acct);

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
        // Local read/unread changes go out first, so the reconcile below cannot undo them.
        self.push_pending_reads().await;

        let folders = self.db.get_folders()?;

        if folders.is_empty() {
            // Fall back to inbox if no folders cached yet
            return self.sync_folder_messages("inbox", is_initial).await;
        }

        // Read flags first: one cheap request per folder, so they are right within seconds
        // of launch instead of after the full paginated sync of every folder.
        {
            let _t = perf::span(format!("mail[{}] reconcile_read_state x{} folders", self.db.account_id(), folders.len()));
            for folder in &folders {
                self.reconcile_read_state(&folder.id, &folder.display_name).await;
            }
        }

        // Priority stages done (recent 50, folders, read flags): calendar and contacts may
        // start now, concurrently with the older-mail crawl below.
        sync_state::open_gate(self.db.account_id());

        let mut total = 0;
        for folder in &folders {
            let _t = perf::span(format!("mail[{}] folder '{}' sync", self.db.account_id(), folder.display_name));
            match self.sync_folder_messages(&folder.id, is_initial).await {
                Ok(count) => total += count,
                Err(e) => error!("Failed to sync folder {}: {}", folder.display_name, e),
            }
        }
        Ok(total)
    }

    /// Push read/unread changes made in the UI to the provider.
    async fn push_pending_reads(&self) {
        let pending = match self.db.pending_reads() {
            Ok(p) => p,
            Err(e) => { error!("Could not list pending read changes: {}", e); return; }
        };
        for (id, is_read) in pending {
            match self.provider.set_message_read(&id, is_read).await {
                Ok(()) => {
                    if let Err(e) = self.db.clear_read_pending(&id, is_read) {
                        error!("Could not clear pending flag for {}: {}", id, e);
                    }
                }
                // Stays pending: retried on the next cycle.
                Err(e) => warn!("Could not push read={} for {}: {}", is_read, id, e),
            }
        }
    }

    /// Bring the cached read flags of a folder in line with the provider's.
    async fn reconcile_read_state(&self, folder_id: &str, folder_name: &str) {
        match self.provider.fetch_unread_ids(folder_id).await {
            Ok(unread) => match self.db.reconcile_read_state(folder_id, &unread) {
                Ok(0) => {}
                Ok(n) => {
                    debug!("Read state: {} message(s) updated in {}", n, folder_name);
                    sync_state::bump_mail("read flags changed");
                }
                Err(e) => error!("Read-state reconcile failed for {}: {}", folder_name, e),
            },
            Err(e) => warn!("Could not read unread list for {}: {}", folder_name, e),
        }
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
            let mut first_batch = true;

            // Consume each page and persist it in ONE transaction (one fsync per page, and the
            // write lock is held for microseconds so readers/UI never wait on it).
            while let Some(batch) = rx.recv().await {
                if first_batch {
                    first_batch = false;
                    perf::mark(&format!("mail[{}] folder {} first page of {} received", db.account_id(), &folder_id[..folder_id.len().min(8)], batch.len()));
                }
                match db.insert_emails_batch(&batch) {
                    Ok(n) => inserted += n,
                    Err(e) => error!("Failed to store page for {}: {}", folder_id, e),
                }
                tokio::task::yield_now().await;
            }

            if let Ok(Err(e)) = fetch_handle.await {
                error!("Paginated fetch error for {}: {}", folder_id, e);
            }
            if inserted > 0 {
                sync_state::bump_mail(&format!("crawl stored {} older/new messages", inserted));
            }

            Ok(inserted)
        } else {
            // Incremental: 50 most recent
            debug!("Incremental sync for folder: {}", folder_id);
            let emails = self.provider.fetch_folder_messages(folder_id, 50).await?;
            let inserted = self.db.insert_emails_batch(&emails)?;
            if inserted > 0 {
                sync_state::bump_mail(&format!("poll stored {} new messages", inserted));
            }
            Ok(inserted)
        }
    }

    /// Stage 1 of a launch: the newest `limit` Inbox messages, stored in one transaction and
    /// announced to the UI immediately. Errors are logged and ignored: the regular sync that
    /// follows covers the same ground.
    async fn sync_recent(&self, limit: usize) {
        let acct = self.db.account_id().to_string();
        let t = Instant::now();
        let emails = match self.provider.fetch_inbox(limit).await {
            Ok(e) => e,
            Err(e) => {
                warn!("Recent-mail fetch failed for {}: {}", acct, e);
                return;
            }
        };
        perf::mark(&format!("mail[{}] recent {}: fetched {} in {:.1}ms", acct, limit, emails.len(), t.elapsed().as_secs_f64() * 1000.0));
        match self.db.insert_emails_batch(&emails) {
            Ok(n) => {
                perf::mark(&format!("mail[{}] recent {}: {} new stored", acct, limit, n));
                if n > 0 {
                    sync_state::bump_mail(&format!("recent {}: {} new", limit, n));
                }
            }
            Err(e) => error!("Could not store recent mail for {}: {}", acct, e),
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
