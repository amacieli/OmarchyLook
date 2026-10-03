//! Account identity.
//!
//! Every account id has the form `<provider>-<6 hex chars>` (e.g.
//! `exchange-3f9a1c`, `gmail-07be42`), including the first account a user
//! adds. The only exception is `exchange-primary` (`token_store::DEFAULT_ACCOUNT`):
//! the id given to the account that existed before multi-account support, so
//! its keyring entry and data keep working. It is never generated for new accounts.
//!
//! Ids are opaque and stable: they never encode the email address (addresses
//! can change and would leak into keyring labels). Uniqueness of the mailbox
//! itself is enforced by `UNIQUE(provider, email)` in the `accounts` table.
//!
//! Provider-supplied row ids (message / folder / event ids) share one table
//! namespace across accounts. Graph ids are globally unique; providers whose
//! ids are only unique per mailbox (IMAP UIDs, folder names like "INBOX")
//! must prefix them with the account id.

use std::collections::hash_map::RandomState;
use std::hash::{BuildHasher, Hasher};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

/// Provider slug usable in an id: lowercase ASCII alphanumerics only.
pub fn provider_slug(provider: &str) -> String {
    let s: String = provider
        .to_ascii_lowercase()
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect();
    if s.is_empty() { "account".to_string() } else { s }
}

/// A fresh `<provider>-<6 hex>` id. Callers must still check for a collision
/// (see `Database::create_account`, which retries).
pub fn new_account_id(provider: &str) -> String {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let mut h = RandomState::new().build_hasher(); // OS-seeded per instance
    h.write_u64(COUNTER.fetch_add(1, Ordering::Relaxed));
    h.write_u128(SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0));
    format!("{}-{:06x}", provider_slug(provider), h.finish() & 0xff_ffff)
}

/// Provider part of an account id (`exchange-3f9a1c` → `exchange`).
pub fn provider_of(account_id: &str) -> &str {
    account_id.split('-').next().unwrap_or(account_id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::token_store::DEFAULT_ACCOUNT;

    #[test]
    fn ids_follow_provider_dash_hex_pattern() {
        for p in ["exchange", "Gmail", "IMAP account", "proton-mail", ""] {
            let id = new_account_id(p);
            let (prov, suffix) = id.rsplit_once('-').unwrap();
            assert_eq!(prov, provider_slug(p));
            assert_eq!(suffix.len(), 6, "{}", id);
            assert!(suffix.chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()), "{}", id);
        }
    }

    #[test]
    fn first_account_is_not_special() {
        // New accounts never get the legacy id, even the first Exchange one.
        for _ in 0..1000 {
            assert_ne!(new_account_id("exchange"), DEFAULT_ACCOUNT);
        }
    }

    #[test]
    fn ids_are_well_distributed() {
        let ids: std::collections::HashSet<_> = (0..500).map(|_| new_account_id("exchange")).collect();
        assert!(ids.len() >= 495, "too many collisions: {}", ids.len());
    }

    #[test]
    fn provider_round_trips() {
        assert_eq!(provider_of(&new_account_id("gmail")), "gmail");
        assert_eq!(provider_of("exchange-primary"), "exchange");
    }
}
