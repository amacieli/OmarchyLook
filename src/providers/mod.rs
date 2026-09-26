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

    /// Fetch all top-level mail folders
    async fn fetch_folders(&self) -> Result<Vec<MailFolder>>;

    /// Check if the token is still valid
    async fn is_token_valid(&self) -> Result<bool>;
}

pub mod graph;
pub use graph::GraphEmailProvider;
