//! Calendar synchronization daemon (mirrors email_daemon.rs)
//!
//! - First authenticated run: full paginated sync of the entire calendar
//!   history via a channel, writing each ~50-event page as it arrives
//! - Subsequent polls (default 2 minutes): 50 most recent events
//! - Events are upserted into SQLite so edits and reschedules propagate
//! - Fully independent of the mail daemon: own provider, own DB handle, own loop

use crate::db::Database;
use crate::errors::Result;
use crate::providers::CalendarProvider;
use log::{debug, error, info, warn};
use std::sync::Arc;
use std::time::{Duration, Instant};

pub struct CalendarDaemonConfig {
    pub poll_interval_secs: u64,
}

impl Default for CalendarDaemonConfig {
    fn default() -> Self {
        Self { poll_interval_secs: 120 }
    }
}

pub struct CalendarDaemon {
    config: CalendarDaemonConfig,
    db: Arc<Database>,
    provider: Arc<dyn CalendarProvider>,
}

impl CalendarDaemon {
    pub fn new(config: CalendarDaemonConfig, db: Arc<Database>, provider: Arc<dyn CalendarProvider>) -> Self {
        Self { config, db, provider }
    }

    pub async fn start(&self) {
        info!("Calendar daemon started (events every {}s)", self.config.poll_interval_secs);
        let interval = Duration::from_secs(self.config.poll_interval_secs);
        let mut last_sync: Option<Instant> = None;
        let mut authenticated_once = false;

        loop {
            match self.provider.is_token_valid().await {
                Ok(true) => {
                    let is_first_run = !authenticated_once;
                    authenticated_once = true;

                    let should_sync = is_first_run
                        || last_sync.map(|t| t.elapsed() >= interval).unwrap_or(true);

                    if should_sync {
                        match self.sync_events(is_first_run).await {
                            Ok(count) => {
                                if count > 0 {
                                    info!("Successfully synced {} calendar events", count);
                                } else {
                                    debug!("No new calendar events");
                                }
                                last_sync = Some(Instant::now());
                            }
                            Err(e) => error!("Failed to sync calendar: {}", e),
                        }
                    }
                    tokio::time::sleep(interval).await;
                }
                Ok(false) => {
                    warn!("Calendar daemon: auth token not valid, waiting for authentication...");
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }
                Err(e) => {
                    error!("Calendar daemon: failed to check token validity: {}", e);
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }
            }
        }
    }

    /// is_initial=true: paginate the full history; false: 50 most recent only.
    async fn sync_events(&self, is_initial: bool) -> Result<usize> {
        if is_initial {
            debug!("Full paginated calendar sync");
            let (tx, mut rx) = tokio::sync::mpsc::channel::<Vec<crate::models::CalendarEvent>>(4);
            let provider = Arc::clone(&self.provider);
            let fetch_handle = tokio::spawn(async move { provider.fetch_all_events(tx).await });

            let mut written = 0usize;
            while let Some(batch) = rx.recv().await {
                for ev in &batch {
                    match self.db.upsert_event(ev) {
                        Ok(()) => written += 1,
                        Err(e) => error!("Failed to store event {}: {}", ev.id, e),
                    }
                }
                tokio::task::yield_now().await;
            }

            if let Ok(Err(e)) = fetch_handle.await {
                error!("Paginated calendar fetch error: {}", e);
            }
            Ok(written)
        } else {
            debug!("Incremental calendar sync");
            let events = self.provider.fetch_events(50).await?;
            let mut written = 0;
            for ev in &events {
                self.db.upsert_event(ev)?;
                written += 1;
            }
            Ok(written)
        }
    }
}
