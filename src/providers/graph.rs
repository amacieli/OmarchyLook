//! Microsoft Graph API email provider implementation

use crate::errors::Result;
use crate::models::{EmailMessage, MailFolder};
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

    /// Internal: get a valid access token
    async fn get_token(&self) -> Result<String> {
        let mut auth = self.auth.lock().await;
        let token = auth.get_token().map_err(|e| {
            crate::errors::OmarchyError::AuthError(format!("Failed to get token: {}", e))
        })?;
        if token.is_empty() {
            return Err(crate::errors::OmarchyError::AuthError("No access token".to_string()));
        }
        Ok(token)
    }

    /// Internal: handle non-2xx responses with full body logging
    async fn check_response(response: reqwest::Response) -> Result<String> {
        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            error!("Graph API returned status: {}", status);
            error!("Graph API error body: {}", body);
            return Err(crate::errors::OmarchyError::HttpError(format!(
                "Graph API error: {} — {}",
                status, body
            )));
        }
        let text = response.text().await
            .map_err(|e| crate::errors::OmarchyError::HttpError(e.to_string()))?;
        Ok(text)
    }
}

#[async_trait]
impl super::EmailProvider for GraphEmailProvider {
    /// Fetch emails from a specific folder (defaults to inbox)
    async fn fetch_inbox(&self, limit: usize) -> Result<Vec<EmailMessage>> {
        self.fetch_folder_messages("inbox", limit).await
    }

    async fn fetch_folder_messages(&self, folder_id: &str, limit: usize) -> Result<Vec<EmailMessage>> {
        debug!("Fetching {} emails from Graph API folder: {}", limit, folder_id);
        let token = self.get_token().await?;
        let client = reqwest::Client::new();

        // Use well-known names directly OR folder IDs
        let url = format!(
            "https://graph.microsoft.com/v1.0/me/mailFolders/{}/messages?\
             $top={}&$select=id,subject,from,receivedDateTime,bodyPreview,isRead,parentFolderId",
            folder_id, limit
        );

        let response = client
            .get(&url)
            .header("Authorization", format!("Bearer {}", token))
            .send()
            .await
            .map_err(|e| crate::errors::OmarchyError::HttpError(e.to_string()))?;

        let body = Self::check_response(response).await?;
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
                let from = msg["from"]["emailAddress"]["address"]
                    .as_str()
                    .unwrap_or("unknown@example.com")
                    .to_string();
                let preview = msg["bodyPreview"].as_str().unwrap_or("").to_string();
                let parent_folder_id = msg["parentFolderId"].as_str().map(|s| s.to_string());

                emails.push(EmailMessage {
                    id,
                    from,
                    subject,
                    received,
                    body: preview,
                    folder_id: parent_folder_id,
                });
            }
        }

        debug!("Fetched {} emails from folder {}", emails.len(), folder_id);
        Ok(emails)
    }

    /// Fetch all mail folders from Graph API
    async fn fetch_folders(&self) -> Result<Vec<MailFolder>> {
        debug!("Fetching mail folders from Graph API");
        let token = self.get_token().await?;
        let client = reqwest::Client::new();

        // Fetch top-level folders including well-known names
        let url = "https://graph.microsoft.com/v1.0/me/mailFolders?\
                   $top=100&$select=id,displayName,parentFolderId,unreadItemCount,totalItemCount"
            .to_string();

        let response = client
            .get(&url)
            .header("Authorization", format!("Bearer {}", token))
            .send()
            .await
            .map_err(|e| crate::errors::OmarchyError::HttpError(e.to_string()))?;

        let body = Self::check_response(response).await?;
        let json: serde_json::Value = serde_json::from_str(&body)
            .map_err(|e| crate::errors::OmarchyError::HttpError(e.to_string()))?;

        let mut folders = Vec::new();
        if let Some(values) = json["value"].as_array() {
            for f in values {
                folders.push(MailFolder {
                    id:                f["id"].as_str().unwrap_or("").to_string(),
                    display_name:      f["displayName"].as_str().unwrap_or("").to_string(),
                    parent_folder_id:  f["parentFolderId"].as_str().map(|s| s.to_string()),
                    unread_item_count: f["unreadItemCount"].as_i64().map(|n| n as i32),
                    total_item_count:  f["totalItemCount"].as_i64().map(|n| n as i32),
                    well_known_name:   f["wellKnownName"].as_str()
                                        .filter(|s| !s.is_empty())
                                        .map(|s| s.to_string()),
                });
            }
        }

        debug!("Fetched {} folders", folders.len());
        Ok(folders)
    }

    async fn is_token_valid(&self) -> Result<bool> {
        let mut auth = self.auth.lock().await;
        let token = auth.get_token().map_err(|_| {
            crate::errors::OmarchyError::AuthError("Token check failed".to_string())
        });
        Ok(token.is_ok() && !token.unwrap_or_default().is_empty())
    }
}
