/// Compose bridge module - exposes email composition to QML
/// Phase 2: Email send integration with Microsoft Graph

use log::info;

/// ComposeBridge - QML-accessible email composition interface
pub struct ComposeBridge {
    to: String,
    cc: String,
    bcc: String,
    subject: String,
    body: String,
}

impl Default for ComposeBridge {
    fn default() -> Self {
        ComposeBridge {
            to: String::new(),
            cc: String::new(),
            bcc: String::new(),
            subject: String::new(),
            body: String::new(),
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
    }

    /// Set recipient
    pub fn set_to(&mut self, email: String) {
        info!("ComposeBridge::set_to() - {}", email);
        self.to = email;
    }

    /// Set subject
    pub fn set_subject(&mut self, subject: String) {
        self.subject = subject;
    }

    /// Set email body
    pub fn set_body(&mut self, body: String) {
        self.body = body;
    }

    /// Send email via Microsoft Graph
    pub fn send(&mut self) -> Result<(), String> {
        if self.to.is_empty() {
            return Err("Recipient required".to_string());
        }
        if self.subject.is_empty() {
            return Err("Subject required".to_string());
        }

        info!(
            "ComposeBridge::send() - to: {}, subject: {}",
            self.to, self.subject
        );

        // TODO: Call graph API to send email
        // For now, placeholder
        Ok(())
    }

    pub fn get_to(&self) -> &str {
        &self.to
    }

    pub fn get_subject(&self) -> &str {
        &self.subject
    }

    pub fn get_body(&self) -> &str {
        &self.body
    }
}
