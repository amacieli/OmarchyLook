//! Microsoft Graph API email provider implementation

use crate::errors::Result;
use crate::models::EmailMessage;
use crate::auth::AuthManager;
use async_trait::async_trait;
use log::{debug, error};
use tokio::sync::Mutex;

pub struct GraphEmailProvider {
    auth: Mutex<AuthManager>,
}

impl GraphEmailProvider {
    pub fn new(auth: AuthManager) -> Self {
        Self {
            auth: Mutex::new(auth),
        }
    }
}

#[async_trait]
impl super::EmailProvider for GraphEmailProvider {
    async fn fetch_inbox(&self, limit: usize) -> Result<Vec<EmailMessage>> {
        debug!("Fetching {} emails from Graph API inbox", limit);

        // Get the current access token
        let mut auth = self.auth.lock().await;
        let token = auth.get_token().map_err(|e| {
            crate::errors::OmarchyError::AuthError(format!("Failed to get token: {}", e))
        })?;
        drop(auth); // Release lock before HTTP call
        
        if token.is_empty() {
            error!("No access token available");
            return Err(crate::errors::OmarchyError::AuthError("No access token".to_string()));
        }

        // Use reqwest to fetch emails
        let client = reqwest::Client::new();
        let url = format!(
            "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages?$top={}",
            limit
        );

        let response = client
            .get(&url)
            .header("Authorization", format!("Bearer {}", token))
            .send()
            .await
            .map_err(|e| crate::errors::OmarchyError::HttpError(e.to_string()))?;

        if !response.status().is_success() {
            error!("Graph API returned status: {}", response.status());
            return Err(crate::errors::OmarchyError::HttpError(format!(
                "Graph API error: {}",
                response.status()
            )));
        }

        let body = response
            .text()
            .await
            .map_err(|e| crate::errors::OmarchyError::HttpError(e.to_string()))?;

        let json: serde_json::Value = serde_json::from_str(&body)
            .map_err(|e| crate::errors::OmarchyError::HttpError(e.to_string()))?;

        let mut emails = Vec::new();
        if let Some(values) = json["value"].as_array() {
            for msg in values {
                let id = msg["id"].as_str().unwrap_or("").to_string();
                let subject = msg["subject"].as_str().unwrap_or("(no subject)").to_string();
                let received = msg["receivedDateTime"]
                    .as_str()
                    .unwrap_or(&chrono::Utc::now().to_rfc3339())
                    .to_string();

                // Extract sender email
                let from = msg["from"]["emailAddress"]["address"]
                    .as_str()
                    .unwrap_or("unknown@example.com")
                    .to_string();

                // Extract body content
                let body = msg["bodyPreview"]
                    .as_str()
                    .unwrap_or("")
                    .to_string();

                emails.push(EmailMessage {
                    id,
                    from,
                    subject,
                    received,
                    body,
                });
            }
        }

        debug!("Fetched {} emails successfully", emails.len());
        Ok(emails)
    }

    async fn is_token_valid(&self) -> Result<bool> {
        // Simple check: try to get access token
        let mut auth = self.auth.lock().await;
        let token = auth.get_token().map_err(|_| {
            crate::errors::OmarchyError::AuthError("Token check failed".to_string())
        });
        Ok(token.is_ok() && !token.unwrap_or_default().is_empty())
    }
}
