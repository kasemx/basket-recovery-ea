# Sprint 9C — Local Telegram Route Dashboard Runbook

Phase 9C delivers a **local-only** dashboard using Python stdlib HTTP server, SQLite, vanilla HTML/CSS/JS, and an optional Telethon adapter for login and channel sync.

## Requirements

- Python **3.11+**
- Dashboard server: standard library only
- Telethon (optional, for login/sync): `pip install telethon`
- Browser access via **127.0.0.1 only**

## Environment

Set these in your local environment (never commit values):

```text
TELEGRAM_API_ID=your_api_id
TELEGRAM_API_HASH=your_api_hash
TELEGRAM_SESSION_PATH=integrations/telegram/local-data/dashboard.session
DASHBOARD_HOST=127.0.0.1
DASHBOARD_PORT=8787
DASHBOARD_DATA_DIR=integrations/telegram/local-data
```

See `integrations/telegram/.env.example` for the full template.

## Start dashboard

From repository root:

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

1. Set `TELEGRAM_API_ID`, `TELEGRAM_API_HASH`, `TELEGRAM_SESSION_PATH` in environment.
2. Start dashboard; open Telegram page.
3. Confirm badges: **Environment config ready** and **Telethon installed**.
4. Enter phone in international format → **Configure Phone**.
5. Click **Request Code** (Telegram sends SMS/app code).
6. Enter code → **Verify Code**.
7. If 2FA enabled, enter password → **Verify 2FA**.
8. When status is `CONNECTED`, click **Sync Channels**.
9. Channels page shows synced records with `source=TELEGRAM`.
10. Toggle tracking as needed. Demo import remains available (`source=LOCAL_DEMO_DATA`).

## What works in 9C-B

| Feature | Status |
|---------|--------|
| Overview / safety badges | Available |
| Telegram configure (masked phone, env credentials) | Available |
| Telegram login (code + 2FA) | Available (local Telethon) |
| Channel sync from Telegram | Available (on-demand) |
| Local demo channel import | Available |
| Channel tracking toggle | Available |
| MT5 target CRUD (observer-only) | Available |
| Route CRUD (OBSERVER_ONLY only) | Available |
| Audit log (redacted) | Available |
| FILE_COMMON publish | **NOT_IMPLEMENTED_IN_DASHBOARD** |
| EA attach/control | **NOT_IMPLEMENTED** |
| Telegram message listener | **NOT_IMPLEMENTED** |

## Bridge relationship

Existing bridge remains separate:

- `integrations/telegram/fasttrack_file_bridge.py`
- Dashboard stores route/target metadata and syncs channels only
- No publish or EA control from dashboard

## Running tests

```powershell
python -m py_compile integrations/telegram/telegram_adapter.py
python -m py_compile integrations/telegram/dashboard_api.py
python -m py_compile integrations/telegram/dashboard_store.py
python -m py_compile integrations/telegram/dashboard_security.py
python -m py_compile integrations/telegram/dashboard_server.py

python -m unittest integrations.telegram.tests.test_dashboard_server -v
python -m unittest integrations.telegram.tests.test_atomic_publish -v
```

Tests use fake adapters and temporary directories — no real Telegram network, no D0E FILE_COMMON, no EA attach.

## Broker/state boundary

Dashboard does not:

- Write FILE_COMMON files
- Attach BasketRecoveryEA
- Submit broker orders or issue tokens
- Modify pending/basket/state files
- Start Telegram message listeners
