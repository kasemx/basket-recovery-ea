# Sprint 9B — Offline FastTrack File Bridge Runbook

Phase 1 delivers a **stdin simulator** and **atomic FILE_COMMON publisher** with no Telegram, Telethon, network, EA attach, or broker interaction.

## Requirements

- Python **3.11+**
- Standard library only (no pip dependencies)
- ASCII-safe signal text only (UTF-8 without BOM on write)

## Repository paths

| Artifact | Path |
|----------|------|
| Bridge CLI | `integrations/telegram/fasttrack_file_bridge.py` |
| Env template | `integrations/telegram/.env.example` |
| Tests | `integrations/telegram/tests/test_atomic_publish.py` |

## Modes

### 1. `--simulate-stdin`

Line-delimited JSON events on stdin:

```json
{"type":"seed","text":"Gold sell now","message_id":"seed-001"}
{"type":"details","text":"Gold sell now 4014 - 4017\nSL: 4077\nTP: 4007\nTP: 4005\nTP: 4003\nTP: 4002\nTP: open","message_id":"details-001"}
```

Example (temporary directory — **not** real FILE_COMMON):

```powershell
$root = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "ft_bridge_sim") -Force
@'
{"type":"seed","text":"Gold sell now","message_id":"seed-001"}
{"type":"details","text":"Gold sell now 4014 - 4017\nSL: 4077\nTP: 4007\nTP: 4005\nTP: 4003\nTP: 4002\nTP: open","message_id":"details-001"}
'@ | python integrations/telegram/fasttrack_file_bridge.py `
  --simulate-stdin `
  --file-common-root $root `
  --seed-filename basket_recovery_fasttrack_seed.txt `
  --details-filename basket_recovery_fasttrack_details.txt `
  --pair-timeout-seconds 900
```

### 2. `--publish-pair`

Direct pair publish for ops/tests:

```powershell
python integrations/telegram/fasttrack_file_bridge.py `
  --publish-pair `
  --file-common-root $root `
  --seed-text "Gold sell now" `
  --details-text "Gold sell now 4014 - 4017`nSL: 4077`nTP: 4007`nTP: open"
```

Or from files:

```powershell
python integrations/telegram/fasttrack_file_bridge.py `
  --publish-pair `
  --file-common-root $root `
  --seed-file .\fixtures\seed.txt `
  --details-file .\fixtures\details.txt
```

### 3. `--dry-run`

Logs `PUBLISH_READY` with `dry_run=true` and writes **no files**.

```powershell
python integrations/telegram/fasttrack_file_bridge.py `
  --publish-pair `
  --dry-run `
  --file-common-root $root `
  --seed-text "Gold sell now" `
  --details-text "Gold sell now 4014 - 4017`nSL: 4077`nTP: open"
```

Optional structured log file:

```powershell
  --log-file integrations/telegram/bridge.local.log
```

## Default filenames

- Seed: `basket_recovery_fasttrack_seed.txt`
- Details: `basket_recovery_fasttrack_details.txt`

These match Sprint 9A EA inputs. Only **basename** values are accepted.

## Atomic publish protocol

1. Move existing seed final to `.hold.<uuid>` (prevents old seed + new details reads).
2. Move existing details final to `.hold.<uuid>`.
3. Write details to `.part.<uuid>`, fsync, atomic replace to details final.
4. Write seed to `.part.<uuid>`, fsync, atomic replace to seed final.
5. Delete hold files on success.
6. On failure: remove staging, restore holds; no mismatched final pair.

`PUBLISH_READY` is emitted only when both finals succeed.

## Pair matcher (stdin mode)

- One open seed at a time.
- New seed without matching details → previous seed discarded (`stale_seed_replaced`).
- Details without seed → skipped (`details_without_seed`).
- Same normalized pair fingerprint → skipped (`dedup`).
- Unmatched seed past timeout → skipped (`pair_expired`).

Correlation key: `symbol|direction|date_utc|seed_message_id`

TODO (Phase 2): Telegram `grouped_id` / reply-chain pairing.

## Validation limits

- ASCII-only payloads (no silent transliteration).
- Max **8192 bytes** per file (matches EA `BRE_FAST_TRACK_AUDIT_FILE_MAX_BYTES`).
- Seed format: `<symbol> <buy|sell> now` (currently `gold` alias supported).
- Details: raw text preserved; line endings normalized to `\n`.

## Real FILE_COMMON — not used in Phase 1 tests

Production MT5 FILE_COMMON on Windows:

```text
%APPDATA%\MetaQuotes\Terminal\Common\Files\
```

Phase 1 unit tests use **temporary directories only**. Writing to the D0E terminal FILE_COMMON is an **operator step for Phase 1.5 / Phase 2 E2E**, not part of automated tests.

## Future E2E with observer-only EA (Phase 1.5+)

1. Publish pair to real FILE_COMMON with bridge `--publish-pair`.
2. Attach `BasketRecoveryEA` with:
   - FastTrack manual test enabled
   - File polling enabled
   - Direct seed/details inputs **empty**
   - Observer-only / demo isolation enabled
3. Expect Experts log:
   - `fast_track_audit_file_source=READ`
   - `fast_track_basket_stage=DETAILS_BOUND`
   - `fast_track_order_plan_result=BLOCKED`
   - `OBSERVER_ONLY_STARTUP_ISOLATION`

Re-attach EA for each new signal (EA reads file inbox once per attach in Sprint 9A).

## Broker security boundary

Even if bridge publishes valid signals, observer-only mode blocks broker submission. No OrderSendAsync, pending/basket/idempotency writes from this bridge.

## Telegram — Phase 2

Telethon user-session listener, credentials, and private-channel intake are **out of scope** for Phase 1. See Sprint 9B architecture plan for Phase 2 sequencing.

## Running tests

```powershell
python -m unittest integrations.telegram.tests.test_atomic_publish -v
```

Or from repo root:

```powershell
python integrations/telegram/tests/test_atomic_publish.py -v
```

## Credential hygiene

- Do not commit `.env`, `*.session`, or local log files.
- `.env.example` contains variable names only.
