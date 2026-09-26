//! SQLite database with FTS5 for local mail cache

use crate::errors::{OmarchyError, Result};
use crate::models::{CachedMessage, EmailMessage, MailFolder, Message};
use log::{debug, info};
use rusqlite::{Connection, params, OptionalExtension};
use chrono::Utc;

pub struct Database {
    conn: Connection,
}

impl Database {
    /// Open or create database at the given path
    pub fn open(path: &str) -> Result<Self> {
        debug!("Opening database at: {}", path);
        
        let conn = Connection::open(path)
            .map_err(|e| OmarchyError::DatabaseError(e))?;
        
        let db = Self { conn };
        db.init_schema()?;
        info!("Database initialized");
        
        Ok(db)
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
        
        self.conn.execute(
            "CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
                INSERT INTO messages_fts(messages_fts, id, subject, from_email, from_name, body)
                VALUES('delete', old.id, old.subject, old.from_email, old.from_name, old.body);
                INSERT INTO messages_fts(id, subject, from_email, from_name, body)
                VALUES (new.id, new.subject, new.from_email, new.from_name, new.body);
            END",
            [],
        )?;
        
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

        Ok(())
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
        
        debug!("Caching message: {}", msg.id);
        
        self.conn.execute(
            "INSERT OR REPLACE INTO messages (id, subject, from_email, from_name, body, received_at, is_read)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                msg.id,
                msg.subject,
                from_email,
                from_name,
                body,
                received_at,
                msg.is_read.unwrap_or(false),
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
            debug!("Email {} exists in database", id);
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
        debug!("Inserting email: {}", email.id);

        self.conn.execute(
            "INSERT OR IGNORE INTO messages (id, subject, from_email, body, received_at, is_read, cached_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                email.id,
                email.subject,
                email.from,
                email.body,
                email.received,
                false, // new emails default to unread
                now,
            ],
        )?;

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
            "INSERT INTO folders (id, display_name, parent_folder_id, unread_item_count, total_item_count, well_known_name, sort_order, cached_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, CURRENT_TIMESTAMP)
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
}
