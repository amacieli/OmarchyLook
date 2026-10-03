//! Email provider trait for pluggable auth backends
//!
//! Implementations: Graph API, IMAP (future)

use crate::errors::Result;
use crate::models::{EmailMessage, MailFolder};
use async_trait::async_trait;

/// Trait for email provider implementations (Graph, IMAP, etc.)
#[async_trait]
pub trait EmailProvider: Send + Sync {
    /// Fetch emails from inbox (convenience — calls fetch_folder_messages("inbox", limit))
    async fn fetch_inbox(&self, limit: usize) -> Result<Vec<EmailMessage>>;

    /// Fetch emails from a specific folder by ID or well-known name
    async fn fetch_folder_messages(&self, folder_id: &str, limit: usize) -> Result<Vec<EmailMessage>>;

    /// Fetch ALL messages in a folder with pagination, streaming batches to a channel.
    /// Default implementation calls fetch_folder_messages repeatedly (non-paginated fallback).
    async fn fetch_all_folder_messages(
        &self,
        folder_id: &str,
        tx: tokio::sync::mpsc::Sender<Vec<EmailMessage>>,
    ) -> Result<usize> {
        // Default: one page of 50 (providers that support full pagination override this)
        let emails = self.fetch_folder_messages(folder_id, 50).await?;
        let count = emails.len();
        if !emails.is_empty() {
            let _ = tx.send(emails).await;
        }
        Ok(count)
    }

    /// Fetch all top-level mail folders
    async fn fetch_folders(&self) -> Result<Vec<MailFolder>>;

    /// Check if the token is still valid
    async fn is_token_valid(&self) -> Result<bool>;
}

pub mod graph;
pub use graph::GraphEmailProvider;

pub mod calendar;
pub use calendar::{CalendarProvider, GraphCalendarProvider};

pub mod contacts;
pub use contacts::{ContactsProvider, GraphContactsProvider};
