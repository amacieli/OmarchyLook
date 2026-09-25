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

    # Load QML engine
    logger.info("Loading QML engine...")
    engine = QQmlApplicationEngine()

    # Register auth bridge as context property for QML
    engine.rootContext().setContextProperty("authBridge", auth_bridge)

    # Load main QML file
    qml_path = Path(__file__).parent / "qml" / "App.qml"
    engine.load(str(qml_path))

    if not engine.rootObjects():
        logger.error("Failed to load QML")
        sys.exit(1)

    logger.info("Application started successfully")
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
