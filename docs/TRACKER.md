# OmarchyLook — outstanding issues and plans

Single index of open work. Add new items at the top of the relevant section; move finished ones to **Done** with the commit hash.
IDs are stable (never reused). Status: `open` | `investigating` | `planned` | `in progress` | `done`.

## Issues

### OL-001 — UI hangs at ~100% CPU on one thread (open)
- **Seen:** 2026-10-07, `quickshell -p /opt/omalook/qml`, PID 3868852. Window stopped responding; one thread pinned at ~97% CPU
  from startup onward (4:09 CPU in 4:15 elapsed); had to be killed by hand.
- **Likely trigger (user report):** rapid scrolling from one message across many others in very quick succession
  (each selection starts a body fetch + rich-text layout in the preview pane).
- **Evidence so far:** log (`/run/user/1000/quickshell/by-pid/<pid>/log.log`) shows
  `MessagePreview.qml:338 Connection refused` (the `Text.RichText` body), a `QIODevice::read (QSslSocket): device not open`
  warning, and 55x `QFont::setPixelSize: Pixel size <= 0 (0)`. No stack trace: `ptrace_scope=1` blocks `eu-stack`/`gdb` attach.
  The Rust daemon was alive when the user ran `ps` (0:01 CPU); it died from the user's `pkill`, so it is **not** the cause.
- **Hypotheses (unconfirmed):**
  1. Body requests not cancelled/debounced on fast selection change, so stale responses pile up and re-lay-out the HTML.
  2. `Text.RichText` layout loop on a particular message (large/nested table, image with 0 size, remote `<img>` fetch retries).
  3. Binding loop from the zero-pixel-size font warnings.
- **To do:** reproduce on a debug run (`QT_LOGGING_RULES`, perf timeline in `perf.rs`); capture the offending message id;
  debounce body fetch (~120 ms) and ignore stale responses by message id; run with `sudo sysctl kernel.yama.ptrace_scope=0`
  once to get a stack if it recurs. Find the source of the `Pixel size <= 0` warnings.
- **Note:** to kill it, use the PID of `quickshell -p /opt/omalook/qml`, never `pkill quickshell` (that is also the Omarchy desktop shell).

### OL-002 — HTML rendering is not correct (open)
- **Seen:** 2026-10-07, user report: HTML message view "doesn't seem to work quite correctly". Specifics not yet collected.
- **Context:** HTML view is Qt `Text.RichText` (HTML4 subset, no CSS layout) fed by `Fmt.sanitizeHtml` in `qml/mail/format.js`
  (`qml/mail/MessagePreview.qml:338`). Known limits of that engine: no flexbox/float/most CSS, weak table sizing, no `<style>` blocks.
- **To do:** collect 3-5 example messages that render wrongly (screenshot + expected); decide whether to improve the sanitiser
  (inline CSS, table widths, image sizing) or switch the HTML pane to a real engine (QtWebEngine; unverified inside Quickshell,
  see `PLAN-compose.md` Phase D). Possibly related to OL-001.

### OL-003 — Make hyperlinks clickable in "system font" view (open)
- **Seen:** 2026-10-07, user request. In system-font (plain) rendering, URLs in the body are not clickable.
- **To do:** in `Fmt.textToHtml`/the system-font path, linkify `http(s)://`, `www.` and `mailto:` text (escape first, then wrap
  in `<a href>`), keep `onLinkActivated: Qt.openUrlExternally`. Only http(s) and mailto schemes; show the real target on hover.
  Open question: all links or only "some" (user said "some hyperlinks")? Clarify which (e.g. only URLs that appear as bare text,
  not link-text-differs-from-target which is a phishing signal).

## Plans

| Plan | File | Status |
|---|---|---|
| Compose: system-font / HTML modes, drafts, send | `docs/PLAN-compose.md` | planned; Phase D spike passed 2026-10-07; UI first draft + Phase A (send, outbox, undo delay) built 2026-10-08 |
| Mail list views / field chooser | `notes/PLAN-mail-list-views.md` (gitignored `notes/`) | not started |
| Keyboard model: vim nav, `g` modules, palette, mail actions | `docs/PLAN-keyboard.md` | planned (plan written 2026-10-09; decisions Q1-Q6 settled) |

## Done
- (none yet)
