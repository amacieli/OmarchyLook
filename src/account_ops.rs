//! Account lifecycle operations used by the HTTP layer: list, add (device-flow
//! login under a fresh `<provider>-<suffix>` id), sign out, remove.

use crate::accounts::{new_account_id, provider_slug};
use crate::auth::{any_account_authenticated, broker_for, AuthManager};
use crate::db::Database;
use crate::errors::{OmarchyError, Result};
use crate::scheduler::{is_supported, SyncScheduler};
use log::{error, info, warn};
use std::collections::HashSet;
use std::path::Path;
use std::sync::{Arc, Mutex, OnceLock};

fn db_path(config_dir: &Path) -> String {
    config_dir.join("messages.db").to_string_lossy().to_string()
}

/// Email address of an account's mailbox via Graph `/me` (User.Read).
pub fn fetch_account_email(account_id: &str) -> Option<String> {
    let token = AuthManager::for_account(account_id).get_token().ok()?;
    let me: serde_json::Value = ureq::get("https://graph.microsoft.com/v1.0/me?$select=mail,userPrincipalName")
        .set("Authorization", &format!("Bearer {}", token))
        .call()
        .ok()?
        .into_json()
        .ok()?;
    me["mail"]
        .as_str()
        .filter(|s| !s.is_empty())
        .or_else(|| me["userPrincipalName"].as_str())
        .map(|s| s.to_string())
}

/// auth_state.json is what the QML auth watcher reads. `is_authenticated` means
/// "at least one account is signed in"; `login_serial` bumps after each completed login.
pub fn write_auth_state(config_dir: &Path, error: Option<&str>, login_serial: Option<u64>) {
    let mut state = serde_json::json!({ "is_authenticated": any_account_authenticated() });
    if let Some(e) = error {
        state["error"] = e.into();
    }
    if let Some(s) = login_serial {
        state["login_serial"] = s.into();
    }
    if let Ok(json) = serde_json::to_string_pretty(&state) {
        let _ = std::fs::write(config_dir.join("auth_state.json"), json);
    }
}

fn now_serial() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

// ───────────────────────────────────────────────────────────── listing

/// JSON for GET /accounts. Rows still missing an email get it resolved in the background.
pub fn accounts_json(config_dir: &Path) -> String {
    let db = match Database::open(&db_path(config_dir)) {
        Ok(db) => db,
        Err(e) => {
            warn!("GET /accounts: DB open failed: {}", e);
            return "[]".to_string();
        }
    };
    let accounts = db.list_accounts().unwrap_or_default();
    let rows: Vec<serde_json::Value> = accounts
        .iter()
        .map(|a| {
            let signed_in = broker_for(&a.id).is_authenticated();
            if signed_in && a.email.as_deref().unwrap_or("").is_empty() {
                resolve_email_in_background(config_dir, &a.id);
            }
            serde_json::json!({
                "id": a.id,
                "provider": a.provider,
                "email": a.email.clone().unwrap_or_default(),
                "signed_in": signed_in,
            })
        })
        .collect();
    serde_json::to_string(&rows).unwrap_or_else(|_| "[]".to_string())
}

fn resolve_email_in_background(config_dir: &Path, account_id: &str) {
    static IN_FLIGHT: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
    let set = IN_FLIGHT.get_or_init(|| Mutex::new(HashSet::new()));
    if !set.lock().unwrap_or_else(|p| p.into_inner()).insert(account_id.to_string()) {
        return;
    }
    let (path, id) = (db_path(config_dir), account_id.to_string());
    std::thread::spawn(move || {
        if let Some(email) = fetch_account_email(&id) {
            if let Ok(db) = Database::open(&path) {
                let _ = db.set_account_email(&id, &email);
            }
        }
        set.lock().unwrap_or_else(|p| p.into_inner()).remove(&id);
    });
}

// ──────────────────────────────────────────────────────────── add account

#[derive(Debug, PartialEq)]
pub enum LoginOutcome {
    /// A new account row was created under the login's id.
    Added(String),
    /// The mailbox already existed but was signed out; its tokens were replaced.
    Rebound(String),
    /// The mailbox is already signed in under another account.
    Duplicate(String),
}

/// Decide what a completed login means. Pure of I/O beyond the DB so it can be tested:
/// `is_signed_in(id)` reports token presence, `move_tokens(from, to)` transfers credentials.
pub fn register_login(
    db: &Database,
    id: &str,
    provider: &str,
    email: Option<&str>,
    is_signed_in: &dyn Fn(&str) -> bool,
    move_tokens: &dyn Fn(&str, &str) -> Result<()>,
) -> Result<LoginOutcome> {
    if let Some(email) = email {
        let existing = db.list_accounts()?.into_iter().find(|a| {
            a.id != id
                && a.provider == provider
                && a.email.as_deref().map(|e| e.eq_ignore_ascii_case(email)).unwrap_or(false)
        });
        if let Some(existing) = existing {
            if is_signed_in(&existing.id) {
                return Ok(LoginOutcome::Duplicate(email.to_string()));
            }
            move_tokens(id, &existing.id)?;
            return Ok(LoginOutcome::Rebound(existing.id));
        }
    }
    db.insert_account(id, provider, email, None, "{}")?;
    Ok(LoginOutcome::Added(id.to_string()))
}

/// Start a device-flow login for a brand-new account. The id is generated here
/// (`<provider>-<suffix>`, even for the first account); the QML polls device_code.json.
pub fn begin_add_account(config_dir: &Path, provider: &str, scheduler: Arc<SyncScheduler>) -> Result<()> {
    let provider = provider_slug(provider);
    if !is_supported(&provider) {
        let msg = format!("{} accounts aren't supported yet", provider);
        write_auth_state(config_dir, Some(&msg), None);
        return Err(OmarchyError::AuthError(msg));
    }
    let id = new_account_id(&provider);
    info!("Adding {} account (pending id {})", provider, id);
    write_auth_state(config_dir, None, None); // clear any stale error

    let dir = config_dir.to_path_buf();
    let mut auth = AuthManager::for_account(&id);
    let cb: Box<dyn FnOnce(&str) + Send> = Box::new(move |id| finish_login(&dir, id, &provider, &scheduler));
    auth.start_device_flow_with_callback(config_dir, Some(cb)).map(|_| ())
}

fn finish_login(config_dir: &Path, id: &str, provider: &str, scheduler: &SyncScheduler) {
    let email = fetch_account_email(id);
    let db = match Database::open(&db_path(config_dir)) {
        Ok(db) => db,
        Err(e) => {
            error!("finish_login: DB open failed: {}", e);
            write_auth_state(config_dir, Some("Signed in, but the account could not be saved"), None);
            return;
        }
    };
    let move_tokens = |from: &str, to: &str| -> Result<()> {
        let snapshot = broker_for(from)
            .snapshot()
            .ok_or_else(|| OmarchyError::TokenError("no tokens to move".into()))?;
        broker_for(to).adopt(&snapshot)?;
        broker_for(from).sign_out()
    };
    match register_login(&db, id, provider, email.as_deref(), &|a| broker_for(a).is_authenticated(), &move_tokens) {
        Ok(LoginOutcome::Added(id)) | Ok(LoginOutcome::Rebound(id)) => {
            scheduler.start_account(&id);
            write_auth_state(config_dir, None, Some(now_serial()));
        }
        Ok(LoginOutcome::Duplicate(email)) => {
            let _ = broker_for(id).sign_out();
            write_auth_state(config_dir, Some(&format!("{} is already signed in", email)), Some(now_serial()));
        }
        Err(e) => {
            error!("finish_login failed: {}", e);
            let _ = broker_for(id).sign_out();
            write_auth_state(config_dir, Some(&format!("Could not add account: {}", e)), Some(now_serial()));
        }
    }
}

// ───────────────────────────────────────────────── sign out / remove

/// Stop syncing and delete the account's tokens. The account and its cached data stay
/// (shown as signed out) so signing in again to the same mailbox resumes without a re-sync.
pub fn sign_out_account(config_dir: &Path, id: &str, scheduler: &SyncScheduler) -> Result<()> {
    scheduler.stop_account(id);
    broker_for(id).sign_out()?;
    write_auth_state(config_dir, None, Some(now_serial()));
    Ok(())
}

/// Sign out every signed-in account (what the legacy logout trigger file means).
pub fn sign_out_all(config_dir: &Path, scheduler: &SyncScheduler) -> Result<usize> {
    let accounts = Database::open(&db_path(config_dir))?.list_accounts()?;
    let mut n = 0;
    for a in accounts.iter().filter(|a| broker_for(&a.id).is_authenticated()) {
        sign_out_account(config_dir, &a.id, scheduler)?;
        n += 1;
    }
    write_auth_state(config_dir, None, Some(now_serial()));
    Ok(n)
}

/// Sign out and delete the account together with everything cached for it.
pub fn remove_account(config_dir: &Path, id: &str, scheduler: &SyncScheduler) -> Result<()> {
    scheduler.stop_account(id);
    broker_for(id).sign_out()?;
    Database::open(&db_path(config_dir))?.delete_account(id)?;
    write_auth_state(config_dir, None, Some(now_serial()));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    fn db() -> Database {
        Database::open(":memory:").unwrap()
    }

    #[test]
    fn new_mailbox_is_added_under_its_login_id() {
        let d = db();
        let out = register_login(&d, "exchange-aaaaaa", "exchange", Some("a@x.com"), &|_| false, &|_, _| Ok(())).unwrap();
        assert_eq!(out, LoginOutcome::Added("exchange-aaaaaa".into()));
        assert_eq!(d.list_accounts().unwrap().len(), 1);
    }

    #[test]
    fn second_account_of_same_provider_gets_its_own_row() {
        let d = db();
        register_login(&d, "exchange-aaaaaa", "exchange", Some("a@x.com"), &|_| true, &|_, _| Ok(())).unwrap();
        let out = register_login(&d, "exchange-bbbbbb", "exchange", Some("b@x.com"), &|_| true, &|_, _| Ok(())).unwrap();
        assert_eq!(out, LoginOutcome::Added("exchange-bbbbbb".into()));
        assert_eq!(d.list_accounts().unwrap().len(), 2);
    }

    #[test]
    fn signing_in_to_an_already_signed_in_mailbox_is_a_duplicate() {
        let d = db();
        register_login(&d, "exchange-aaaaaa", "exchange", Some("a@x.com"), &|_| true, &|_, _| Ok(())).unwrap();
        let out = register_login(&d, "exchange-bbbbbb", "exchange", Some("A@X.com"), &|_| true, &|_, _| Ok(())).unwrap();
        assert_eq!(out, LoginOutcome::Duplicate("A@X.com".into()));
        assert_eq!(d.list_accounts().unwrap().len(), 1, "no second row");
    }

    #[test]
    fn signed_out_mailbox_is_rebound_and_keeps_its_id() {
        let d = db();
        register_login(&d, "exchange-aaaaaa", "exchange", Some("a@x.com"), &|_| true, &|_, _| Ok(())).unwrap();
        let moved = RefCell::new(Vec::new());
        let out = register_login(&d, "exchange-bbbbbb", "exchange", Some("a@x.com"), &|_| false, &|from, to| {
            moved.borrow_mut().push((from.to_string(), to.to_string()));
            Ok(())
        }).unwrap();
        assert_eq!(out, LoginOutcome::Rebound("exchange-aaaaaa".into()));
        assert_eq!(moved.into_inner(), vec![("exchange-bbbbbb".to_string(), "exchange-aaaaaa".to_string())]);
        assert_eq!(d.list_accounts().unwrap().len(), 1);
    }

    #[test]
    fn same_address_on_different_provider_is_a_separate_account() {
        let d = db();
        register_login(&d, "exchange-aaaaaa", "exchange", Some("a@x.com"), &|_| true, &|_, _| Ok(())).unwrap();
        let out = register_login(&d, "outlook-bbbbbb", "outlook", Some("a@x.com"), &|_| true, &|_, _| Ok(())).unwrap();
        assert_eq!(out, LoginOutcome::Added("outlook-bbbbbb".into()));
    }

    #[test]
    fn unknown_email_still_registers_the_account() {
        let d = db();
        let out = register_login(&d, "exchange-aaaaaa", "exchange", None, &|_| false, &|_, _| Ok(())).unwrap();
        assert_eq!(out, LoginOutcome::Added("exchange-aaaaaa".into()));
    }
}
