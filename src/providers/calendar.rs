//! Microsoft Graph calendar provider (mirrors providers/graph.rs for mail)
//!
//! Pagination follows @odata.nextLink exactly like fetch_all_folder_messages.

use crate::auth::AuthManager;
use crate::errors::{OmarchyError, Result};
use crate::models::CalendarEvent;
use async_trait::async_trait;
use log::{debug, error};
use tokio::sync::Mutex;

const SELECT: &str = "id,subject,body,start,end,isAllDay";

#[async_trait]
pub trait CalendarProvider: Send + Sync {
    /// Fetch the most recent events (by start time, newest first)
    async fn fetch_events(&self, limit: usize) -> Result<Vec<CalendarEvent>>;

    /// Fetch ALL events with pagination, streaming batches (~50) to a channel.
    async fn fetch_all_events(
        &self,
        tx: tokio::sync::mpsc::Sender<Vec<CalendarEvent>>,
    ) -> Result<usize>;

    async fn is_token_valid(&self) -> Result<bool>;
}

pub struct GraphCalendarProvider {
    auth: Mutex<AuthManager>,
    /// IANA zone requested from Graph so start/end arrive as local wall-clock
    time_zone: String,
}

impl GraphCalendarProvider {
    pub fn new(auth: AuthManager) -> Self {
        Self { auth: Mutex::new(auth), time_zone: local_time_zone() }
    }

    async fn get_token(&self) -> Result<String> {
        let mut auth = self.auth.lock().await;
        let token = auth
            .get_token()
            .map_err(|e| OmarchyError::AuthError(format!("Failed to get token: {}", e)))?;
        if token.is_empty() {
            return Err(OmarchyError::AuthError("No access token".to_string()));
        }
        Ok(token)
    }

    async fn get_page(&self, client: &reqwest::Client, token: &str, url: &str) -> Result<serde_json::Value> {
        let response = client
            .get(url)
            .header("Authorization", format!("Bearer {}", token))
            // local-time start/end + plain-text body
            .header(
                "Prefer",
                format!("outlook.timezone=\"{}\", outlook.body-content-type=\"text\"", self.time_zone),
            )
            .send()
            .await
            .map_err(|e| OmarchyError::HttpError(e.to_string()))?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            error!("Graph calendar API returned status: {}", status);
            error!("Graph calendar API error body: {}", body);
            return Err(OmarchyError::HttpError(format!("Graph API error: {} — {}", status, body)));
        }
        let text = response.text().await.map_err(|e| OmarchyError::HttpError(e.to_string()))?;
        serde_json::from_str(&text).map_err(|e| OmarchyError::HttpError(e.to_string()))
    }

    fn parse_event(&self, ev: &serde_json::Value) -> CalendarEvent {
        // Graph returns "2026-10-03T09:00:00.0000000" — keep "YYYY-MM-DDTHH:MM:SS"
        let stamp = |v: &serde_json::Value| -> String {
            v["dateTime"].as_str().unwrap_or("").chars().take(19).collect()
        };
        CalendarEvent {
            id: ev["id"].as_str().unwrap_or("").to_string(),
            subject: ev["subject"].as_str().unwrap_or("(no title)").to_string(),
            body: ev["body"]["content"].as_str().unwrap_or("").to_string(),
            start: stamp(&ev["start"]),
            end: stamp(&ev["end"]),
            is_all_day: ev["isAllDay"].as_bool().unwrap_or(false),
            time_zone: ev["start"]["timeZone"].as_str().unwrap_or(&self.time_zone).to_string(),
        }
    }

    fn parse_page(&self, json: &serde_json::Value) -> Vec<CalendarEvent> {
        json["value"]
            .as_array()
            .map(|vals| vals.iter().map(|v| self.parse_event(v)).filter(|e| !e.id.is_empty() && !e.start.is_empty()).collect())
            .unwrap_or_default()
    }
}

#[async_trait]
impl CalendarProvider for GraphCalendarProvider {
    async fn fetch_events(&self, limit: usize) -> Result<Vec<CalendarEvent>> {
        debug!("Fetching {} calendar events from Graph API", limit);
        let token = self.get_token().await?;
        let client = reqwest::Client::new();
        let url = format!(
            "https://graph.microsoft.com/v1.0/me/events?$top={}&$select={}&$orderby=start/dateTime desc",
            limit, SELECT
        );
        let json = self.get_page(&client, &token, &url).await?;
        Ok(self.parse_page(&json))
    }

    async fn fetch_all_events(
        &self,
        tx: tokio::sync::mpsc::Sender<Vec<CalendarEvent>>,
    ) -> Result<usize> {
        let token = self.get_token().await?;
        let client = reqwest::Client::new();

        let mut next_url = Some(format!(
            "https://graph.microsoft.com/v1.0/me/events?$top=50&$select={}&$orderby=start/dateTime desc",
            SELECT
        ));
        let mut total = 0usize;

        while let Some(url) = next_url.take() {
            let json = self.get_page(&client, &token, &url).await?;
            let batch = self.parse_page(&json);
            total += batch.len();

            if !batch.is_empty() && tx.send(batch).await.is_err() {
                debug!("Calendar pagination receiver dropped, stopping");
                break;
            }

            next_url = json["@odata.nextLink"].as_str().map(|s| s.to_string());
            tokio::task::yield_now().await;
        }

        debug!("Completed full calendar sync: {} events total", total);
        Ok(total)
    }

    async fn is_token_valid(&self) -> Result<bool> {
        let mut auth = self.auth.lock().await;
        let token = auth
            .get_token()
            .map_err(|_| OmarchyError::AuthError("Token check failed".to_string()));
        Ok(token.is_ok() && !token.unwrap_or_default().is_empty())
    }
}

/// IANA time zone of this machine (from the /etc/localtime symlink), else UTC.
fn local_time_zone() -> String {
    std::fs::read_link("/etc/localtime")
        .ok()
        .and_then(|p| {
            let s = p.to_string_lossy().to_string();
            s.split_once("zoneinfo/").map(|(_, tz)| tz.to_string())
        })
        .filter(|tz| !tz.is_empty())
        .unwrap_or_else(|| "UTC".to_string())
}
