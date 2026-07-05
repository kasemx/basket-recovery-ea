# Sprint 9C-A — Local Telegram Route Dashboard Runbook

Phase 9C-A delivers a **local-only** dashboard foundation using Python stdlib HTTP server, SQLite, and vanilla HTML/CSS/JS.

## Requirements

- Python **3.11+**
- Standard library only (no npm, no FastAPI, no Telethon in dashboard server)
- Browser access via **127.0.0.1 only**

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

Startup log:

```text
dashboard_event=SERVER_READY host=127.0.0.1 port=8787
```

## Security notes

- Binding to any host other than `127.0.0.1` is **rejected**.
- API ID, API hash, login code, 2FA password, and session strings are **never** accepted by dashboard API bodies.
- Phone numbers are stored **masked only** (e.g. `+90******4567`).
- Local data directory (`integrations/telegram/local-data/`) is Git-ignored.
- This panel **does not** grant broker execution authority.

## What works in 9C-A

| Feature | Status |
|---------|--------|
| Overview / safety badges | Available |
| Telegram configure (masked phone + present flags) | Available |
| Telegram login / code / 2FA | **NOT_IMPLEMENTED** (Phase 9C-B) |
| Local demo channel import | Available |
| Channel tracking toggle | Available |
| MT5 target CRUD (observer-only) | Available |
| Route CRUD (OBSERVER_ONLY only) | Available |
| Audit log (redacted) | Available |
| FILE_COMMON publish | **NOT_IMPLEMENTED** |
| EA attach/control | **NOT_IMPLEMENTED** |

## Typical local workflow

1. Start dashboard server.
2. Open Overview — confirm broker execution disabled badges.
3. Telegram page:
   - Check API configured locally flags.
   - Enter phone in international format.
   - Click **Configure Local Session** (stores masked phone only).
4. Channels page:
   - Click **Import Local Demo Channels** (3 demo records, `source=LOCAL_DEMO_DATA`).
   - Toggle tracking switches.
5. MT5 Targets page:
   - Add a DEMO target with FILE_COMMON root and seed/details basenames.
   - Observer-only remains locked.
6. Routes page:
   - Create observer-only route linking channel + target.
7. Audit page:
   - Refresh events or add demo event (`route_event=SIMULATED_OBSERVER_BLOCKED`).

## Environment template

See `integrations/telegram/.env.example`:

```text
DASHBOARD_HOST=127.0.0.1
DASHBOARD_PORT=8787
DASHBOARD_DATA_DIR=integrations/telegram/local-data
TELEGRAM_API_ID=
TELEGRAM_API_HASH=
...
```

Real values stay in local `.env` only — never commit them.

## Phase 9C-B (next)

- Telethon adapter for real login and private channel sync
- Read API ID/hash/session from local environment (not dashboard POST bodies)
- Optional bridge integration for observer-only FILE_COMMON publish

## Bridge relationship

Existing bridge remains separate:

- `integrations/telegram/fasttrack_file_bridge.py`
- Dashboard stores route/target metadata only in this sprint
- No publish or EA control from dashboard yet

## Running tests

```powershell
python -m unittest integrations.telegram.tests.test_dashboard_server -v
python -m unittest integrations.telegram.tests.test_atomic_publish -v
```

Tests use temporary directories only — no Telegram network, no D0E FILE_COMMON, no EA attach.

## Broker/state boundary

Dashboard foundation does not:

- Connect to Telegram API
- Write FILE_COMMON files
- Attach BasketRecoveryEA
- Submit broker orders or issue tokens
- Modify pending/basket/state files
