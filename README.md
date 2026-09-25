# Omarchy-Look: QML Outlook Clone

A native Linux desktop email/calendar/contacts/tasks client built in **Qt/QML**, styled to match the Omarchy aesthetic (dark, minimal, keyboard-first). Connects exclusively to **Microsoft 365 / Exchange Online** via the **Microsoft Graph REST API**.

## Features (Roadmap)

- ✓ Phase 1: OAuth 2.0 authentication via MSAL
- ✓ Phase 2: App shell with navigation
- ⏳ Phase 3: Mail module (read-only)
- ⏳ Phase 4: Mail compose & actions
- ⏳ Phase 5: Categories
- ⏳ Phase 6: Calendar module
- ⏳ Phase 7: Contacts module
- ⏳ Phase 8: Tasks module
- ⏳ Phase 9: Polish & packaging

## Project Structure

```
omarchy-look/
├── main.py                  # Entry point
├── pyproject.toml          # Dependencies
├── qml/                    # QML UI layer
│   └── App.qml            # Main window
├── backend/               # Python backend
│   ├── auth.py            # MSAL authentication
│   ├── graph_client.py    # Graph API wrapper
│   ├── bridges.py         # QML ↔ Python interface
│   └── __init__.py
├── DESIGN.md              # Full architecture spec
├── PLAN.md                # Phased implementation plan
└── README.md              # This file
```

## Requirements

- Python 3.10+
- Qt 6.x (via PySide6)
- Microsoft 365 account

## Setup

1. **Clone and set up environment**
   ```
   cd /mnt/ai/projects/omarchy-look
   uv venv
   source .venv/bin/activate  # or .venv/Scripts/activate on Windows
   uv pip install -e .
   ```

2. **Azure App Registration** (One-time setup)
   - Go to [portal.azure.com](https://portal.azure.com)
   - New App Registration → "omarchy-look"
   - Platform: Mobile and desktop application
   - Redirect URI: `http://localhost`
   - Required scopes: `User.Read`, `Mail.ReadWrite`, `Mail.Send`, `Calendars.ReadWrite`, `Contacts.ReadWrite`, `Tasks.ReadWrite`, `offline_access`
   - Copy `client_id` and `tenant_id`

3. **Configure**
   ```
   cp .env.example .env
   # Edit .env with your AZURE_CLIENT_ID and AZURE_TENANT_ID
   ```

4. **Run**
   ```
   python main.py
   ```

## Documentation

- **DESIGN.md** — Full architecture, endpoints, UI layout, error handling
- **PLAN.md** — Phase-by-phase implementation roadmap (1–9 phases, ~15–22 sessions total)

## Authentication Flow

1. App launches and checks for cached authentication
2. If none found, shows login screen
3. User clicks "Sign in with Microsoft"
4. Browser opens to Microsoft identity platform
5. After login, browser redirects to loopback with auth code
6. MSAL exchanges code for access + refresh tokens
7. Tokens cached in OS keyring (SecretService/KWallet on Linux)
8. App displays user's name in top bar
9. On relaunch, tokens refresh silently

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI framework | Qt 6 / QML |
| Backend | Python 3.10+ with PySide6 |
| Auth | MSAL Python (msal library) |
| API client | httpx (async) |
| Cache | SQLite (aiosqlite) |
| Build | pyproject.toml + uv |

## Keyboard Shortcuts (Phase 2+)

- `1`–`4` — Switch modules (Mail, Calendar, Contacts, Tasks)
- `Ctrl+\` — Toggle nav rail collapse
- `Ctrl+R` — Manual sync
- `?` — Show shortcuts overlay

## Development Notes

- **No Electron.** This is a real, native Qt application.
- **Offline-capable.** All data cached locally; syncs on reconnect.
- **Graph-only.** No IMAP/SMTP — all via Microsoft Graph REST API.
- **Keyboard-first.** Full keybinding coverage; mouse optional.
- **Omarchy aesthetic.** Dark background (#1a1a1a), Inter/JetBrains Mono, rounded cards.

## References

- [Microsoft identity platform](https://learn.microsoft.com/azure/active-directory/develop/v2-overview)
- [Microsoft Graph overview](https://learn.microsoft.com/graph/overview)
- [MSAL Python](https://learn.microsoft.com/azure/active-directory/develop/msal-overview)
- [PySide6 docs](https://doc.qt.io/qtforpython-6/)
- [Qt QML docs](https://doc.qt.io/qt-6/qtqml-index.html)

## License

MIT
