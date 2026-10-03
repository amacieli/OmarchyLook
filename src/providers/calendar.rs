//! Microsoft Graph calendar provider (mirrors providers/graph.rs for mail)
//!
//! Pagination follows @odata.nextLink exactly like fetch_all_folder_messages.

use crate::auth::AuthManager;
use crate::errors::{OmarchyError, Result};
use crate::models::CalendarEvent;
use async_trait::async_trait;
use chrono::{Local, NaiveDate, TimeZone, Utc};
use log::{debug, error};
use tokio::sync::Mutex;

const SELECT: &str = "id,subject,body,start,end,isAllDay,type,seriesMasterId";

#[async_trait]
pub trait CalendarProvider: Send + Sync {
    /// Fetch the most recent events (by start time, newest first)
    async fn fetch_events(&self, limit: usize) -> Result<Vec<CalendarEvent>>;

    /// Fetch ALL events with pagination, streaming batches (~50) to a channel.
    async fn fetch_all_events(
        &self,
        tx: tokio::sync::mpsc::Sender<Vec<CalendarEvent>>,
    ) -> Result<usize>;

    /// Every event overlapping `[from, to)` with recurring series EXPANDED into their individual
    /// occurrences (Graph `calendarView`), following all pages. `/me/events` only returns each
    /// series once, as its master.
    async fn fetch_window(&self, from: NaiveDate, to: NaiveDate) -> Result<Vec<CalendarEvent>>;

    async fn is_token_valid(&self) -> Result<bool>;
}

/// Local midnight of `date` as an RFC 3339 instant with its UTC offset.
fn local_midnight(date: NaiveDate) -> String {
    let naive = date.and_hms_opt(0, 0, 0).expect("midnight is valid");
    match Local.from_local_datetime(&naive) {
        chrono::LocalResult::Single(dt) | chrono::LocalResult::Ambiguous(dt, _) => dt.to_rfc3339(),
        chrono::LocalResult::None => Utc.from_utc_datetime(&naive).to_rfc3339(),
    }
}

/// `calendarView` URL for `[from, to)`. The offsets contain '+', so the instants are percent-encoded.
pub(crate) fn window_url(from: NaiveDate, to: NaiveDate) -> String {
    format!(
        "https://graph.microsoft.com/v1.0/me/calendarView?startDateTime={}&endDateTime={}&$select={}&$top=50&$orderby=start/dateTime",
        urlencoding::encode(&local_midnight(from)),
        urlencoding::encode(&local_midnight(to)),
        SELECT
    )
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
            event_type: ev["type"].as_str().unwrap_or("singleInstance").to_string(),
            series_master_id: ev["seriesMasterId"].as_str().map(|s| s.to_string()),
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

    async fn fetch_window(&self, from: NaiveDate, to: NaiveDate) -> Result<Vec<CalendarEvent>> {
        let token = self.get_token().await?;
        let client = reqwest::Client::new();
        let mut next_url = Some(window_url(from, to));
        let mut all = Vec::new();
        while let Some(url) = next_url.take() {
            let json = self.get_page(&client, &token, &url).await?;
            all.extend(self.parse_page(&json));
            next_url = json["@odata.nextLink"].as_str().map(|s| s.to_string());
            tokio::task::yield_now().await;
        }
        debug!("calendarView {}..{}: {} events", from, to, all.len());
        Ok(all)
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn window_url_encodes_offsets_and_selects_type_fields() {
        let url = window_url(NaiveDate::from_ymd_opt(2026, 10, 1).unwrap(), NaiveDate::from_ymd_opt(2026, 12, 30).unwrap());
        assert!(url.starts_with("https://graph.microsoft.com/v1.0/me/calendarView?startDateTime=2026-10-01T00%3A00%3A00"), "{}", url);
        let query = url.split_once('?').unwrap().1;
        assert!(!query.contains('+'), "a raw '+' would be read as a space: {}", url);
        assert!(url.contains("type,seriesMasterId"));
    }

    #[test]
    fn graph_event_types_are_parsed() {
        let p = GraphCalendarProvider::new(AuthManager::new());
        let occ = p.parse_event(&serde_json::json!({
            "id": "o", "subject": "Standup", "start": {"dateTime": "2026-10-05T09:00:00.0000000", "timeZone": "Eastern Standard Time"},
            "end": {"dateTime": "2026-10-05T09:30:00.0000000"}, "isAllDay": false, "type": "occurrence", "seriesMasterId": "M"
        }));
        assert_eq!((occ.event_type.as_str(), occ.series_master_id.as_deref()), ("occurrence", Some("M")));
        let single = p.parse_event(&serde_json::json!({"id": "s", "start": {"dateTime": "2026-10-05T09:00:00"}, "end": {"dateTime": "2026-10-05T10:00:00"}}));
        assert_eq!(single.event_type, "singleInstance");
    }
}
