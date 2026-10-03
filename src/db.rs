//! SQLite database with FTS5 for local mail cache

use crate::errors::{OmarchyError, Result};
use crate::accounts;
use crate::models::{Account, CachedMessage, CalendarEvent, EmailMessage, MailFolder, Message};
use crate::token_store::DEFAULT_ACCOUNT;
use log::{debug, info};
use rusqlite::{Connection, params, OptionalExtension};
use chrono::Utc;

pub struct Database {
    conn: Connection,
    /// Account that rows written through this handle belong to.
    account_id: String,
}

impl Database {
    /// Open or create database at the given path
    pub fn open(path: &str) -> Result<Self> {
        Self::open_for_account(path, DEFAULT_ACCOUNT)
    }

    /// Open the database; rows written through this handle are stamped with `account_id`.
    /// `open()` uses the legacy single account (`exchange-primary`) until the
    /// per-account sync scheduler lands.
    pub fn open_for_account(path: &str, account_id: &str) -> Result<Self> {
        debug!("Opening database at: {} (account {})", path, account_id);
        
        let conn = Connection::open(path)
            .map_err(|e| OmarchyError::DatabaseError(e))?;
        
        let db = Self { conn, account_id: account_id.to_string() };
        db.init_schema()?;
        db.ensure_account_row(account_id)?;
        info!("Database initialized");
        
        Ok(db)
    }

    pub fn account_id(&self) -> &str {
        &self.account_id
    }
    
    /// Initialize schema with FTS5 for full-text search
    fn init_schema(&self) -> Result<()> {
        debug!("Initializing database schema");
        
        // Messages table
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                subject TEXT NOT NULL,
                from_email TEXT NOT NULL,
                from_name TEXT,
                body TEXT NOT NULL,
                received_at DATETIME NOT NULL,
                is_read BOOLEAN DEFAULT 0,
                cached_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )",
            [],
        )?;
        
        // FTS5 virtual table for full-text search
        self.conn.execute(
            "CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
                id UNINDEXED,
                subject,
                from_email UNINDEXED,
                from_name,
                body,
                tokenize = 'porter'
            )",
            [],
        )?;
        
        // Triggers to keep FTS in sync
        self.conn.execute(
            "CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
                INSERT INTO messages_fts(id, subject, from_email, from_name, body)
                VALUES (new.id, new.subject, new.from_email, new.from_name, new.body);
            END",
            [],
        )?;
        
        self.create_messages_au_trigger()?;
        
        self.conn.execute(
            "CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
                INSERT INTO messages_fts(messages_fts, id, subject, from_email, from_name, body)
                VALUES ('delete', old.id, old.subject, old.from_email, old.from_name, old.body);
            END",
            [],
        )?;

        // Folders table
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS folders (
                id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                parent_folder_id TEXT,
                unread_item_count INTEGER DEFAULT 0,
                total_item_count INTEGER DEFAULT 0,
                well_known_name TEXT,
                sort_order INTEGER DEFAULT 999,
                cached_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )",
            [],
        )?;

        // folder_id column on messages (added via ALTER TABLE for existing DBs)
        let has_folder_col: bool = self.conn
            .query_row(
                "SELECT COUNT(*) FROM pragma_table_info('messages') WHERE name='folder_id'",
                [],
                |row| row.get::<_, i32>(0),
            )
            .unwrap_or(0) > 0;
        if !has_folder_col {
            self.conn.execute(
                "ALTER TABLE messages ADD COLUMN folder_id TEXT",
                [],
            )?;
        }

        // Calendar events (separate from mail; created if not present)
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS calendar_events (
                id TEXT PRIMARY KEY,
                subject TEXT NOT NULL,
                body TEXT NOT NULL DEFAULT '',
                start_at TEXT NOT NULL,
                end_at TEXT NOT NULL,
                is_all_day BOOLEAN DEFAULT 0,
                time_zone TEXT,
                cached_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )",
            [],
        )?;
        self.conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_calendar_events_start ON calendar_events(start_at)",
            [],
        )?;

        self.init_accounts_schema()?;

        Ok(())
    }
    
    /// FTS sync trigger for message updates (unchanged definition; factored out so the
    /// account backfill can suspend it inside its transaction).
    fn create_messages_au_trigger(&self) -> Result<()> {
        self.conn.execute(
            "CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
                INSERT INTO messages_fts(messages_fts, id, subject, from_email, from_name, body)
                VALUES('delete', old.id, old.subject, old.from_email, old.from_name, old.body);
                INSERT INTO messages_fts(id, subject, from_email, from_name, body)
                VALUES (new.id, new.subject, new.from_email, new.from_name, new.body);
            END",
            [],
        )?;
        Ok(())
    }

    /// Accounts table + `account_id` on every synced table. Rows that predate
    /// multi-account support are assigned to the legacy account.
    fn init_accounts_schema(&self) -> Result<()> {
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS accounts (
                id TEXT PRIMARY KEY,
                provider TEXT NOT NULL,
                email TEXT,
                display_name TEXT,
                config TEXT NOT NULL DEFAULT '{}',
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(provider, email)
            )",
            [],
        )?;

        let mut backfill_needed = false;
        for table in ["messages", "folders", "calendar_events"] {
            let has_col: bool = self.conn.query_row(
                "SELECT COUNT(*) FROM pragma_table_info(?1) WHERE name='account_id'",
                params![table],
                |row| row.get::<_, i32>(0),
            ).unwrap_or(0) > 0;
            if !has_col {
                self.conn.execute(&format!("ALTER TABLE {} ADD COLUMN account_id TEXT", table), [])?;
            }
            self.conn.execute(
                &format!("CREATE INDEX IF NOT EXISTS idx_{}_account ON {}(account_id)", table, table),
                [],
            )?;
            if self.conn.query_row(
                &format!("SELECT EXISTS(SELECT 1 FROM {} WHERE account_id IS NULL)", table),
                [],
                |row| row.get::<_, bool>(0),
            )? {
                backfill_needed = true;
            }
        }

        if backfill_needed {
            // One transaction: either every table is assigned or none is.
            self.conn.execute_batch("BEGIN")?;
            let result = (|| -> Result<()> {
                self.ensure_account_row(DEFAULT_ACCOUNT)?;
                // account_id is not indexed text, so the FTS update trigger would only churn
                // the full-text index for every row; suspend it for this transaction.
                // (DDL is transactional: a rollback restores the trigger.)
                self.conn.execute("DROP TRIGGER IF EXISTS messages_au", [])?;
                for table in ["messages", "folders", "calendar_events"] {
                    let n = self.conn.execute(
                        &format!("UPDATE {} SET account_id = ?1 WHERE account_id IS NULL", table),
                        params![DEFAULT_ACCOUNT],
                    )?;
                    info!("Assigned {} existing {} rows to account {}", n, table, DEFAULT_ACCOUNT);
                }
                self.create_messages_au_trigger()?;
                Ok(())
            })();
            match result {
                Ok(()) => self.conn.execute_batch("COMMIT")?,
                Err(e) => {
                    let _ = self.conn.execute_batch("ROLLBACK");
                    return Err(e);
                }
            }
        }
        Ok(())
    }

    /// Insert a bare account row if missing (provider derived from the id prefix).
    fn ensure_account_row(&self, account_id: &str) -> Result<()> {
        self.conn.execute(
            "INSERT OR IGNORE INTO accounts (id, provider) VALUES (?1, ?2)",
            params![account_id, accounts::provider_of(account_id)],
        )?;
        Ok(())
    }

    /// Create an account with a freshly generated `<provider>-<suffix>` id.
    /// Fails if the same mailbox (provider + email) is already added.
    pub fn create_account(&self, provider: &str, email: Option<&str>, display_name: Option<&str>, config: &str) -> Result<Account> {
        let provider = accounts::provider_slug(provider);
        if let Some(email) = email {
            let dup: bool = self.conn.query_row(
                "SELECT EXISTS(SELECT 1 FROM accounts WHERE provider = ?1 AND lower(email) = lower(?2))",
                params![provider, email],
                |row| row.get(0),
            )?;
            if dup {
                return Err(OmarchyError::SettingsError(format!("{} account {} is already added", provider, email)));
            }
        }
        for _ in 0..16 {
            let id = accounts::new_account_id(&provider);
            let inserted = self.conn.execute(
                "INSERT OR IGNORE INTO accounts (id, provider, email, display_name, config) VALUES (?1, ?2, ?3, ?4, ?5)",
                params![id, provider, email, display_name, config],
            )?;
            if inserted == 1 {
                return Ok(Account {
                    id, provider,
                    email: email.map(|s| s.to_string()),
                    display_name: display_name.map(|s| s.to_string()),
                    config: config.to_string(),
                });
            }
        }
        Err(OmarchyError::SettingsError("could not generate a unique account id".into()))
    }

    pub fn list_accounts(&self) -> Result<Vec<Account>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, provider, email, display_name, config FROM accounts ORDER BY created_at, id",
        )?;
        let rows = stmt
            .query_map([], |row| {
                Ok(Account {
                    id: row.get(0)?, provider: row.get(1)?, email: row.get(2)?,
                    display_name: row.get(3)?, config: row.get(4)?,
                })
            })?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    pub fn set_account_email(&self, account_id: &str, email: &str) -> Result<()> {
        self.conn.execute("UPDATE accounts SET email = ?1 WHERE id = ?2", params![email, account_id])?;
        Ok(())
    }

    /// Remove an account and everything synced for it (mail, folders, events).
    /// Tokens live in the keyring and are removed by the token broker.
    pub fn delete_account(&self, account_id: &str) -> Result<()> {
        self.conn.execute_batch("BEGIN")?;
        let result = (|| -> Result<()> {
            for table in ["messages", "folders", "calendar_events"] {
                self.conn.execute(&format!("DELETE FROM {} WHERE account_id = ?1", table), params![account_id])?;
            }
            self.conn.execute("DELETE FROM accounts WHERE id = ?1", params![account_id])?;
            Ok(())
        })();
        match result {
            Ok(()) => { self.conn.execute_batch("COMMIT")?; Ok(()) }
            Err(e) => { let _ = self.conn.execute_batch("ROLLBACK"); Err(e) }
        }
    }

    /// Cache a message from Graph API
    pub fn cache_message(&self, msg: &Message) -> Result<()> {
        let from_email = msg.from.as_ref()
            .and_then(|r| r.email_address.as_ref())
            .map(|ea| ea.address.clone())
            .unwrap_or_default();
        
        let from_name = msg.from.as_ref()
            .and_then(|r| r.email_address.as_ref())
            .and_then(|ea| ea.name.clone());
        
        let body = msg.body.as_ref()
            .map(|b| b.content.clone())
            .unwrap_or_default();
        
        let received_at = msg.received_date_time.as_ref()
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
            .map(|dt| dt.to_utc())
            .unwrap_or_else(Utc::now);
        
        // debug!("Caching message: {}", msg.id);
        
        self.conn.execute(
            "INSERT OR REPLACE INTO messages (id, subject, from_email, from_name, body, received_at, is_read, account_id)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                msg.id,
                msg.subject,
                from_email,
                from_name,
                body,
                received_at,
                msg.is_read.unwrap_or(false),
                self.account_id,
            ],
        )?;
        
        Ok(())
    }
    
    /// Check if email already exists in database (for deduplication)
    pub fn email_exists(&self, id: &str) -> Result<bool> {
        let mut stmt = self.conn.prepare(
            "SELECT 1 FROM messages WHERE id = ?1 LIMIT 1"
        )?;
        
        let exists = stmt.exists(params![id])?;
        
        if exists {
            // debug!("Email {} exists in database", id);
        }
        
        Ok(exists)
    }
    
    /// Get cached message by ID
    pub fn get_message(&self, id: &str) -> Result<Option<CachedMessage>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, subject, from_email, from_name, body, received_at, is_read, cached_at
             FROM messages WHERE id = ?1"
        )?;
        
        let msg = stmt.query_row(params![id], |row| {
            Ok(CachedMessage {
                id: row.get(0)?,
                subject: row.get(1)?,
                from_email: row.get(2)?,
                from_name: row.get(3)?,
                body: row.get(4)?,
                received_at: row.get(5)?,
                is_read: row.get(6)?,
                cached_at: row.get(7)?,
            })
        }).optional()?;
        
        Ok(msg)
    }
    
    /// Get recent cached messages
    pub fn get_recent_messages(&self, limit: usize) -> Result<Vec<CachedMessage>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, subject, from_email, from_name, body, received_at, is_read, cached_at
             FROM messages ORDER BY received_at DESC LIMIT ?1"
        )?;
        
        let messages = stmt.query_map(params![limit as i32], |row| {
            Ok(CachedMessage {
                id: row.get(0)?,
                subject: row.get(1)?,
                from_email: row.get(2)?,
                from_name: row.get(3)?,
                body: row.get(4)?,
                received_at: row.get(5)?,
                is_read: row.get(6)?,
                cached_at: row.get(7)?,
            })
        })?
        .collect::<std::result::Result<Vec<_>, _>>()?;
        
        Ok(messages)
    }
    
    /// Full-text search in cached messages
    pub fn search(&self, query: &str, limit: usize) -> Result<Vec<CachedMessage>> {
        debug!("FTS search: {}", query);
        
        let mut stmt = self.conn.prepare(
            "SELECT m.id, m.subject, m.from_email, m.from_name, m.body, m.received_at, m.is_read, m.cached_at
             FROM messages m
             JOIN messages_fts f ON m.id = f.id
             WHERE messages_fts MATCH ?1
             ORDER BY rank
             LIMIT ?2"
        )?;
        
        let messages = stmt.query_map(params![query, limit as i32], |row| {
            Ok(CachedMessage {
                id: row.get(0)?,
                subject: row.get(1)?,
                from_email: row.get(2)?,
                from_name: row.get(3)?,
                body: row.get(4)?,
                received_at: row.get(5)?,
                is_read: row.get(6)?,
                cached_at: row.get(7)?,
            })
        })?
        .collect::<std::result::Result<Vec<_>, _>>()?;
        
        info!("FTS search returned {} results", messages.len());
        Ok(messages)
    }
    
    /// Mark message as read
    pub fn mark_read(&self, id: &str, is_read: bool) -> Result<()> {
        self.conn.execute(
            "UPDATE messages SET is_read = ?1 WHERE id = ?2",
            params![is_read, id],
        )?;
        Ok(())
    }
    
    /// Delete old messages (retention policy)
    pub fn cleanup_old_messages(&self, days: i32) -> Result<usize> {
        let count = self.conn.execute(
            "DELETE FROM messages WHERE received_at < datetime('now', ?1)",
            params![format!("-{} days", days)],
        )?;
        
        info!("Cleaned up {} old messages", count);
        Ok(count)
    }
    
    /// Get unread count
    pub fn get_unread_count(&self) -> Result<usize> {
        let mut stmt = self.conn.prepare(
            "SELECT COUNT(*) FROM messages WHERE is_read = 0"
        )?;
        
        let count: i32 = stmt.query_row([], |row| row.get(0))?;
        Ok(count as usize)
    }

    /// Insert a new email message (used by daemon)
    pub fn insert_email(&self, email: &EmailMessage) -> Result<()> {
        let now = Utc::now();
        // debug!("Inserting email: {}", email.id);

        self.conn.execute(
            "INSERT OR IGNORE INTO messages (id, subject, from_email, body, received_at, is_read, cached_at, folder_id, account_id)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                email.id,
                email.subject,
                email.from,
                email.body,
                email.received,
                false, // new emails default to unread
                now,
                email.folder_id,
                self.account_id,
            ],
        )?;

        // Backfill folder_id on existing rows that were inserted before the column existed
        if email.folder_id.is_some() {
            self.conn.execute(
                "UPDATE messages SET folder_id = ?1 WHERE id = ?2 AND folder_id IS NULL",
                params![email.folder_id, email.id],
            )?;
        }

        Ok(())
    }

    /// Upsert a folder from Graph API
    pub fn upsert_folder(&self, folder: &MailFolder) -> Result<()> {
        // Assign sort_order: well-known folders get fixed low numbers, others 999
        let sort_order: i32 = match folder.well_known_name.as_deref() {
            Some("inbox")        => 1,
            Some("drafts")       => 2,
            Some("sentitems")    => 3,
            Some("deleteditems") => 4,
            Some("junkemail")    => 5,
            Some("archive")      => 6,
            _                    => 999,
        };

        self.conn.execute(
            "INSERT INTO folders (id, display_name, parent_folder_id, unread_item_count, total_item_count, well_known_name, sort_order, cached_at, account_id)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, CURRENT_TIMESTAMP, ?8)
             ON CONFLICT(id) DO UPDATE SET
               display_name      = excluded.display_name,
               unread_item_count = excluded.unread_item_count,
               total_item_count  = excluded.total_item_count,
               sort_order        = excluded.sort_order,
               cached_at         = CURRENT_TIMESTAMP",
            params![
                folder.id,
                folder.display_name,
                folder.parent_folder_id,
                folder.unread_item_count,
                folder.total_item_count,
                folder.well_known_name,
                sort_order,
                self.account_id,
            ],
        )?;
        Ok(())
    }

    /// Get all folders sorted: well-known first (by sort_order), then alphabetical
    pub fn get_folders(&self) -> Result<Vec<MailFolder>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, display_name, parent_folder_id, unread_item_count, total_item_count, well_known_name
             FROM folders
             ORDER BY sort_order ASC, display_name ASC",
        )?;

        let folders = stmt
            .query_map([], |row| {
                Ok(MailFolder {
                    id:                row.get(0)?,
                    display_name:      row.get(1)?,
                    parent_folder_id:  row.get(2)?,
                    unread_item_count: row.get(3)?,
                    total_item_count:  row.get(4)?,
                    well_known_name:   row.get(5)?,
                })
            })?
            .collect::<std::result::Result<Vec<_>, _>>()?;

        Ok(folders)
    }

    /// Get cached messages for a specific folder (by folder_id)
    pub fn get_messages_for_folder(&self, folder_id: &str, limit: usize) -> Result<Vec<CachedMessage>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, subject, from_email, from_name, body, received_at, is_read, cached_at
             FROM messages
             WHERE folder_id = ?1
             ORDER BY received_at DESC
             LIMIT ?2",
        )?;

        let messages = stmt
            .query_map(params![folder_id, limit as i32], |row| {
                Ok(CachedMessage {
                    id:          row.get(0)?,
                    subject:     row.get(1)?,
                    from_email:  row.get(2)?,
                    from_name:   row.get(3)?,
                    body:        row.get(4)?,
                    received_at: row.get(5)?,
                    is_read:     row.get(6)?,
                    cached_at:   row.get(7)?,
                })
            })?
            .collect::<std::result::Result<Vec<_>, _>>()?;

        Ok(messages)
    }

    // ------------------------------------------------------------ calendar

    /// Insert or update a calendar event (updates so reschedules/edits propagate)
    pub fn upsert_event(&self, ev: &CalendarEvent) -> Result<()> {
        self.conn.execute(
            "INSERT INTO calendar_events (id, subject, body, start_at, end_at, is_all_day, time_zone, cached_at, account_id)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, CURRENT_TIMESTAMP, ?8)
             ON CONFLICT(id) DO UPDATE SET
               subject    = excluded.subject,
               body       = excluded.body,
               start_at   = excluded.start_at,
               end_at     = excluded.end_at,
               is_all_day = excluded.is_all_day,
               time_zone  = excluded.time_zone,
               cached_at  = CURRENT_TIMESTAMP",
            params![ev.id, ev.subject, ev.body, ev.start, ev.end, ev.is_all_day, ev.time_zone, self.account_id],
        )?;
        Ok(())
    }

    /// Events overlapping the given month ("YYYY-MM"), ordered by start
    pub fn get_events_for_month(&self, month: &str) -> Result<Vec<CalendarEvent>> {
        let (y, m) = month.split_once('-').unwrap_or(("1970", "01"));
        let (y, m): (i32, u32) = (y.parse().unwrap_or(1970), m.parse().unwrap_or(1));
        let (ny, nm) = if m >= 12 { (y + 1, 1) } else { (y, m + 1) };
        let from = format!("{:04}-{:02}-01T00:00:00", y, m);
        let to = format!("{:04}-{:02}-01T00:00:00", ny, nm);

        let mut stmt = self.conn.prepare(
            "SELECT id, subject, body, start_at, end_at, is_all_day, COALESCE(time_zone, '')
             FROM calendar_events
             WHERE start_at < ?2 AND end_at >= ?1
             ORDER BY start_at ASC",
        )?;
        let events = stmt
            .query_map(params![from, to], |row| {
                Ok(CalendarEvent {
                    id:         row.get(0)?,
                    subject:    row.get(1)?,
                    body:       row.get(2)?,
                    start:      row.get(3)?,
                    end:        row.get(4)?,
                    is_all_day: row.get(5)?,
                    time_zone:  row.get(6)?,
                })
            })?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        Ok(events)
    }
}

#[cfg(test)]
mod calendar_tests {
    use super::*;

    fn ev(id: &str, start: &str, end: &str, subject: &str) -> CalendarEvent {
        CalendarEvent {
            id: id.into(), subject: subject.into(), body: "body".into(),
            start: start.into(), end: end.into(), is_all_day: false, time_zone: "America/New_York".into(),
        }
    }

    #[test]
    fn upsert_and_month_query() {
        let db = Database::open(":memory:").unwrap();
        db.upsert_event(&ev("a", "2026-10-03T09:00:00", "2026-10-03T10:00:00", "Standup")).unwrap();
        db.upsert_event(&ev("b", "2026-09-30T23:00:00", "2026-10-01T01:00:00", "Spans in")).unwrap();
        db.upsert_event(&ev("c", "2026-11-01T09:00:00", "2026-11-01T10:00:00", "Next month")).unwrap();
        db.upsert_event(&ev("d", "2026-12-31T20:00:00", "2027-01-01T01:00:00", "Spans out")).unwrap();

        let oct = db.get_events_for_month("2026-10").unwrap();
        assert_eq!(oct.iter().map(|e| e.id.as_str()).collect::<Vec<_>>(), vec!["b", "a"]);
        assert_eq!(db.get_events_for_month("2027-01").unwrap().len(), 1);
        assert_eq!(db.get_events_for_month("2026-12").unwrap().len(), 1);

        // upsert updates in place (reschedule)
        db.upsert_event(&ev("a", "2026-10-04T09:00:00", "2026-10-04T10:00:00", "Standup moved")).unwrap();
        let oct = db.get_events_for_month("2026-10").unwrap();
        assert_eq!(oct.len(), 2);
        assert!(oct.iter().any(|e| e.subject == "Standup moved" && e.start.starts_with("2026-10-04")));
    }
}

#[cfg(test)]
mod account_tests {
    use super::*;

    fn temp_db_path(name: &str) -> String {
        let dir = std::env::temp_dir().join(format!("omarchylook-test-{}-{}", name, std::process::id()));
        let _ = std::fs::remove_file(&dir);
        dir.to_string_lossy().to_string()
    }

    #[test]
    fn create_account_generates_pattern_ids_even_for_first_account() {
        let db = Database::open_for_account(":memory:", "exchange-aaaaaa").unwrap();
        let a = db.create_account("Exchange", Some("a@x.com"), None, "{}").unwrap();
        let b = db.create_account("exchange", Some("b@x.com"), None, "{}").unwrap();
        for acc in [&a, &b] {
            assert!(acc.id.starts_with("exchange-") && acc.id != DEFAULT_ACCOUNT, "{}", acc.id);
            assert_eq!(acc.id.len(), "exchange-".len() + 6);
        }
        assert_ne!(a.id, b.id);
    }

    #[test]
    fn duplicate_mailbox_is_rejected_case_insensitively() {
        let db = Database::open(":memory:").unwrap();
        db.create_account("gmail", Some("Me@Gmail.com"), None, "{}").unwrap();
        assert!(db.create_account("gmail", Some("me@gmail.com"), None, "{}").is_err());
        // same address on another provider type is a different account
        assert!(db.create_account("outlook", Some("me@gmail.com"), None, "{}").is_ok());
    }

    #[test]
    fn writes_are_stamped_with_the_handle_account() {
        let db = Database::open_for_account(":memory:", "gmail-123abc").unwrap();
        db.insert_email(&EmailMessage {
            id: "m1".into(), from: "x@y".into(), subject: "s".into(), received: "2026-10-01T00:00:00Z".into(),
            body: "b".into(), folder_id: Some("f".into()),
        }).unwrap();
        db.upsert_event(&CalendarEvent {
            id: "e1".into(), subject: "s".into(), body: "".into(), start: "2026-10-01T09:00:00".into(),
            end: "2026-10-01T10:00:00".into(), is_all_day: false, time_zone: "UTC".into(),
        }).unwrap();
        let m: String = db.conn.query_row("SELECT account_id FROM messages WHERE id='m1'", [], |r| r.get(0)).unwrap();
        let e: String = db.conn.query_row("SELECT account_id FROM calendar_events WHERE id='e1'", [], |r| r.get(0)).unwrap();
        assert_eq!((m.as_str(), e.as_str()), ("gmail-123abc", "gmail-123abc"));
    }

    #[test]
    fn existing_rows_are_backfilled_to_the_legacy_account() {
        // Build a pre-multi-account database (no accounts table, no account_id).
        let path = temp_db_path("backfill");
        {
            let c = Connection::open(&path).unwrap();
            c.execute_batch(
                "CREATE TABLE messages (id TEXT PRIMARY KEY, subject TEXT NOT NULL, from_email TEXT NOT NULL, from_name TEXT,
                    body TEXT NOT NULL, received_at DATETIME NOT NULL, is_read BOOLEAN DEFAULT 0,
                    cached_at DATETIME DEFAULT CURRENT_TIMESTAMP, folder_id TEXT);
                 CREATE TABLE folders (id TEXT PRIMARY KEY, display_name TEXT NOT NULL, parent_folder_id TEXT,
                    unread_item_count INTEGER DEFAULT 0, total_item_count INTEGER DEFAULT 0, well_known_name TEXT,
                    sort_order INTEGER DEFAULT 999, cached_at DATETIME DEFAULT CURRENT_TIMESTAMP);
                 CREATE TABLE calendar_events (id TEXT PRIMARY KEY, subject TEXT NOT NULL, body TEXT NOT NULL DEFAULT '',
                    start_at TEXT NOT NULL, end_at TEXT NOT NULL, is_all_day BOOLEAN DEFAULT 0, time_zone TEXT,
                    cached_at DATETIME DEFAULT CURRENT_TIMESTAMP);
                 INSERT INTO messages (id, subject, from_email, body, received_at) VALUES ('m1','s','a@b','x','2026-01-01'),('m2','s','a@b','x','2026-01-02');
                 INSERT INTO folders (id, display_name) VALUES ('f1','Inbox');
                 INSERT INTO calendar_events (id, subject, start_at, end_at) VALUES ('e1','s','2026-01-01T09:00:00','2026-01-01T10:00:00');",
            ).unwrap();
        }
        let db = Database::open(&path).unwrap();
        for (table, n) in [("messages", 2), ("folders", 1), ("calendar_events", 1)] {
            let c: i32 = db.conn.query_row(&format!("SELECT COUNT(*) FROM {} WHERE account_id = 'exchange-primary'", table), [], |r| r.get(0)).unwrap();
            let nulls: i32 = db.conn.query_row(&format!("SELECT COUNT(*) FROM {} WHERE account_id IS NULL", table), [], |r| r.get(0)).unwrap();
            assert_eq!((c, nulls), (n, 0), "{}", table);
        }
        let trig: i32 = db.conn.query_row("SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name='messages_au'", [], |r| r.get(0)).unwrap();
        assert_eq!(trig, 1, "FTS update trigger must be restored after backfill");
        let accts = db.list_accounts().unwrap();
        assert_eq!(accts.len(), 1);
        assert_eq!((accts[0].id.as_str(), accts[0].provider.as_str()), ("exchange-primary", "exchange"));

        // Re-opening is idempotent.
        drop(db);
        let db = Database::open(&path).unwrap();
        assert_eq!(db.list_accounts().unwrap().len(), 1);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn delete_account_removes_only_its_data() {
        let a = Database::open_for_account(":memory:", "gmail-aaaaaa").unwrap();
        let ev = |id: &str| CalendarEvent { id: id.into(), subject: "s".into(), body: "".into(), start: "2026-10-01T09:00:00".into(),
            end: "2026-10-01T10:00:00".into(), is_all_day: false, time_zone: "UTC".into() };
        a.upsert_event(&ev("e1")).unwrap();
        a.conn.execute("INSERT INTO calendar_events (id, subject, start_at, end_at, account_id) VALUES ('e2','s','2026-10-01T09:00:00','2026-10-01T10:00:00','gmail-bbbbbb')", []).unwrap();
        a.delete_account("gmail-aaaaaa").unwrap();
        let left: Vec<String> = a.conn.prepare("SELECT id FROM calendar_events").unwrap()
            .query_map([], |r| r.get(0)).unwrap().filter_map(|r| r.ok()).collect();
        assert_eq!(left, vec!["e2"]);
        assert!(a.list_accounts().unwrap().is_empty());
    }
}

#[cfg(test)]
mod real_db_copy {
    use super::*;

    /// Opens a COPY of a real database (path in OMARCHY_DB_COPY) and checks the account backfill.
    /// Run with: OMARCHY_DB_COPY=/path/copy.db cargo test real_db_copy -- --ignored --nocapture
    #[test]
    #[ignore]
    fn backfill_on_copy_of_real_db() {
        let path = std::env::var("OMARCHY_DB_COPY").expect("set OMARCHY_DB_COPY");
        let before = Connection::open(&path).unwrap();
        let counts = |c: &Connection| -> Vec<i64> {
            ["messages", "folders", "calendar_events"].iter()
                .map(|t| c.query_row(&format!("SELECT COUNT(*) FROM {}", t), [], |r| r.get(0)).unwrap()).collect()
        };
        let n_before = counts(&before);
        drop(before);

        let t = std::time::Instant::now();
        let db = Database::open(&path).unwrap();
        println!("open+backfill took {:?}", t.elapsed());

        assert_eq!(counts(&db.conn), n_before, "row counts must not change");
        for table in ["messages", "folders", "calendar_events"] {
            let nulls: i64 = db.conn.query_row(&format!("SELECT COUNT(*) FROM {} WHERE account_id IS NULL", table), [], |r| r.get(0)).unwrap();
            assert_eq!(nulls, 0, "{}", table);
        }
        println!("rows before/after: {:?}", n_before);
        println!("accounts: {:?}", db.list_accounts().unwrap());
        let fts: i64 = db.conn.query_row("SELECT COUNT(*) FROM messages_fts", [], |r| r.get(0)).unwrap();
        println!("messages_fts rows: {}", fts);
    }
}
