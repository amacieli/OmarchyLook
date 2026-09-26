//! Email provider trait for pluggable auth backends
//!
//! Implementations: Graph API, IMAP (future)

use crate::errors::Result;
use crate::models::EmailMessage;
use async_trait::async_trait;

/// Trait for email provider implementations (Graph, IMAP, etc.)
#[async_trait]
pub trait EmailProvider: Send + Sync {
    /// Fetch emails from inbox. Returns up to `limit` emails.
    async fn fetch_inbox(&self, limit: usize) -> Result<Vec<EmailMessage>>;
    
    /// Check if the token is still valid
    async fn is_token_valid(&self) -> Result<bool>;
}

pub mod graph;
pub use graph::GraphEmailProvider;
