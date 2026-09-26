/// Mail List bridge module - exposes mail data to QML with search & filtering
/// Phase 5: Email inbox display, full-text search, filtering, detail view

use crate::models::CachedMessage;
use crate::db::Database;
use std::sync::{Arc, Mutex};
use log::info;

/// MailListBridge - QML-accessible mail list interface with search & filtering
pub struct MailListBridge {
    emails: Vec<CachedMessage>,
    db: Option<Arc<Mutex<Database>>>,
    current_search_query: String,
    current_filter: FilterMode,
}

#[derive(Clone, Debug)]
pub enum FilterMode {
    All,
    Unread,
    FromSender(String),
}

impl Default for MailListBridge {
    fn default() -> Self {
        MailListBridge {
            emails: Vec::new(),
            db: None,
            current_search_query: String::new(),
            current_filter: FilterMode::All,
        }
    }
}

impl MailListBridge {
    pub fn new() -> Self {
        Self::default()
    }

    /// Initialize with database connection
    pub fn with_db(db: Arc<Mutex<Database>>) -> Self {
        MailListBridge {
            db: Some(db),
            ..Default::default()
        }
    }

    /// Load emails from cache (recent messages)
    pub fn fetch_emails(&mut self) -> Result<(), String> {
        info!("MailListBridge::fetch_emails()");
        
        if let Some(db_ref) = &self.db {
            let db = db_ref.lock().map_err(|e| format!("Db lock failed: {}", e))?;
            
            // Load recent 100 messages
            let messages = db.get_recent_messages(100)
                .map_err(|e| format!("Failed to fetch messages: {}", e))?;
            
            self.emails = messages;
            // Drop the lock guard before calling apply_filters
            drop(db);
            self.apply_filters();
            info!("Loaded {} emails from cache", self.emails.len());
            Ok(())
        } else {
            Err("Database not initialized".to_string())
        }
    }

    /// Search emails using FTS5
    pub fn search(&mut self, query: &str) -> Result<(), String> {
        info!("MailListBridge::search(\"{}\")", query);
        
        self.current_search_query = query.to_string();
        
        if query.is_empty() {
            // Return to full list
            return self.fetch_emails();
        }
        
        if let Some(db_ref) = &self.db {
            let db = db_ref.lock().map_err(|e| format!("Db lock failed: {}", e))?;
            
            // FTS5 search with limit of 500 results
            let results = db.search(query, 500)
                .map_err(|e| format!("FTS search failed: {}", e))?;
            
            self.emails = results;
            // Drop the lock guard before calling apply_filters
            drop(db);
            self.apply_filters();
            info!("FTS search found {} results", self.emails.len());
            Ok(())
        } else {
            Err("Database not initialized".to_string())
        }
    }

    /// Filter by sender
    pub fn filter_by_sender(&mut self, sender_email: &str) -> Result<(), String> {
        info!("MailListBridge::filter_by_sender(\"{}\")", sender_email);
        
        self.current_filter = FilterMode::FromSender(sender_email.to_string());
        
        // Reload from database and apply filter
        self.fetch_emails()?;
        Ok(())
    }

    /// Filter unread messages
    pub fn filter_unread(&mut self) -> Result<(), String> {
        info!("MailListBridge::filter_unread()");
        
        self.current_filter = FilterMode::Unread;
        self.fetch_emails()?;
        Ok(())
    }

    /// Clear all filters and show all messages
    pub fn clear_filters(&mut self) -> Result<(), String> {
        info!("MailListBridge::clear_filters()");
        
        self.current_filter = FilterMode::All;
        self.current_search_query.clear();
        self.fetch_emails()?;
        Ok(())
    }

    /// Apply current filters to emails list
    fn apply_filters(&mut self) {
        match &self.current_filter {
            FilterMode::All => {
                // No additional filtering
            }
            FilterMode::Unread => {
                self.emails.retain(|email| !email.is_read);
            }
            FilterMode::FromSender(sender) => {
                self.emails.retain(|email| email.from_email == *sender);
            }
        }
    }

    /// Get email count (post-filter)
    pub fn email_count(&self) -> i32 {
        self.emails.len() as i32
    }

    /// Get email at index
    pub fn get_email(&self, index: i32) -> Option<EmailSummary> {
        self.emails.get(index as usize).map(|email| EmailSummary {
            id: email.id.clone(),
            subject: email.subject.clone(),
            from: format!("{} ({})", 
                email.from_name.clone().unwrap_or_default(),
                email.from_email.clone()
            ),
            from_email: email.from_email.clone(),
            preview: email.body.chars().take(150).collect::<String>(),
            received_at: email.received_at.to_string(),
            is_read: email.is_read,
        })
    }

    /// Get full email body for detail view
    pub fn get_email_body(&self, index: i32) -> Option<String> {
        self.emails.get(index as usize).map(|email| email.body.clone())
    }

    /// Mark email as read
    pub fn mark_as_read(&mut self, index: i32) -> Result<(), String> {
        if let Some(email) = self.emails.get_mut(index as usize) {
            let email_id = email.id.clone();
            email.is_read = true;
            
            // Persist to database
            if let Some(db_ref) = &self.db {
                let db = db_ref.lock().map_err(|e| format!("Db lock failed: {}", e))?;
                db.mark_read(&email_id, true)
                    .map_err(|e| format!("Failed to mark read: {}", e))?;
            }
            
            info!("Marked email {} as read", index);
            Ok(())
        } else {
            Err(format!("Email index {} out of bounds", index))
        }
    }

    /// Mark email as unread
    pub fn mark_as_unread(&mut self, index: i32) -> Result<(), String> {
        if let Some(email) = self.emails.get_mut(index as usize) {
            let email_id = email.id.clone();
            email.is_read = false;
            
            // Persist to database
            if let Some(db_ref) = &self.db {
                let db = db_ref.lock().map_err(|e| format!("Db lock failed: {}", e))?;
                db.mark_read(&email_id, false)
                    .map_err(|e| format!("Failed to mark unread: {}", e))?;
            }
            
            info!("Marked email {} as unread", index);
            Ok(())
        } else {
            Err(format!("Email index {} out of bounds", index))
        }
    }

    /// Delete email (local cache only for now)
    pub fn delete_email(&mut self, index: i32) -> Result<(), String> {
        if (index as usize) < self.emails.len() {
            let email = self.emails.remove(index as usize);
            info!("Deleted email {} from cache", email.id);
            Ok(())
        } else {
            Err(format!("Email index {} out of bounds", index))
        }
    }

    /// Get unread count
    pub fn get_unread_count(&self) -> i32 {
        self.emails.iter().filter(|e| !e.is_read).count() as i32
    }
}

/// Simplified email summary for QML display
#[derive(Clone, Debug)]
pub struct EmailSummary {
    pub id: String,
    pub subject: String,
    pub from: String,
    pub from_email: String,
    pub preview: String,
    pub received_at: String,
    pub is_read: bool,
}
