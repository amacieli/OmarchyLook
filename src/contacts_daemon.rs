//! Contacts synchronization daemon (mirrors email_daemon.rs: contact folders play the role
//! of mail folders).
//!
//! - Polls on the same schedule as mail: contacts every 2 minutes, folders every 10
//! - First authenticated run: full paginated sync of every folder, each ~50-contact page
//!   written as it arrives, until the whole address book is loaded
//! - Later polls: the 50 most recently modified contacts per folder
//! - Contacts are upserted (edits propagate); the local favorite flag is never overwritten
//! - Independent of the mail and calendar daemons: own provider, own DB handle, own loop
//!   (they only share the account's token broker)

use crate::db::Database;
use crate::errors::Result;
use crate::models::{Contact, ContactFolder};
use crate::providers::ContactsProvider;
use crate::perf;
use log::{debug, error, info, warn};
use std::sync::Arc;
use std::time::{Duration, Instant};

pub struct ContactsDaemonConfig {
    pub poll_interval_secs: u64,
    pub folder_sync_interval_secs: u64,
}

impl Default for ContactsDaemonConfig {
    fn default() -> Self {
        Self { poll_interval_secs: 120, folder_sync_interval_secs: 600 }
    }
}

pub struct ContactsDaemon {
    config: ContactsDaemonConfig,
    db: Arc<Database>,
    provider: Arc<dyn ContactsProvider>,
}

impl ContactsDaemon {
    pub fn new(config: ContactsDaemonConfig, db: Arc<Database>, provider: Arc<dyn ContactsProvider>) -> Self {
        Self { config, db, provider }
    }

    pub async fn start(&self) {
        info!(
            "Contacts daemon started (contacts every {}s, folders every {}s)",
            self.config.poll_interval_secs, self.config.folder_sync_interval_secs
        );
        let folder_interval = Duration::from_secs(self.config.folder_sync_interval_secs);
        let message_interval = Duration::from_secs(self.config.poll_interval_secs);
        let mut last_folder_sync: Option<Instant> = None;
        let mut last_sync: Option<Instant> = None;
        let mut authenticated_once = false;

        // Mail's priority stages (recent 50, folders, read flags) go first.
        let acct = self.db.account_id().to_string();
        crate::sync_state::wait_gate(&acct, Duration::from_secs(60)).await;

        loop {
            match self.provider.is_token_valid().await {
                Ok(true) => {
                    let is_first_run = !authenticated_once;
                    authenticated_once = true;

                    if last_folder_sync.map(|t| t.elapsed() >= folder_interval).unwrap_or(true) {
                        let _t = perf::span(format!("contacts[{}] sync_folders", self.db.account_id()));
                        match self.sync_folders().await {
                            Ok(n) => {
                                info!("Synced {} contact folders", n);
                                last_folder_sync = Some(Instant::now());
                            }
                            Err(e) => error!("Failed to sync contact folders: {}", e),
                        }
                    }

                    if is_first_run || last_sync.map(|t| t.elapsed() >= message_interval).unwrap_or(true) {
                        let _t = perf::span(format!("contacts[{}] sync_contacts(first_run={})", self.db.account_id(), is_first_run));
                        match self.sync_contacts(is_first_run).await {
                            Ok(n) => {
                                if n > 0 { info!("Synced {} contacts", n) } else { debug!("No contact changes") }
                                last_sync = Some(Instant::now());
                            }
                            Err(e) => error!("Failed to sync contacts: {}", e),
                        }
                    }
                    tokio::time::sleep(message_interval).await;
                }
                Ok(false) => {
                    warn!("Contacts daemon: auth token not valid, waiting for authentication...");
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }
                Err(e) => {
                    error!("Contacts daemon: failed to check token validity: {}", e);
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }
            }
        }
    }

    async fn sync_folders(&self) -> Result<usize> {
        let folders = self.provider.fetch_folders().await?;
        for f in &folders {
            if let Err(e) = self.db.upsert_contact_folder(f) {
                error!("Failed to upsert contact folder {}: {}", f.display_name, e);
            }
        }
        Ok(folders.len())
    }

    async fn sync_contacts(&self, is_initial: bool) -> Result<usize> {
        let folders: Vec<ContactFolder> = self.db.get_contact_folders()?;
        let mut total = 0;
        for folder in &folders {
            match self.sync_folder(&folder.id, is_initial).await {
                Ok(n) => total += n,
                Err(e) => error!("Failed to sync contact folder {}: {}", folder.display_name, e),
            }
        }
        Ok(total)
    }

    async fn sync_folder(&self, folder_id: &str, is_initial: bool) -> Result<usize> {
        if is_initial {
            debug!("Full paginated contacts sync for folder: {}", folder_id);
            let (tx, mut rx) = tokio::sync::mpsc::channel::<Vec<Contact>>(4);
            let provider = Arc::clone(&self.provider);
            let folder_owned = folder_id.to_string();
            let fetch = tokio::spawn(async move { provider.fetch_all_folder_contacts(&folder_owned, tx).await });

            let mut written = 0usize;
            while let Some(batch) = rx.recv().await {
                for c in &batch {
                    match self.db.upsert_contact(c) {
                        Ok(()) => written += 1,
                        Err(e) => error!("Failed to store contact {}: {}", c.id, e),
                    }
                }
                tokio::task::yield_now().await;
            }
            if let Ok(Err(e)) = fetch.await {
                error!("Paginated contacts fetch error for {}: {}", folder_id, e);
            }
            Ok(written)
        } else {
            let contacts = self.provider.fetch_folder_contacts(folder_id, 50).await?;
            for c in &contacts {
                self.db.upsert_contact(c)?;
            }
            Ok(contacts.len())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;
    use std::sync::Mutex;

    /// Serves two folders; folder "f1" has 120 contacts so the paged path is exercised.
    struct FakeProvider {
        calls: Mutex<Vec<String>>,
    }
    fn contact(i: usize, folder: &str) -> Contact {
        Contact { id: format!("{}-{}", folder, i), display_name: format!("C{}", i), folder_id: Some(folder.into()), ..Default::default() }
    }
    #[async_trait]
    impl ContactsProvider for FakeProvider {
        async fn fetch_folders(&self) -> Result<Vec<ContactFolder>> {
            Ok(vec![
                ContactFolder { id: "f1".into(), display_name: "Contacts".into(), parent_folder_id: None },
                ContactFolder { id: "f2".into(), display_name: "Clients".into(), parent_folder_id: None },
            ])
        }
        async fn fetch_folder_contacts(&self, folder_id: &str, limit: usize) -> Result<Vec<Contact>> {
            self.calls.lock().unwrap().push(format!("recent:{}:{}", folder_id, limit));
            Ok((0..3).map(|i| contact(i, folder_id)).collect())
        }
        async fn fetch_all_folder_contacts(&self, folder_id: &str, tx: tokio::sync::mpsc::Sender<Vec<Contact>>) -> Result<usize> {
            self.calls.lock().unwrap().push(format!("all:{}", folder_id));
            let n = if folder_id == "f1" { 120 } else { 5 };
            let all: Vec<Contact> = (0..n).map(|i| contact(i, folder_id)).collect();
            for page in all.chunks(50) {
                let _ = tx.send(page.to_vec()).await;
            }
            Ok(n)
        }
        async fn is_token_valid(&self) -> Result<bool> { Ok(true) }
    }

    fn daemon() -> (ContactsDaemon, Arc<FakeProvider>) {
        let p = Arc::new(FakeProvider { calls: Mutex::new(vec![]) });
        let db = Arc::new(Database::open_for_account(":memory:", "exchange-aaaaaa").unwrap());
        (ContactsDaemon::new(ContactsDaemonConfig::default(), db, p.clone()), p)
    }

    #[tokio::test(flavor = "current_thread")]
    async fn initial_sync_loads_every_page_of_every_folder() {
        let (d, p) = daemon();
        assert_eq!(d.sync_folders().await.unwrap(), 2);
        assert_eq!(d.sync_contacts(true).await.unwrap(), 125);
        assert_eq!(d.db.query_contacts("all", "first").unwrap().len(), 125);
        let calls = p.calls.lock().unwrap().clone();
        assert!(calls.contains(&"all:f1".to_string()) && calls.contains(&"all:f2".to_string()));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn incremental_sync_fetches_50_most_recent_per_folder_and_is_idempotent() {
        let (d, p) = daemon();
        d.sync_folders().await.unwrap();
        d.sync_contacts(true).await.unwrap();
        d.sync_contacts(false).await.unwrap();
        d.sync_contacts(false).await.unwrap();
        assert_eq!(d.db.query_contacts("all", "first").unwrap().len(), 125, "upserts must not duplicate");
        assert!(p.calls.lock().unwrap().contains(&"recent:f1:50".to_string()));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn favorites_survive_resync() {
        let (d, _p) = daemon();
        d.sync_folders().await.unwrap();
        d.sync_contacts(true).await.unwrap();
        d.db.set_contact_favorite("f1-1", true).unwrap();
        d.sync_contacts(false).await.unwrap();
        let favs = d.db.query_contacts("favorites", "first").unwrap();
        assert_eq!(favs.len(), 1);
        assert_eq!(favs[0].contact.id, "f1-1");
    }
}
