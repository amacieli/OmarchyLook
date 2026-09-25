#!/usr/bin/env python3
"""Entry point for omarchy-look."""
import sys
import os
import logging
from pathlib import Path
from dotenv import load_dotenv

from PySide6.QtWidgets import QApplication
from PySide6.QtQml import QQmlApplicationEngine

from backend import AuthManager, AuthBridge
from backend.settings import SettingsManager

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


def main():
    """Launch the application."""
    # Load environment variables from .env (optional now)
    env_path = Path(__file__).parent / ".env"
    load_dotenv(env_path)

    logger.info("Starting omarchy-look...")

    # Initialize Qt application
    app = QApplication(sys.argv)

    # Set app metadata
    app.setApplicationName("omarchy-look")
    app.setApplicationVersion("0.1.0")

    # Initialize authentication (no credentials needed; uses public client ID)
    logger.info("Initializing authentication...")
    auth_manager = AuthManager()

    # Create auth bridge for QML
    auth_bridge = AuthBridge(auth_manager)
    
    # Initialize settings manager
    logger.info("Initializing settings...")
    settings_manager = SettingsManager()
    
    # **CRITICAL**: Keep auth_bridge and settings_manager alive for the lifetime of the app
    app.authBridge = auth_bridge
    app.settingsManager = settings_manager

    # Load QML engine
    logger.info("Loading QML engine...")
    engine = QQmlApplicationEngine()

    # Register auth bridge as context property for QML (root level)
    ctx = engine.rootContext()
    ctx.setContextProperty("authBridge", auth_bridge)
    ctx.setContextProperty("settingsManager", settings_manager)

    # Load main QML file
    qml_path = Path(__file__).parent / "qml" / "App.qml"
    engine.load(str(qml_path))

    if not engine.rootObjects():
        logger.error("Failed to load QML")
        sys.exit(1)

    logger.info("Application started successfully")
    
    # Check if user is already authenticated (cached tokens exist)
    if auth_manager.is_authenticated():
        logger.info("Cached tokens found, restoring session...")
        # Load cached tokens into the manager
        cached_token = auth_manager._get_cached_refresh_token()
        if cached_token:
            auth_manager.refresh_token = cached_token
            logger.info("Tokens restored from cache, emitting loginSucceeded signal")
            # Emit signal to tell QML to skip login and go to app shell
            auth_bridge.loginSucceeded.emit()
    else:
        logger.info("No cached tokens, showing login screen")
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
