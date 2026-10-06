//! Launch-to-mail timing marks.
//!
//! `perf::mark("label")` prints `[PERF] +<ms since process start> [thread] label` to stderr
//! and appends the same line to `<config dir>/perf.log` (truncated at each launch). The QML
//! side posts its own marks to `POST /perf?m=<label>`, so one file holds the whole timeline
//! from process start to "emails visible". Cost per mark is a mutex + one small write.

use std::fs::File;
use std::io::Write;
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

static START: OnceLock<Instant> = OnceLock::new();
static LOG: OnceLock<Mutex<Option<File>>> = OnceLock::new();

/// Call first thing in `main`: fixes t=0 and (re)creates the log file.
pub fn init(config_dir: &std::path::Path) {
    let _ = START.set(Instant::now());
    let _ = std::fs::create_dir_all(config_dir);
    let file = File::create(config_dir.join("perf.log")).ok();
    let _ = LOG.set(Mutex::new(file));
    mark("process start");
}

/// Milliseconds since `init` (0.0 if `init` was never called).
pub fn elapsed_ms() -> f64 {
    START.get().map(|s| s.elapsed().as_secs_f64() * 1000.0).unwrap_or(0.0)
}

pub fn mark(label: &str) {
    let thread = std::thread::current();
    let line = format!("+{:>8.1}ms [{}] {}", elapsed_ms(), thread.name().unwrap_or("main"), label);
    eprintln!("[PERF] {}", line);
    if let Some(lock) = LOG.get() {
        if let Ok(mut guard) = lock.lock() {
            if let Some(f) = guard.as_mut() {
                let _ = writeln!(f, "{}", line);
            }
        }
    }
}

/// Time a block: marks `<label> (<n> ms)` when the returned guard drops.
pub struct Span {
    label: String,
    t: Instant,
}

pub fn span(label: impl Into<String>) -> Span {
    Span { label: label.into(), t: Instant::now() }
}

impl Drop for Span {
    fn drop(&mut self) {
        mark(&format!("{} done in {:.1}ms", self.label, self.t.elapsed().as_secs_f64() * 1000.0));
    }
}
