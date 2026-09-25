"""QML ↔ Python bridge for authentication."""
import asyncio
import logging
from typing import Optional, Dict
from PySide6.QtCore import QObject, Signal, Slot, Property, QThread
import threading

logger = logging.getLogger(__name__)


class AsyncWorker(QThread):
    """Worker thread to run async Device Flow login without blocking Qt UI."""

    loginSucceeded = Signal()
    loginFailed = Signal(str)  # error message

    def __init__(self, auth_manager):
        super().__init__()
        self.auth_manager = auth_manager

    def run(self):
        """Run Device Flow login in background thread."""
        loop = None
        try:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            success = loop.run_until_complete(self.auth_manager.login())
            if success:
                self.loginSucceeded.emit()
            else:
                self.loginFailed.emit("Authentication failed")
        except Exception as e:
            logger.error(f"Device Flow exception: {e}")
            self.loginFailed.emit(str(e))
        finally:
            if loop:
                loop.close()


class AuthBridge(QObject):
    """Bridge between QML login UI and Python authentication backend."""

    # Signals
    loginSucceeded = Signal()
    loginFailed = Signal(str)  # error message
    logoutSucceeded = Signal()
    accountChanged = Signal()

    def __init__(self, auth_manager):
        super().__init__()
        self.auth_manager = auth_manager
        self._is_authenticated = auth_manager.is_authenticated()
        self._worker = None

    @Property(bool, notify=accountChanged)
    def isAuthenticated(self) -> bool:
        """Check if user is authenticated."""
        return self._is_authenticated

    @Property(str, notify=accountChanged)
    def displayName(self) -> str:
        """Get user's display name."""
        account = self.auth_manager.get_account()
        if account:
            return account.get("name", "Microsoft 365 User")
        return ""

    @Property(str, notify=accountChanged)
    def username(self) -> str:
        """Get user's email/username."""
        account = self.auth_manager.get_account()
        if account:
            return account.get("username", "")
        return ""

    @Slot()
    def login(self):
        """Initiate Device Flow login in background thread."""
        logger.info("Device Flow login initiated from QML")

        # Create worker thread to run async login
        self._worker = AsyncWorker(self.auth_manager)
        self._worker.loginSucceeded.connect(self._on_login_succeeded)
        self._worker.loginFailed.connect(self._on_login_failed)
        self._worker.start()

    def _on_login_succeeded(self):
        """Handle successful login."""
        self._is_authenticated = True
        self.loginSucceeded.emit()
        self.accountChanged.emit()
        logger.info("Device Flow login succeeded")
        if self._worker:
            self._worker.quit()
            self._worker.wait()

    def _on_login_failed(self, error_msg: str):
        """Handle failed login."""
        self.loginFailed.emit(error_msg or "Authentication failed")
        logger.error(f"Device Flow login failed: {error_msg}")
        if self._worker:
            self._worker.quit()
            self._worker.wait()

    @Slot()
    def logout(self):
        """Log out and clear cached tokens."""
        logger.info("Logout initiated from QML")
        success = self.auth_manager.logout()

        if success:
            self._is_authenticated = False
            self.logoutSucceeded.emit()
            self.accountChanged.emit()
            logger.info("Logout succeeded")
        else:
            logger.error("Logout failed")

    @Slot(result=str)
    def getFirstLetterAvatar(self) -> str:
        """Get first letter of display name for avatar."""
        name = self.displayName
        if name:
            return name[0].upper()
        return "?"
