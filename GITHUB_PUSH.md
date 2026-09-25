# Push omarchy-look to GitHub

Your code is ready. To push to GitHub, use these commands:

## Option 1: Create repo via GitHub web UI, then push

1. Go to https://github.com/new
2. Name: `omarchy-look`
3. Description: "Omarchy-style QML Outlook clone using Microsoft Graph"
4. Public
5. Click "Create repository"
6. Then run:

```bash
cd /mnt/ai/projects/omarchy-look
git remote add origin https://github.com/amacieli/omarchy-look.git
git branch -M main
git push -u origin main
```

## Option 2: Use GitHub CLI with a token that has repo scope

If your current token doesn't have `repo` scope, create a new Personal Access Token:
1. Go to https://github.com/settings/tokens
2. Generate new token (classic)
3. Select scopes: `repo` (all), `gist`, `read:user`
4. Copy the token
5. Run: `gh auth login` and paste the token
6. Then: `gh repo create amacieli/omarchy-look --public --source=. --remote=origin --push`

## Repository Contents (Phase 1 — Complete)

### Python Backend
- `backend/auth.py` — MSAL authentication manager with OS keyring caching
- `backend/graph_client.py` — Microsoft Graph API async HTTP client (429 handling, pagination)
- `backend/bridges.py` — QML ↔ Python bridge via Qt signals/slots
- `main.py` — Entry point: loads .env, initializes auth, launches QML engine

### QML Frontend
- `qml/App.qml` — Main window, loader that switches between LoginScreen and AppShell
- `qml/LoginScreen.qml` — Sign-in button, calls authBridge.login() → opens browser
- `qml/AppShell.qml` — Placeholder shell with nav rail + content area (Phase 2)
- `qml/TopBar.qml` — Top bar with user avatar, account menu, sync indicator

### Configuration
- `pyproject.toml` — Dependencies: PySide6, msal, httpx, aiosqlite, keyring, python-dotenv
- `.env.example` — Template for AZURE_CLIENT_ID and AZURE_TENANT_ID
- `.gitignore` — Python, Qt, venv, .env
- `setup.sh` — Automated venv + pip install

### Documentation
- `README.md` — Quick start, features, tech stack
- `DESIGN.md` — Full architecture (endpoints, auth flow, UI layout, error handling)
- `PLAN.md` — 9-phase roadmap (Phase 1 complete, Phase 2 next)

## Phase 1 Deliverables ✓

✅ Azure App Registration setup (manual, documented)
✅ Python environment with uv-ready pyproject.toml
✅ MSAL authentication with OS keyring caching
✅ Interactive login via system browser + loopback redirect
✅ Silent token refresh on relaunch
✅ QML login screen (styled to Omarchy aesthetic)
✅ QML app shell with top bar + nav placeholder
✅ AuthBridge for QML ↔ Python communication
✅ GraphClient for async Graph API calls
✅ Error handling (401, 403, 429)

## Next: Phase 2 — App Shell & Navigation

When ready:
- Implement NavRail.qml with Mail/Calendar/Contacts/Tasks
- Wire keyboard shortcuts (1–4 to switch modules)
- Add Ctrl+\ to toggle nav collapse
- Implement smooth view transitions
- Add sync status indicator wiring

---

**Local path:** `/mnt/ai/projects/omarchy-look`
**Status:** Ready for GitHub push
**Size:** 531 KB, 2 commits, 9 source files
