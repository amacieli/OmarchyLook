"""Settings manager for omarchy-look with file watching and QML bindings."""
import logging
from pathlib import Path
from typing import Any, Optional
import tomllib
import tomli_w
from dataclasses import dataclass, field, asdict
from threading import Thread
import time

from PySide6.QtCore import QObject, Signal, Slot
from watchfiles import watch

logger = logging.getLogger(__name__)


@dataclass
class FontSettings:
    """Font configuration."""
    family: str = "monospace"
    base_size: int = 10
    scale_factor: float = 1.0

    def get_scaled_size(self, base: int = None) -> int:
        """Get a size scaled by the scale factor."""
        size = base if base is not None else self.base_size
        return max(1, int(size * self.scale_factor))

    def title_size(self) -> int:
        """Get title font size (1.2x base)."""
        return self.get_scaled_size(int(self.base_size * 1.2))

    def hint_size(self) -> int:
        """Get hint font size (0.8x base)."""
        return max(8, self.get_scaled_size(int(self.base_size * 0.8)))


@dataclass
class ColorSettings:
    """TUI color palette."""
    bg_dark: str = "#0d0d0d"
    bg_surface: str = "#242424"
    border: str = "#333333"
    text_primary: str = "#e8e8e8"
    text_secondary: str = "#888888"
    accent_purple: str = "#7c6af7"
    danger_red: str = "#ff6b6b"
    success_green: str = "#51cf66"


@dataclass
class UISettings:
    """UI/UX configuration."""
    window_width: int = 1280
    window_height: int = 800
    use_tui_style: bool = True
    animation_enabled: bool = True


@dataclass
class Settings:
    """Root settings object."""
    font: FontSettings = field(default_factory=FontSettings)
    color: ColorSettings = field(default_factory=ColorSettings)
    ui: UISettings = field(default_factory=UISettings)

    @classmethod
    def from_dict(cls, data: dict) -> "Settings":
        """Create Settings from a dictionary."""
        font_data = data.get("font", {})
        color_data = data.get("color", {})
        ui_data = data.get("ui", {})

        return cls(
            font=FontSettings(**{k: v for k, v in font_data.items() if k in FontSettings.__dataclass_fields__}),
            color=ColorSettings(**{k: v for k, v in color_data.items() if k in ColorSettings.__dataclass_fields__}),
            ui=UISettings(**{k: v for k, v in ui_data.items() if k in UISettings.__dataclass_fields__}),
        )

    def to_dict(self) -> dict:
        """Convert to dictionary for TOML serialization."""
        return asdict(self)


class SettingsManager(QObject):
    """Thread-safe settings manager with file watching and QML signals."""

    # Signals
    settingsChanged = Signal()  # General change signal
    fontSettingsChanged = Signal()
    colorSettingsChanged = Signal()
    uiSettingsChanged = Signal()

    def __init__(self, config_dir: Optional[Path] = None):
        """Initialize settings manager.

        Args:
            config_dir: Config directory path. Defaults to ~/.config/omarchylook/
        """
        super().__init__()
        self._config_dir = config_dir or Path.home() / ".config" / "omarchylook"
        self._config_dir.mkdir(parents=True, exist_ok=True)
        self._settings_file = self._config_dir / "settings.toml"
        self._settings: Settings = Settings()
        self._watch_thread: Optional[Thread] = None
        self._watching = False

        # Load initial settings
        self.load()

        # Start file watcher
        self.start_watching()

    def load(self) -> None:
        """Load settings from file, creating default if missing."""
        try:
            if self._settings_file.exists():
                with open(self._settings_file, "rb") as f:
                    data = tomllib.load(f)
                self._settings = Settings.from_dict(data)
                logger.info(f"Loaded settings from {self._settings_file}")
            else:
                # Create default settings file
                self.save()
                logger.info(f"Created default settings at {self._settings_file}")
        except Exception as e:
            logger.error(f"Failed to load settings: {e}. Using defaults.")
            self._settings = Settings()

    def save(self) -> None:
        """Save settings to file."""
        try:
            with open(self._settings_file, "wb") as f:
                tomli_w.dump(self._settings.to_dict(), f)
            logger.info(f"Saved settings to {self._settings_file}")
        except Exception as e:
            logger.error(f"Failed to save settings: {e}")

    def start_watching(self) -> None:
        """Start file watcher in background thread."""
        if self._watching:
            return

        self._watching = True
        self._watch_thread = Thread(target=self._watch_file, daemon=True)
        self._watch_thread.start()
        logger.info("Settings file watcher started")

    def stop_watching(self) -> None:
        """Stop file watcher."""
        self._watching = False
        if self._watch_thread:
            self._watch_thread.join(timeout=2)

    def _watch_file(self) -> None:
        """Watch settings file for changes (runs in background thread)."""
        try:
            for changes in watch(str(self._config_dir), watch_filter=lambda x: "omarchylook.toml" in str(x)):
                if not self._watching:
                    break
                # Debounce rapid changes
                time.sleep(0.1)
                self.load()
                # Emit signals from main thread via queued connection
                self.settingsChanged.emit()
                self.fontSettingsChanged.emit()
                self.colorSettingsChanged.emit()
                self.uiSettingsChanged.emit()
                logger.info("Settings file changed, reloaded")
        except Exception as e:
            logger.error(f"File watcher error: {e}")

    # Getter properties for QML
    @Slot(result=int)
    def get_font_base_size(self) -> int:
        """Get current font base size (unscaled)."""
        return self._settings.font.base_size

    @Slot(result=int)
    def get_base_size(self) -> int:
        """Get current scaled base font size (used for QML)."""
        return self._settings.font.get_scaled_size()

    @Slot(result=float)
    def get_font_scale_factor(self) -> float:
        """Get current font scale factor."""
        return self._settings.font.scale_factor

    @Slot(result=str)
    def get_font_family(self) -> str:
        """Get current font family."""
        return self._settings.font.family

    @Slot(result=int)
    def get_scaled_size(self, base: int = None) -> int:
        """Get a size scaled by the scale factor."""
        return self._settings.font.get_scaled_size(base)

    @Slot(result=int)
    def get_title_size(self) -> int:
        """Get title font size."""
        return self._settings.font.title_size()

    @Slot(result=int)
    def get_hint_size(self) -> int:
        """Get hint font size."""
        return self._settings.font.hint_size()

    # Color getters
    @Slot(result=str)
    def get_color_bg_dark(self) -> str:
        return self._settings.color.bg_dark

    @Slot(result=str)
    def get_color_bg_surface(self) -> str:
        return self._settings.color.bg_surface

    @Slot(result=str)
    def get_color_border(self) -> str:
        return self._settings.color.border

    @Slot(result=str)
    def get_color_text_primary(self) -> str:
        return self._settings.color.text_primary

    @Slot(result=str)
    def get_color_text_secondary(self) -> str:
        return self._settings.color.text_secondary

    @Slot(result=str)
    def get_color_accent_purple(self) -> str:
        return self._settings.color.accent_purple

    @Slot(result=str)
    def get_color_danger_red(self) -> str:
        return self._settings.color.danger_red

    @Slot(result=str)
    def get_color_success_green(self) -> str:
        return self._settings.color.success_green

    # UI getters
    @Slot(result=int)
    def get_ui_window_width(self) -> int:
        return self._settings.ui.window_width

    @Slot(result=int)
    def get_ui_window_height(self) -> int:
        return self._settings.ui.window_height

    @Slot(result=bool)
    def get_ui_use_tui_style(self) -> bool:
        return self._settings.ui.use_tui_style

    @Slot(result=bool)
    def get_ui_animation_enabled(self) -> bool:
        return self._settings.ui.animation_enabled
