# Phase 5: Email Inbox & Search — IMPLEMENTATION IN PROGRESS
**Date**: 2026-09-26  
**Status**: 🔄 IN PROGRESS (Core bridge & QML complete, testing & refinement underway)

## Objectives (from phases-of-work.md)
- ✅ Display inbox messages in QML list view  
- ✅ Full-text search on cached messages (FTS5 backed)  
- ✅ Message detail view with expand/collapse  
- ✅ Mark message as read/unread actions  
- ✅ Delete message action  
- ✅ Sender + subject filtering  

## Success Criteria
- **Memory footprint <100MB at rest** — deferred to performance testing  
- **Search response <50ms** — FTS5 indexed queries target <50ms baseline  
- **Startup time <1s cold** — depends on message load volume  
- **Release binary <15MB** — current: check post-build  

## Deliverables Completed

### 1. **MailListBridge** (Rust)
**File**: `src/qt_bridge/mail_list_bridge.rs` (239 lines)

#### Key features:
- `fetch_emails()` — Load recent 100 messages from cache  
- `search(query)` — FTS5 full-text search, max 500 results  
- `filter_by_sender(email)` — Filter by sender address  
- `filter_unread()` — Show only unread messages  
- `clear_filters()` — Reset to all messages  
- `mark_as_read(index)` / `mark_as_unread(index)` — Toggle read status (persisted to DB)  
- `delete_email(index)` — Remove from cache (local deletion)  
- `get_email(index)` → `EmailSummary` — Row data for QML list view  
- `get_email_body(index)` → full body for detail view  
- `email_count()` / `get_unread_count()` — Metadata queries  

#### FilterMode enum:
- `All` — show all cached messages  
- `Unread` — retain only unread  
- `FromSender(String)` — match sender email  

#### Borrow checker fix:
- Lock guard now explicitly dropped before `apply_filters()` call to avoid holding immutable borrow across mutable operation  

### 2. **MailListView.qml** (Composition & Search UI)
**File**: `qml/MailListView.qml` (238 lines)

#### Components:
- **Search bar** (TextInput) with 300ms debounced FTS search  
- **Filter buttons**:  
  - "Unread" — toggle unread filter  
  - "Clear" — reset all filters & search  
- **Email list** (ListView):  
  - Count display (Inbox count + unread count)  
  - Per-item UI:  
    - Green dot indicator for unread messages  
    - Subject (bold if unread), from email, date  
    - Preview (first 150 chars, elided)  
    - Hover state (lighter background)  
  - Clickable rows emit `showDetailView(index)` signal  
- **Initialization**: Auto-loads emails on `Component.onCompleted`  

### 3. **MessageDetail.qml** (Detail & Action View)
**File**: `qml/MessageDetail.qml` (261 lines)

#### Components:
- **Header bar**:  
  - "← Back" button → emits `backToList()` signal  
  - Subject display (truncated)  
  - "Mark unread" button (visible only if read)  
  - "Delete" button (red)  
- **Metadata section**:  
  - From (sender email)  
  - Date (received_at)  
  - Read status (green ● if unread, gray ✓ if read)  
- **Body view** (ScrollView):  
  - Full email body (PlainText, wrapped)  
  - Monospace font for consistency  

### 4. **AppShell Integration**
**File**: `qml/AppShell.qml` (patched)

#### Changes:
- Added state tracking:  
  - `mailView: "list" | "detail"` — sub-view switch  
  - `selectedEmailIndex` — track which email is open  
- Replaced placeholder mail component with Loader:  
  - Dynamic sourceComponent selection based on `mailView` state  
  - `mailListComponent` — MailListView instance  
  - `messageDetailComponent` — MessageDetail instance  
  - Signal wiring: `showDetailView(index)` → switch to detail view  
  - Signal wiring: `backToList()` → return to list view  

## Build Status

**Rust Compilation**: ✅ PASS  
- Command: `cargo build --release`  
- Exit code: 0  
- Warnings: 3 (non-critical: unused imports, dead code, irrefutable pattern)  
- Binary size: TBD (pending full build with dependencies)  

**QML Syntax**: ✅ PASS (no linter errors)

## Next Steps: Testing & Refinement

### Phase 5 (Current) — Refinement:
1. **Test email display** — Launch app, verify inbox loads (>0 messages)  
2. **Test search** — Type query, verify FTS5 results appear  
3. **Test filtering** — Click "Unread", verify list updates  
4. **Test detail view** — Click message, open detail, verify layout  
5. **Test actions** — Mark read/unread, delete, verify persistence  
6. **Performance baseline** — Measure cold startup, search latency with real message volume  
7. **Memory profiling** — Valgrind/heaptrack to validate <100MB baseline  

### Known Limitations (Phase 5):
- Delete is local-cache only; needs backend sync for persistent deletion  
- No pagination; fixed 100-message limit per fetch  
- No attachment display (Phase 6+)  
- No folder/label support yet  

### Phase 6 Scope (Deferred):
- Email composer improvements (threads, drafts)  
- Calendar integration  
- Contact management & autocomplete  
- Message threading  
- Attachment preview/download  

## Files Modified

| File | Lines | Status |
|------|-------|--------|
| `src/qt_bridge/mail_list_bridge.rs` | 239 | ✅ Created |
| `qml/MailListView.qml` | 238 | ✅ Created |
| `qml/MessageDetail.qml` | 261 | ✅ Created |
| `qml/AppShell.qml` | patched (Loader, state tracking) | ✅ Integrated |
| `Cargo.toml` | none | ✓ No changes needed |
| `src/lib.rs` | exports via qt_bridge/mod.rs | ✓ Already available |

## Technical Notes

### Database Integration:
- MailListBridge uses `Arc<Mutex<Database>>` for shared DB access  
- FTS5 backend already present in `db.rs`; uses `search(query, limit)` method  
- `mark_read()` calls persist through DB; delete is in-memory only  

### QML Binding Strategy:
- `mailListBridge` passed as required property to both MailListView and MessageDetail  
- Avoid storing mutable state in QML; bridge owns state  
- Signals (showDetailView, backToList) drive AppShell state machine  

### Performance Considerations:
- Search debounce (300ms) prevents hammering FTS5 on rapid keypresses  
- ListView uses delegate pooling (Qt standard)  
- Single MailListBridge instance shared across views  
- Email body fetched on-demand via `get_email_body(index)` (not pre-loaded)  

### Styling Consistency:
- Monospace font from SettingsManager (defaults to system monospace)  
- Purple accent (#7c6af7) for interactive elements  
- Dark theme (#0d0d0d background, #1a1a1a containers)  
- Red delete button (#dc2626) to signal destructive action  
- Green unread indicator (#4ade80)  

## Verification Checklist

Before marking Phase 5 complete:
- [ ] App launches without segfault  
- [ ] Inbox view shows ≥1 message  
- [ ] Search bar filters results in <100ms  
- [ ] Unread filter works  
- [ ] Detail view opens/closes  
- [ ] Mark read/unread persists (DB checked)  
- [ ] Delete removes from cache  
- [ ] Memory <100MB (idle)  
- [ ] Cold startup <1s (with small message set)  

## Commits & Tags

**Branch**: main  
**Last commit**: Phase 5 initial implementation (mail_list_bridge, views, integration)  
**Tag**: `phase-5-inbox-search` (TBD, post-verification)  

---

**Phase 4 Reference**: See `2026-09-26-PHASE4-COMPLETE.md`  
**Build Reference**: See COMPONENT_REFERENCE.md for dependency versions  
