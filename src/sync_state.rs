//! Cross-thread sync signals.
//!
//! * `MAIL_SERIAL` is bumped whenever a sync stage changed what the mail UI shows (new
//!   messages, flipped read flags, new folder counts). The UI polls `GET /sync/serial`
//!   (tiny, no DB access) and reloads when the number moves, so fresh mail appears
//!   within a poll tick of being stored instead of waiting for the slow refresh timer.
//! * The per-account *gate* orders the stages of a launch: the account's mail daemon opens
//!   it once the recent-50 fetch, folder sync and read-state reconcile are done; calendar
//!   and contacts wait on it so mail gets Graph's throttle and the DB write lock first.

use crate::perf;
use std::collections::HashSet;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

static MAIL_SERIAL: AtomicU64 = AtomicU64::new(0);
static GATE: Mutex<Option<HashSet<String>>> = Mutex::new(None);

pub fn mail_serial() -> u64 {
    MAIL_SERIAL.load(Ordering::SeqCst)
}

/// Tell the UI the mail data changed. `reason` is only for the perf log.
pub fn bump_mail(reason: &str) {
    let n = MAIL_SERIAL.fetch_add(1, Ordering::SeqCst) + 1;
    perf::mark(&format!("sync serial -> {} ({})", n, reason));
}

/// Mail's priority work for this account is done; calendar/contacts may start.
pub fn open_gate(account: &str) {
    let mut g = GATE.lock().unwrap_or_else(|p| p.into_inner());
    if g.get_or_insert_with(HashSet::new).insert(account.to_string()) {
        perf::mark(&format!("gate[{}] opened: mail priority stages done", account));
    }
}

fn is_open(account: &str) -> bool {
    GATE.lock().unwrap_or_else(|p| p.into_inner()).as_ref().map(|g| g.contains(account)).unwrap_or(false)
}

/// Wait (async) until the account's gate opens, or `max` passes so a failing mail sync
/// can never starve calendar/contacts. Returns true if it opened.
pub async fn wait_gate(account: &str, max: Duration) -> bool {
    let t = Instant::now();
    while !is_open(account) {
        if t.elapsed() >= max {
            perf::mark(&format!("gate[{}] wait timed out after {:?}", account, max));
            return false;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    true
}
