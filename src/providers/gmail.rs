//! Gmail provider (Gmail REST API v1) behind the same `EmailProvider` trait as Graph.
//!
//! Mapping: labels play the role of folders (system INBOX/SENT/DRAFT/TRASH/SPAM plus the
//! user's own labels); a message is stored once, under the first folder that lists it.
//! Gmail ids are only unique per mailbox, so every id leaving this module is
//! `<account id>:<gmail id>` (see `accounts::scoped`).
//!
//! Pagination mirrors Graph: ids are listed page by page (`nextPageToken`), ids already in the
//! cache are skipped *before* the expensive per-message fetch, and each page's new messages
//! are streamed to the daemon through the channel.

use super::google_api::GoogleApi;
use crate::accounts::{scoped, unscoped};
use crate::errors::Result;
use crate::models::{EmailMessage, MailFolder};
use async_trait::async_trait;
use base64::Engine;
use log::{debug, warn};
use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::Arc;

const BASE: &str = "https://gmail.googleapis.com/gmail/v1/users/me";
const PAGE_SIZE: usize = 100;
/// Concurrent `messages.get` calls (Gmail allows ~50/s per user; this stays far below).
const FETCH_CONCURRENCY: usize = 10;

/// System labels shown as folders, with the Graph-style well-known name that drives ordering.
const SYSTEM_FOLDERS: &[(&str, &str, &str)] = &[
    ("INBOX", "Inbox", "inbox"),
    ("DRAFT", "Drafts", "drafts"),
    ("SENT", "Sent", "sentitems"),
    ("TRASH", "Trash", "deleteditems"),
    ("SPAM", "Spam", "junkemail"),
];

pub struct GmailProvider {
    account_id: String,
    api: Arc<GoogleApi>,
    /// Cache database, used only to skip messages that are already stored.
    db_path: Option<PathBuf>,
}

// ───────────────────────────────────────────────────────────── pure parsing

/// `"Name" <a@b.com>` / `a@b.com` → `a@b.com`
pub(crate) fn address_of(from_header: &str) -> String {
    let h = from_header.trim();
    match (h.rfind('<'), h.rfind('>')) {
        (Some(l), Some(r)) if l < r => h[l + 1..r].trim().to_string(),
        _ => h.trim_matches('"').to_string(),
    }
}

fn header<'a>(msg: &'a serde_json::Value, name: &str) -> Option<&'a str> {
    msg["payload"]["headers"].as_array()?.iter().find_map(|h| {
        h["name"].as_str().filter(|n| n.eq_ignore_ascii_case(name)).and_then(|_| h["value"].as_str())
    })
}

/// Gmail message resource (format=metadata) → `EmailMessage` stored under `folder_id`.
pub(crate) fn parse_message(account_id: &str, folder_id: &str, msg: &serde_json::Value) -> Option<EmailMessage> {
    let raw_id = msg["id"].as_str().filter(|s| !s.is_empty())?;
    let received = msg["internalDate"]
        .as_str()
        .and_then(|ms| ms.parse::<i64>().ok())
        .and_then(chrono::DateTime::<chrono::Utc>::from_timestamp_millis)
        .map(|d| d.format("%Y-%m-%dT%H:%M:%SZ").to_string())
        .unwrap_or_else(|| chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string());
    let unread = msg["labelIds"].as_array().map(|l| l.iter().any(|x| x == "UNREAD")).unwrap_or(false);
    Some(EmailMessage {
        id: scoped(account_id, raw_id),
        from: header(msg, "From").map(address_of).filter(|s| !s.is_empty()).unwrap_or_else(|| "unknown@example.com".into()),
        subject: header(msg, "Subject").map(str::trim).filter(|s| !s.is_empty()).unwrap_or("(no subject)").to_string(),
        received,
        body: msg["snippet"].as_str().unwrap_or("").to_string(),
        folder_id: Some(folder_id.to_string()),
        is_read: !unread,
    })
}

/// Folders from `labels.list` (`counts` supplies per-label totals from `labels.get`).
pub(crate) fn parse_labels(account_id: &str, labels: &serde_json::Value, counts: &dyn Fn(&str) -> (Option<i32>, Option<i32>)) -> Vec<MailFolder> {
    let mut out = Vec::new();
    for l in labels["labels"].as_array().cloned().unwrap_or_default() {
        let (Some(id), Some(name)) = (l["id"].as_str(), l["name"].as_str()) else { continue };
        let folder = if let Some((_, display, wk)) = SYSTEM_FOLDERS.iter().find(|(sid, _, _)| *sid == id) {
            Some((display.to_string(), Some(wk.to_string())))
        } else if l["type"].as_str() == Some("user") {
            Some((name.to_string(), None))
        } else {
            None // CATEGORY_*, STARRED, IMPORTANT, UNREAD, CHAT ... are views, not folders
        };
        if let Some((display_name, well_known_name)) = folder {
            let (unread, total) = counts(id);
            out.push(MailFolder {
                id: scoped(account_id, id),
                display_name,
                parent_folder_id: None,
                unread_item_count: unread,
                total_item_count: total,
                well_known_name,
            });
        }
    }
    out
}

/// Best body of a `format=full` message: HTML if present, else plain text.
pub(crate) fn extract_body(payload: &serde_json::Value) -> (String, String) {
    fn walk(p: &serde_json::Value, html: &mut Option<String>, text: &mut Option<String>) {
        let mime = p["mimeType"].as_str().unwrap_or("");
        if let Some(data) = p["body"]["data"].as_str() {
            let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
                .decode(data.trim_end_matches('='))
                .ok()
                .map(|b| String::from_utf8_lossy(&b).into_owned());
            if let Some(d) = decoded {
                if mime == "text/html" && html.is_none() { *html = Some(d); }
                else if mime == "text/plain" && text.is_none() { *text = Some(d); }
            }
        }
        for part in p["parts"].as_array().into_iter().flatten() {
            walk(part, html, text);
        }
    }
    let (mut html, mut text) = (None, None);
    walk(payload, &mut html, &mut text);
    match (html, text) {
        (Some(h), _) => ("html".into(), h),
        (None, Some(t)) => ("text".into(), t),
        _ => ("text".into(), String::new()),
    }
}

// ─────────────────────────────────────────────────────────────── provider

impl GmailProvider {
    pub fn new(account_id: &str, db_path: Option<PathBuf>) -> Self {
        Self { account_id: account_id.to_string(), api: Arc::new(GoogleApi::new(account_id)), db_path }
    }

    fn label_of(&self, folder_id: &str) -> String {
        let raw = unscoped(&self.account_id, folder_id);
        if raw.eq_ignore_ascii_case("inbox") { "INBOX".to_string() } else { raw.to_string() }
    }

    /// Subset of `ids` (scoped) that is already cached.
    fn known(&self, ids: &[String]) -> HashSet<String> {
        match &self.db_path {
            Some(p) => crate::db::known_message_ids(p, ids),
            None => HashSet::new(),
        }
    }

    /// One page of message ids for a label: (raw ids, next page token).
    async fn list_page(&self, label: &str, unread_only: bool, page_token: Option<&str>, max: usize) -> Result<(Vec<String>, Option<String>)> {
        let mut url = format!("{}/messages?labelIds={}&maxResults={}&includeSpamTrash=true", BASE, urlencoding::encode(label), max);
        if unread_only {
            url.push_str("&labelIds=UNREAD");
        }
        if let Some(t) = page_token {
            url.push_str(&format!("&pageToken={}", urlencoding::encode(t)));
        }
        let json = self.api.get(&url).await?;
        let ids = json["messages"].as_array().into_iter().flatten().filter_map(|m| m["id"].as_str().map(String::from)).collect();
        Ok((ids, json["nextPageToken"].as_str().map(String::from)))
    }

    /// Metadata for each raw id, a few requests at a time. A message that fails is skipped
    /// (it is retried next sync, because it never became "known").
    async fn fetch_metadata(&self, folder_id: &str, raw_ids: Vec<String>) -> Vec<EmailMessage> {
        let mut out = Vec::with_capacity(raw_ids.len());
        for chunk in raw_ids.chunks(FETCH_CONCURRENCY) {
            let mut set = tokio::task::JoinSet::new();
            for id in chunk {
                let api = Arc::clone(&self.api);
                let url = format!(
                    "{}/messages/{}?format=metadata&metadataHeaders=From&metadataHeaders=Subject",
                    BASE, urlencoding::encode(id)
                );
                set.spawn(async move { api.get(&url).await });
            }
            while let Some(res) = set.join_next().await {
                match res {
                    Ok(Ok(json)) => out.extend(parse_message(&self.account_id, folder_id, &json)),
                    Ok(Err(e)) => warn!("Gmail: skipping a message that could not be fetched: {}", e),
                    Err(e) => warn!("Gmail: fetch task failed: {}", e),
                }
            }
        }
        out
    }

    /// New (not yet cached) messages among `raw_ids`.
    async fn new_messages(&self, folder_id: &str, raw_ids: Vec<String>) -> Vec<EmailMessage> {
        let scoped_ids: Vec<String> = raw_ids.iter().map(|r| scoped(&self.account_id, r)).collect();
        let known = self.known(&scoped_ids);
        let fresh: Vec<String> = raw_ids.into_iter().filter(|r| !known.contains(&scoped(&self.account_id, r))).collect();
        if fresh.is_empty() { return Vec::new(); }
        self.fetch_metadata(folder_id, fresh).await
    }

    /// Full body of one message: (content type "html"|"text", content).
    pub async fn fetch_message_body(&self, id: &str) -> Result<(String, String)> {
        let raw = unscoped(&self.account_id, id);
        let json = self.api.get(&format!("{}/messages/{}?format=full", BASE, urlencoding::encode(raw))).await?;
        Ok(extract_body(&json["payload"]))
    }
}

#[async_trait]
impl super::EmailProvider for GmailProvider {
    async fn fetch_inbox(&self, limit: usize) -> Result<Vec<EmailMessage>> {
        self.fetch_folder_messages("INBOX", limit).await
    }

    async fn fetch_folder_messages(&self, folder_id: &str, limit: usize) -> Result<Vec<EmailMessage>> {
        let label = self.label_of(folder_id);
        let scoped_folder = scoped(&self.account_id, &label);
        let (ids, _) = self.list_page(&label, false, None, limit.clamp(1, 500)).await?;
        Ok(self.new_messages(&scoped_folder, ids).await)
    }

    async fn fetch_all_folder_messages(&self, folder_id: &str, tx: tokio::sync::mpsc::Sender<Vec<EmailMessage>>) -> Result<usize> {
        let label = self.label_of(folder_id);
        let scoped_folder = scoped(&self.account_id, &label);
        let (mut total, mut token) = (0usize, None::<String>);
        loop {
            let (ids, next) = self.list_page(&label, false, token.as_deref(), PAGE_SIZE).await?;
            let batch = self.new_messages(&scoped_folder, ids).await;
            total += batch.len();
            if !batch.is_empty() && tx.send(batch).await.is_err() {
                debug!("Gmail pagination receiver dropped, stopping");
                break;
            }
            match next {
                Some(t) => token = Some(t),
                None => break,
            }
            tokio::task::yield_now().await;
        }
        debug!("Gmail label {}: {} new messages", label, total);
        Ok(total)
    }

    async fn fetch_unread_ids(&self, folder_id: &str) -> Result<Vec<String>> {
        let label = self.label_of(folder_id);
        let (mut all, mut token) = (Vec::new(), None::<String>);
        loop {
            // Any failed page aborts: a partial list must not be treated as authoritative.
            let (ids, next) = self.list_page(&label, true, token.as_deref(), 500).await?;
            all.extend(ids.into_iter().map(|r| scoped(&self.account_id, &r)));
            match next {
                Some(t) => token = Some(t),
                None => return Ok(all),
            }
        }
    }

    async fn set_message_read(&self, id: &str, is_read: bool) -> Result<()> {
        let raw = unscoped(&self.account_id, id);
        let body = if is_read {
            serde_json::json!({"removeLabelIds": ["UNREAD"]})
        } else {
            serde_json::json!({"addLabelIds": ["UNREAD"]})
        };
        self.api.post(&format!("{}/messages/{}/modify", BASE, urlencoding::encode(raw)), &body).await.map(|_| ())
    }

    async fn fetch_folders(&self) -> Result<Vec<MailFolder>> {
        let labels = self.api.get(&format!("{}/labels", BASE)).await?;
        // Counts need one `labels.get` per shown label; fetch them up front.
        let mut counts = std::collections::HashMap::new();
        for l in labels["labels"].as_array().into_iter().flatten() {
            let Some(id) = l["id"].as_str() else { continue };
            let shown = SYSTEM_FOLDERS.iter().any(|(s, _, _)| *s == id) || l["type"].as_str() == Some("user");
            if !shown { continue; }
            match self.api.get(&format!("{}/labels/{}", BASE, urlencoding::encode(id))).await {
                Ok(d) => {
                    counts.insert(id.to_string(), (d["messagesUnread"].as_i64().map(|n| n as i32), d["messagesTotal"].as_i64().map(|n| n as i32)));
                }
                Err(e) => warn!("Gmail: no counts for label {}: {}", id, e),
            }
        }
        Ok(parse_labels(&self.account_id, &labels, &|id| counts.get(id).copied().unwrap_or((None, None))))
    }

    async fn is_token_valid(&self) -> Result<bool> {
        self.api.is_token_valid().await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn from_header_forms() {
        assert_eq!(address_of("Ada Lovelace <ada@example.com>"), "ada@example.com");
        assert_eq!(address_of("\"Doe, J\" <j@x.org>"), "j@x.org");
        assert_eq!(address_of("plain@x.org"), "plain@x.org");
        assert_eq!(address_of("<only@x.org>"), "only@x.org");
    }

    #[test]
    fn metadata_becomes_a_scoped_message() {
        let msg = json!({
            "id": "18f3a", "labelIds": ["INBOX", "UNREAD"], "snippet": "hello there", "internalDate": "1790000000000",
            "payload": {"headers": [{"name": "From", "value": "Ada <ada@example.com>"}, {"name": "subject", "value": " Lunch? "}]}
        });
        let m = parse_message("gmail-aaaaaa", "gmail-aaaaaa:INBOX", &msg).unwrap();
        assert_eq!(m.id, "gmail-aaaaaa:18f3a");
        assert_eq!((m.from.as_str(), m.subject.as_str(), m.body.as_str()), ("ada@example.com", "Lunch?", "hello there"));
        assert!(!m.is_read);
        assert_eq!(m.folder_id.as_deref(), Some("gmail-aaaaaa:INBOX"));
        assert!(m.received.ends_with('Z') && m.received.starts_with("2026-"), "{}", m.received);
        // read when UNREAD is absent; missing headers get safe defaults; no id → no message
        let read = parse_message("a-1", "f", &json!({"id": "x", "labelIds": ["INBOX"]})).unwrap();
        assert!(read.is_read);
        assert_eq!((read.subject.as_str(), read.from.as_str()), ("(no subject)", "unknown@example.com"));
        assert!(parse_message("a-1", "f", &json!({})).is_none());
    }

    #[test]
    fn same_gmail_id_in_two_accounts_stays_distinct() {
        let msg = json!({"id": "same"});
        let a = parse_message("gmail-aaaaaa", "f", &msg).unwrap();
        let b = parse_message("gmail-bbbbbb", "f", &msg).unwrap();
        assert_ne!(a.id, b.id);
    }

    #[test]
    fn labels_map_to_folders_and_hide_views() {
        let labels = json!({"labels": [
            {"id": "INBOX", "name": "INBOX", "type": "system"},
            {"id": "SENT", "name": "SENT", "type": "system"},
            {"id": "STARRED", "name": "STARRED", "type": "system"},
            {"id": "CATEGORY_PROMOTIONS", "name": "CATEGORY_PROMOTIONS", "type": "system"},
            {"id": "Label_7", "name": "Receipts/2026", "type": "user"},
        ]});
        let f = parse_labels("gmail-aaaaaa", &labels, &|id| if id == "INBOX" { (Some(3), Some(120)) } else { (None, None) });
        let ids: Vec<_> = f.iter().map(|x| x.id.as_str()).collect();
        assert_eq!(ids, ["gmail-aaaaaa:INBOX", "gmail-aaaaaa:SENT", "gmail-aaaaaa:Label_7"]);
        assert_eq!(f[0].well_known_name.as_deref(), Some("inbox"));
        assert_eq!((f[0].unread_item_count, f[0].total_item_count), (Some(3), Some(120)));
        assert_eq!(f[2].display_name, "Receipts/2026");
        assert_eq!(f[2].well_known_name, None);
    }

    #[test]
    fn body_prefers_html_and_walks_nested_parts() {
        let enc = |s: &str| base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(s);
        let payload = json!({"mimeType": "multipart/mixed", "parts": [
            {"mimeType": "multipart/alternative", "parts": [
                {"mimeType": "text/plain", "body": {"data": enc("plain")}},
                {"mimeType": "text/html", "body": {"data": enc("<b>rich</b>")}},
            ]},
            {"mimeType": "application/pdf", "body": {"attachmentId": "x"}},
        ]});
        assert_eq!(extract_body(&payload), ("html".to_string(), "<b>rich</b>".to_string()));
        let only_text = json!({"mimeType": "text/plain", "body": {"data": enc("just text ✓")}});
        assert_eq!(extract_body(&only_text), ("text".to_string(), "just text ✓".to_string()));
        assert_eq!(extract_body(&json!({})).1, "");
    }
}
