/// Mail List bridge module - exposes mail data to QML
/// Phase 2: Email list view integration with Rust backend

use crate::models::CachedMessage;
use log::info;

/// MailListBridge - QML-accessible mail list interface
pub struct MailListBridge {
    emails: Vec<CachedMessage>,
}

impl Default for MailListBridge {
    fn default() -> Self {
        MailListBridge {
            emails: Vec::new(),
        }
    }
}

impl MailListBridge {
    pub fn new() -> Self {
        Self::default()
    }

    /// Load emails from cache (placeholder for graph API integration)
    pub fn fetch_emails(&mut self) -> Result<(), String> {
        info!("MailListBridge::fetch_emails()");
        // TODO: Call graph API to fetch emails
        Ok(())
    }

    /// Get email count
    pub fn email_count(&self) -> i32 {
        self.emails.len() as i32
    }

    /// Get email at index
    pub fn get_email(&self, index: i32) -> Option<EmailSummary> {
        self.emails.get(index as usize).map(|email| EmailSummary {
            subject: email.subject.clone(),
            from: format!("{} ({})", 
                email.from_name.clone().unwrap_or_default(),
                email.from_email.clone()
            ),
            preview: email.body.chars().take(100).collect::<String>(),
            received_at: email.received_at.to_string(),
            is_read: email.is_read,
        })
    }

    /// Mark email as read
    pub fn mark_as_read(&mut self, index: i32) -> Result<(), String> {
        if let Some(email) = self.emails.get_mut(index as usize) {
            email.is_read = true;
            info!("MailListBridge::mark_as_read() - email {}", index);
            Ok(())
        } else {
            Err(format!("Email index {} out of bounds", index))
        }
    }

    /// Delete email
    pub fn delete_email(&mut self, index: i32) -> Result<(), String> {
        if (index as usize) < self.emails.len() {
            self.emails.remove(index as usize);
            info!("MailListBridge::delete_email() - email {}", index);
            Ok(())
        } else {
            Err(format!("Email index {} out of bounds", index))
        }
    }
}

/// Simplified email summary for QML display
pub struct EmailSummary {
    pub subject: String,
    pub from: String,
    pub preview: String,
    pub received_at: String,
    pub is_read: bool,
}
