/// Compose bridge module - exposes email composition to QML
/// Phase 4: Email send integration with Microsoft Graph

use log::{info, debug, error};
use regex::Regex;
use std::sync::{Arc, Mutex};

/// Simple email validation pattern (basic RFC 5322)
fn is_valid_email(email: &str) -> bool {
    let email_pattern = Regex::new(
        r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
    ).unwrap();
    email_pattern.is_match(email)
}

/// Parse comma-separated email list
fn parse_recipients(recipients_str: &str) -> Vec<String> {
    recipients_str
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

/// ComposeBridge - QML-accessible email composition interface
/// Handles form input and delegates send to GraphClient
pub struct ComposeBridge {
    to: String,
    cc: String,
    bcc: String,
    subject: String,
    body: String,
    // Last error message (shown to user)
    last_error: Arc<Mutex<String>>,
}

impl Default for ComposeBridge {
    fn default() -> Self {
        ComposeBridge {
            to: String::new(),
            cc: String::new(),
            bcc: String::new(),
            subject: String::new(),
            body: String::new(),
            last_error: Arc::new(Mutex::new(String::new())),
        }
    }
}

impl ComposeBridge {
    pub fn new() -> Self {
        Self::default()
    }

    /// Clear compose form
    pub fn clear(&mut self) {
        info!("ComposeBridge::clear()");
        self.to.clear();
        self.cc.clear();
        self.bcc.clear();
        self.subject.clear();
        self.body.clear();
        self.clear_error();
    }

    /// Set recipient(s) - can be comma-separated
    pub fn set_to(&mut self, email: String) {
        info!("ComposeBridge::set_to() - {}", email);
        self.to = email;
    }

    /// Set CC recipient(s)
    pub fn set_cc(&mut self, email: String) {
        info!("ComposeBridge::set_cc() - {}", email);
        self.cc = email;
    }

    /// Set BCC recipient(s)
    pub fn set_bcc(&mut self, email: String) {
        info!("ComposeBridge::set_bcc() - {}", email);
        self.bcc = email;
    }

    /// Set subject
    pub fn set_subject(&mut self, subject: String) {
        debug!("ComposeBridge::set_subject() - {} chars", subject.len());
        self.subject = subject;
    }

    /// Set email body
    pub fn set_body(&mut self, body: String) {
        debug!("ComposeBridge::set_body() - {} chars", body.len());
        self.body = body;
    }

    /// Validate email addresses in all recipient fields
    fn validate_recipients(&self) -> Result<Vec<String>, String> {
        let all_recipients = format!("{},{},{}", self.to, self.cc, self.bcc);
        let recipients = parse_recipients(&all_recipients);

        if self.to.trim().is_empty() {
            return Err("At least one recipient (To) is required".to_string());
        }

        // Validate each recipient
        for recipient in &recipients {
            if !is_valid_email(recipient) {
                return Err(format!("Invalid email address: {}", recipient));
            }
        }

        Ok(recipients)
    }

    /// Validate form before sending
    fn validate(&self) -> Result<(), String> {
        // Check to field
        if self.to.trim().is_empty() {
            return Err("Recipient required".to_string());
        }

        // Check subject field
        if self.subject.trim().is_empty() {
            return Err("Subject required".to_string());
        }

        // Validate To email addresses
        let to_recipients = parse_recipients(&self.to);
        for email in to_recipients {
            if !is_valid_email(&email) {
                return Err(format!("Invalid recipient email: {}", email));
            }
        }

        // Validate CC if provided
        if !self.cc.is_empty() {
            let cc_recipients = parse_recipients(&self.cc);
            for email in cc_recipients {
                if !is_valid_email(&email) {
                    return Err(format!("Invalid CC email: {}", email));
                }
            }
        }

        // Validate BCC if provided
        if !self.bcc.is_empty() {
            let bcc_recipients = parse_recipients(&self.bcc);
            for email in bcc_recipients {
                if !is_valid_email(&email) {
                    return Err(format!("Invalid BCC email: {}", email));
                }
            }
        }

        Ok(())
    }

    /// Send email via Microsoft Graph
    /// This is called from QML, which handles GraphClient access
    pub fn send(&mut self) -> bool {
        info!("ComposeBridge::send() - validating form");

        // Validate form
        if let Err(e) = self.validate() {
            error!("Validation error: {}", e);
            self.set_error(&e);
            return false;
        }

        // TODO: Call graph API when cxx-qt bridge is available
        // For now, log success and clear form
        info!(
            "ComposeBridge::send() - to: {}, subject: {}",
            self.to, self.subject
        );

        // Clear error on success
        self.clear_error();
        true
    }

    /// Get last error message
    pub fn get_last_error(&self) -> String {
        self.last_error.lock().unwrap().clone()
    }

    /// Set error message (for displaying to user)
    fn set_error(&self, msg: &str) {
        *self.last_error.lock().unwrap() = msg.to_string();
        error!("ComposeBridge error: {}", msg);
    }

    /// Clear error message
    fn clear_error(&self) {
        *self.last_error.lock().unwrap() = String::new();
    }

    // Getters for QML binding
    pub fn get_to(&self) -> &str {
        &self.to
    }

    pub fn get_cc(&self) -> &str {
        &self.cc
    }

    pub fn get_bcc(&self) -> &str {
        &self.bcc
    }

    pub fn get_subject(&self) -> &str {
        &self.subject
    }

    pub fn get_body(&self) -> &str {
        &self.body
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_email() {
        assert!(is_valid_email("user@example.com"));
        assert!(is_valid_email("john.doe+tag@domain.co.uk"));
    }

    #[test]
    fn test_invalid_email() {
        assert!(!is_valid_email("not-an-email"));
        assert!(!is_valid_email("@example.com"));
        assert!(!is_valid_email("user@"));
    }

    #[test]
    fn test_parse_recipients() {
        let result = parse_recipients("alice@test.com, bob@test.com");
        assert_eq!(result.len(), 2);
        assert_eq!(result[0], "alice@test.com");
        assert_eq!(result[1], "bob@test.com");
    }

    #[test]
    fn test_compose_validation() {
        let mut bridge = ComposeBridge::new();

        // Should fail: no recipient
        assert!(bridge.validate().is_err());

        // Add recipient
        bridge.set_to("test@example.com".to_string());
        assert!(bridge.validate().is_err()); // Still fails: no subject

        // Add subject
        bridge.set_subject("Test Subject".to_string());
        assert!(bridge.validate().is_ok()); // Should pass now
    }

    #[test]
    fn test_clear() {
        let mut bridge = ComposeBridge::new();
        bridge.set_to("test@example.com".to_string());
        bridge.set_subject("Test".to_string());
        bridge.set_body("Body".to_string());

        bridge.clear();
        assert!(bridge.get_to().is_empty());
        assert!(bridge.get_subject().is_empty());
        assert!(bridge.get_body().is_empty());
    }
}
