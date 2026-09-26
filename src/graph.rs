//! Microsoft Graph API client (sync, blocking)

use crate::errors::{OmarchyError, Result};
use crate::models::Message;
use log::{debug, info};

const GRAPH_API_BASE: &str = "https://graph.microsoft.com/v1.0";

pub struct GraphClient {
    access_token: String,
}

impl GraphClient {
    pub fn new(access_token: String) -> Self {
        Self { access_token }
    }
    
    /// Fetch recent messages (inbox)
    pub fn get_messages(&self, limit: u32) -> Result<Vec<Message>> {
        debug!("Fetching {} messages from Graph API", limit);
        
        let url = format!(
            "{}/me/mailFolders/inbox/messages?$top={}&$orderby=receivedDateTime desc&$select=id,subject,from,toRecipients,body,receivedDateTime,sentDateTime,isRead,hasAttachments",
            GRAPH_API_BASE, limit
        );
        
        let resp = ureq::get(&url)
            .set("Authorization", &format!("Bearer {}", self.access_token))
            .call()
            .map_err(|e| OmarchyError::HttpError(e.to_string()))?;
        
        if resp.status() < 200 || resp.status() >= 300 {
            return Err(OmarchyError::HttpError(
                format!("Graph API error {}: {}", resp.status(), resp.into_string().unwrap_or_default())
            ));
        }
        
        #[derive(serde::Deserialize)]
        struct MessageResponse {
            value: Vec<Message>,
        }
        
        let msg_resp: MessageResponse = resp
            .into_json()
            .map_err(|e| OmarchyError::HttpError(e.to_string()))?;
        
        info!("Fetched {} messages from Graph API", msg_resp.value.len());
        Ok(msg_resp.value)
    }
    
    /// Get message body (full content)
    pub fn get_message(&self, message_id: &str) -> Result<Message> {
        debug!("Fetching full message: {}", message_id);
        
        let url = format!("{}/me/messages/{}", GRAPH_API_BASE, message_id);
        
        let resp = ureq::get(&url)
            .set("Authorization", &format!("Bearer {}", self.access_token))
            .call()
            .map_err(|e| OmarchyError::HttpError(e.to_string()))?;
        
        if resp.status() < 200 || resp.status() >= 300 {
            return Err(OmarchyError::HttpError(
                format!("Graph API error {}", resp.status())
            ));
        }
        
        resp.into_json()
            .map_err(|e| OmarchyError::HttpError(e.to_string()))
    }
    
    /// Mark message as read
    pub fn mark_read(&self, message_id: &str) -> Result<()> {
        debug!("Marking message as read: {}", message_id);
        
        let url = format!("{}/me/messages/{}", GRAPH_API_BASE, message_id);
        let body = r#"{"isRead": true}"#;
        
        let resp = ureq::patch(&url)
            .set("Authorization", &format!("Bearer {}", self.access_token))
            .set("Content-Type", "application/json")
            .send_string(body)
            .map_err(|e| OmarchyError::HttpError(e.to_string()))?;
        
        if resp.status() < 200 || resp.status() >= 300 {
            return Err(OmarchyError::HttpError(
                format!("Failed to mark message as read: {}", resp.status())
            ));
        }
        
        Ok(())
    }
    
    /// Search messages by keyword
    pub fn search_messages(&self, query: &str, limit: u32) -> Result<Vec<Message>> {
        debug!("Searching messages: {}", query);
        
        // Use Graph API's search-mailItems endpoint
        let url = format!(
            "{}/me/messages?$search=\"{}\"&$top={}&$orderby=receivedDateTime desc",
            GRAPH_API_BASE, urlencoding::encode(query), limit
        );
        
        let resp = ureq::get(&url)
            .set("Authorization", &format!("Bearer {}", self.access_token))
            .call()
            .map_err(|e| OmarchyError::HttpError(e.to_string()))?;
        
        if resp.status() < 200 || resp.status() >= 300 {
            return Err(OmarchyError::HttpError(
                format!("Search failed: {}", resp.status())
            ));
        }
        
        #[derive(serde::Deserialize)]
        struct MessageResponse {
            value: Vec<Message>,
        }
        
        let msg_resp: MessageResponse = resp
            .into_json()
            .map_err(|e| OmarchyError::HttpError(e.to_string()))?;
        
        Ok(msg_resp.value)
    }
    
    /// Create and send a message
    pub fn send_mail(&self, to: &[&str], subject: &str, body: &str) -> Result<String> {
        debug!("Sending mail to {} recipients", to.len());
        
        let to_recipients: Vec<_> = to.iter()
            .map(|addr| serde_json::json!({
                "emailAddress": {
                    "address": addr
                }
            }))
            .collect();
        
        let payload = serde_json::json!({
            "message": {
                "subject": subject,
                "body": {
                    "contentType": "HTML",
                    "content": body
                },
                "toRecipients": to_recipients
            }
        });
        
        let url = format!("{}/me/sendMail", GRAPH_API_BASE);
        
        let resp = ureq::post(&url)
            .set("Authorization", &format!("Bearer {}", self.access_token))
            .set("Content-Type", "application/json")
            .send_json(&payload)
            .map_err(|e| OmarchyError::HttpError(e.to_string()))?;
        
        if resp.status() < 200 || resp.status() >= 300 {
            return Err(OmarchyError::HttpError(
                format!("Failed to send mail: {}", resp.status())
            ));
        }
        
        info!("Mail sent successfully");
        Ok("sent".to_string())
    }
}
