//! Shared HTTP plumbing for the Google providers (Gmail, Calendar, People).
//!
//! One `GoogleApi` per account and service thread: it owns the account's `AuthManager` (so
//! tokens come from the shared per-account broker) and retries the transient failures Google
//! documents (429, 5xx, per-user rate limits) with exponential backoff.

use crate::auth::AuthManager;
use crate::errors::{OmarchyError, Result};
use log::{debug, error, warn};
use std::time::Duration;
use tokio::sync::Mutex;

const MAX_ATTEMPTS: u32 = 4;

pub struct GoogleApi {
    auth: Mutex<AuthManager>,
    client: reqwest::Client,
}

/// Whether a failed response is worth retrying, from its status and error body.
pub(crate) fn is_retryable(status: u16, body: &str) -> bool {
    match status {
        429 | 500 | 502 | 503 | 504 => true,
        403 => body.contains("rateLimitExceeded") || body.contains("userRateLimitExceeded"),
        _ => false,
    }
}

/// A readable hint for the failures that need action from the user rather than a retry.
pub(crate) fn hint_for(status: u16, body: &str) -> &'static str {
    if status == 403 && (body.contains("accessNotConfigured") || body.contains("SERVICE_DISABLED")) {
        " (this API is not enabled in the Google Cloud project: enable it in APIs & Services → Library)"
    } else if status == 403 && body.contains("insufficientPermissions") {
        " (scope not granted: sign in to this account again)"
    } else {
        ""
    }
}

impl GoogleApi {
    pub fn new(account_id: &str) -> Self {
        Self { auth: Mutex::new(AuthManager::for_account(account_id)), client: reqwest::Client::new() }
    }

    async fn token(&self) -> Result<String> {
        let mut auth = self.auth.lock().await;
        let token = auth
            .get_token()
            .map_err(|e| OmarchyError::AuthError(format!("Failed to get token: {}", e)))?;
        if token.is_empty() {
            return Err(OmarchyError::AuthError("No access token".to_string()));
        }
        Ok(token)
    }

    pub async fn is_token_valid(&self) -> Result<bool> {
        Ok(self.token().await.is_ok())
    }

    pub async fn get(&self, url: &str) -> Result<serde_json::Value> {
        self.send(reqwest::Method::GET, url, None).await
    }

    pub async fn post(&self, url: &str, body: &serde_json::Value) -> Result<serde_json::Value> {
        self.send(reqwest::Method::POST, url, Some(body)).await
    }

    async fn send(&self, method: reqwest::Method, url: &str, body: Option<&serde_json::Value>) -> Result<serde_json::Value> {
        let mut attempt = 0;
        loop {
            attempt += 1;
            let token = self.token().await?;
            let mut req = self.client.request(method.clone(), url).bearer_auth(token);
            if let Some(b) = body {
                req = req.json(b);
            }
            let resp = match req.send().await {
                Ok(r) => r,
                Err(e) if attempt < MAX_ATTEMPTS => {
                    warn!("Google API request failed ({}), retrying", e);
                    tokio::time::sleep(Duration::from_secs(1 << (attempt - 1))).await;
                    continue;
                }
                Err(e) => return Err(OmarchyError::HttpError(e.to_string())),
            };
            let status = resp.status();
            let text = resp.text().await.map_err(|e| OmarchyError::HttpError(e.to_string()))?;
            if status.is_success() {
                if text.trim().is_empty() {
                    return Ok(serde_json::Value::Null);
                }
                return serde_json::from_str(&text).map_err(|e| OmarchyError::HttpError(format!("bad JSON from Google: {}", e)));
            }
            if attempt < MAX_ATTEMPTS && is_retryable(status.as_u16(), &text) {
                let wait = Duration::from_secs(1 << (attempt - 1));
                debug!("Google API {} — retrying in {:?}", status, wait);
                tokio::time::sleep(wait).await;
                continue;
            }
            error!("Google API {} for {}: {}", status, url.split('?').next().unwrap_or(url), text);
            return Err(OmarchyError::HttpError(format!("Google API error: {}{} — {}", status, hint_for(status.as_u16(), &text), text)));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_transient_failures_are_retried() {
        assert!(is_retryable(429, ""));
        assert!(is_retryable(503, ""));
        assert!(is_retryable(403, r#"{"error":{"errors":[{"reason":"userRateLimitExceeded"}]}}"#));
        assert!(!is_retryable(403, r#"{"error":{"errors":[{"reason":"insufficientPermissions"}]}}"#));
        assert!(!is_retryable(401, ""));
        assert!(!is_retryable(404, ""));
    }

    #[test]
    fn disabled_api_gets_an_actionable_hint() {
        assert!(hint_for(403, r#"{"status":"PERMISSION_DENIED","reason":"SERVICE_DISABLED"}"#).contains("not enabled"));
        assert!(hint_for(403, "accessNotConfigured").contains("Library"));
        assert_eq!(hint_for(404, ""), "");
    }
}
