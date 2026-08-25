# Sprint 9C — Local Telegram Route Dashboard Runbook

Phase 9C delivers a **local-only** dashboard using Python stdlib HTTP server, SQLite, vanilla HTML/CSS/JS, and an optional Telethon adapter for login and channel sync.

## Requirements

- Python **3.11+**
- Dashboard server: standard library only
- Telethon (optional, for login/sync): `pip install telethon`
- Browser access via **127.0.0.1 only**

## Data directory (deterministic)

Default dashboard data directory (absolute, CWD-independent):

```text
%LOCALAPPDATA%\BasketRecoveryEA\TelegramDashboard
```

Override precedence:

1. CLI `--data-dir`
2. `DASHBOARD_DATA_DIR` environment variable
3. `%LOCALAPPDATA%\BasketRecoveryEA\TelegramDashboard` (Windows)
4. Package fallback: `integrations/telegram/local-data` (dev/non-Windows)

Vault file:

```text
<dashboard-data-dir>/telegram_credentials.dpapi
```

SQLite:

```text
<dashboard-data-dir>/dashboard.sqlite3
```

### Migration from repo-local vault

If credentials were saved under `integrations/telegram/local-data/` before this fix, either:

- Start once with `--data-dir integrations/telegram/local-data`, or
- Copy `telegram_credentials.dpapi` into `%LOCALAPPDATA%\BasketRecoveryEA\TelegramDashboard\`

## Environment

No PowerShell environment variables are required for API ID/hash when using the DPAPI vault.

Optional settings:

```text
TELEGRAM_SESSION_PATH=C:\path\to\custom\telegram.session
DASHBOARD_HOST=127.0.0.1
DASHBOARD_PORT=8787
DASHBOARD_DATA_DIR=C:\custom\dashboard\data
```

If `TELEGRAM_SESSION_PATH` is omitted, session defaults to:

```text
<dashboard-data-dir>/telegram_dashboard.session
```

The session **file** is created on first successful login. A missing session file does **not** block Configure Phone or `config_ready`.

Legacy environment fallback (optional):

```text
TELEGRAM_API_ID=your_api_id
TELEGRAM_API_HASH=your_api_hash
```

Credential source precedence:

1. Windows DPAPI vault (`<dashboard-data-dir>/telegram_credentials.dpapi`)
2. Environment (`TELEGRAM_API_ID` / `TELEGRAM_API_HASH`)
3. Otherwise `TELEGRAM_CONFIG_MISSING`
## Credential vault (9C-B.1)

1. Open dashboard Telegram page on Windows.
2. Enter API ID and API Hash from my.telegram.org.
3. Click **Save Credentials (DPAPI)**.
4. Use **Clear Saved Credentials** to remove the vault file.

Credentials are encrypted for the current Windows user only. They are not stored in SQLite, audit logs, `.env`, or Git.

## Start dashboard

From repository root (default data-dir is `%LOCALAPPDATA%\BasketRecoveryEA\TelegramDashboard`):

```powershell
python integrations/telegram/telegram_dashboard_server.py `
  --host 127.0.0.1 `
  --port 8787 `
  --dashboard-dir integrations/telegram/dashboard
```

Optional explicit data-dir (migration or dev):

```powershell
python integrations/telegram/telegram_dashboard_server.py `
  --host 127.0.0.1 `
  --port 8787 `
  --data-dir integrations/telegram/local-data `
  --dashboard-dir integrations/telegram/dashboard
```
Open:

```text
http://127.0.0.1:8787
```

## Security notes

- Binding to any host other than `127.0.0.1` is **rejected**.
- API ID, API hash, login code, 2FA password, and session strings are **never** accepted in dashboard POST bodies.
- Phone numbers are stored **masked only** (e.g. `+90******4567`).
- Session path is stored **masked**; session file content is never written to SQLite.
- `phone_code_hash` is stored in DB for login flow but never returned in API responses or audit logs.
- Local data directory is Git-ignored.
- This panel **does not** grant broker execution authority.

## Telegram login workflow (9C-B)

1. Save API credentials via DPAPI vault (or legacy env fallback).
2. Start dashboard; open Telegram page.
3. Confirm badges: **Credentials saved**, **Telethon installed**.
4. Enter phone in international format → **Configure Phone**.
5. Click **Request Code** (Telegram sends SMS/app code).
6. Enter code → **Verify Code**.
7. If 2FA enabled, enter password → **Verify 2FA**.
8. When status is `CONNECTED`, click **Sync Channels**.
9. Channels page shows synced records with `source=TELEGRAM`.
10. Toggle tracking for JustGoldDan. Fake “örnek kanal” import is not available.

## Diagnostics (secret-safe)

`GET /api/telegram/diagnostics` returns:

```json
{
  "vault_supported": true,
  "vault_file_present": true,
  "vault_credentials_available": true,
  "credential_source": "WINDOWS_DPAPI_VAULT",
  "session_path_resolved": true,
  "session_parent_exists": true,
  "session_file_exists": false,
  "data_dir_consistent": true,
  "last_safe_error_code": null
}
```

No API ID/hash, phone, code, password, session content, or raw filesystem paths are returned.

## What works in 9C-B

| Feature | Status |
|---------|--------|
| Overview / safety badges | Available |
| Telegram configure (masked phone, DPAPI/env credentials) | Available |
| Telegram login (code + 2FA) | Available (local Telethon) |
| Channel sync from Telegram | Available (on-demand) |
| Channel tracking toggle | Available |
| MT5 target CRUD (observer-only) | Available |
| Route CRUD (OBSERVER_ONLY only) | Available |
| Audit log (redacted) | Available |
| FILE_COMMON publish | Candidate test armed: one real write; otherwise dry-run |
| EA attach/control | **NOT_IMPLEMENTED** |
| Telegram message listener | Observer + candidate-test arm (`DASHBOARD_ROUTE_LISTENER_TELETHON=1` for live Telegram) |
| Route publish to FILE_COMMON | Dry-run by default; armed candidate test writes `br_d0e_justgold_*.txt` once |

## Route listener (Sprint 9C-C)

Observer-only routes can be started from **Sinyal Yönlendirmeleri** via **Takibi Başlat**. The in-process `RouteListenerManager`:

- Requires Telegram **CONNECTED**, channel tracking on, active route/target, `OBSERVER_ONLY` mode
- Does **not** backfill historical messages
- Uses existing `AtomicPublisher` from `fasttrack_file_bridge.py`
- Writes audit/route events with safe metadata only (no raw Telegram text)
- Defaults to **dry-run** publish (no FILE_COMMON files on disk)

Environment flags:

| Variable | Default | Meaning |
|----------|---------|---------|
| `DASHBOARD_ROUTE_LISTENER_DRY_RUN` | `1` | Log publish plan only; no atomic file write |
| `DASHBOARD_ROUTE_LISTENER_TELETHON` | `0` | Do not attach real Telethon message hook |

When `DASHBOARD_ROUTE_LISTENER_TELETHON=1`, the dashboard starts a **single** Telethon client on a dedicated asyncio daemon thread. Channel routing uses a **canonical channel key** so legacy positive `entity.id` values (e.g. `1234567890`) match live `event.chat_id` values (e.g. `-1001234567890`). No backfill is performed. Dashboard restart normalizes stale DB listener rows to `LISTENER_STOPPED`; in-memory runtimes are not restored automatically.

API endpoints:

- `GET /api/listener/status`
- `GET /api/routes/<id>/listener-status`
- `POST /api/routes/<id>/listener/start`
- `POST /api/routes/<id>/listener/stop`
- `GET /api/routes/<id>/events?limit=50`

## Bridge relationship

Existing bridge remains separate:

- `integrations/telegram/fasttrack_file_bridge.py`
- Dashboard stores route/target metadata and syncs channels only
- No publish or EA control from dashboard

## Running tests

```powershell
python -m py_compile integrations/telegram/route_listener_service.py
python -m py_compile integrations/telegram/dashboard_vault.py
python -m py_compile integrations/telegram/telegram_adapter.py
python -m py_compile integrations/telegram/dashboard_api.py
python -m py_compile integrations/telegram/dashboard_store.py
python -m py_compile integrations/telegram/dashboard_security.py
python -m py_compile integrations/telegram/dashboard_server.py

python -m unittest integrations.telegram.tests.test_dashboard_server -v
python -m unittest integrations.telegram.tests.test_atomic_publish -v
```

Tests use fake adapters and temporary directories — no real Telegram network, no D0E FILE_COMMON, no EA attach.

## Dashboard language

The web UI at `http://127.0.0.1:8787` is **Turkish-first** with a three-step Telegram wizard, numbered overview roadmap, and simplified status labels. Technical error codes are hidden behind **Teknik Durumu Göster** on the Telegram page.

API endpoints, payloads, and SQLite schema are unchanged.

Dashboard does not:

- Write FILE_COMMON files
- Attach BasketRecoveryEA
- Submit broker orders or issue tokens
- Modify pending/basket/state files
- Start Telegram message listeners
