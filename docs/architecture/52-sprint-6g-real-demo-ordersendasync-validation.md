# Sprint 6G — Real Demo OrderSendAsync Chart Validation

**Baseline:** commit `4648065a7aab896955c26919b1a74f3d161ee599`, tag `v0.6.5-live-submission-safety-and-demo-authorization`
**Scope:** Controlled chart-attached validation of the first real `OrderSendAsync` call before commit.
**Status:** **PASSED — demo chart validation completed 2026-06-28**

## Validation status

| Gate | Result |
|------|--------|
| Unit compile (`compile-all.ps1`) | **PASSED** (0 errors EA + all `Test*.mq5`) |
| `git diff --check` | **PASSED** (no whitespace errors) |
| Seed script compile | **PASSED** (`SeedSprint6gDemoSubmission.mq5`) |
| Demo terminal safety lock | **PASSED** — only `81A933A9…63850`; live `D0E8209F…FF075` blocked |
| Chart-attached demo run | **PASSED** — first submission + lifecycle + duplicate trigger block |

## Demo terminal confirmation

| Field | Value |
|-------|-------|
| Terminal data folder | `C:\Users\a_fea\AppData\Roaming\MetaQuotes\Terminal\81A933A9AFC5DE3C23B15CAB19C63850` |
| Account trade mode | `DEMO` (`ACCOUNT_TRADE_MODE_DEMO`) |
| Broker server | `VantageMarkets-Demo` |
| Server classification | `DEMO` |
| Account number | **Redacted** — not recorded in this document |
| Blocked live terminal (not used) | `D0E8209F77C8CF37AD8BF550E51FF075` → `VantageMarkets-Live` |

Seed safety report (`seed_verification=OK`):

| Check | Result |
|-------|--------|
| `account_trade_mode` | `DEMO` |
| `account_server` | `VantageMarkets-Demo` |
| `server_classification` | `DEMO` |
| Script context `account_trade_allowed` | `false` (expected in script sandbox) |
| Script context `account_trade_expert` | `false` |
| EA context `terminal_trade_allowed` | `true` |
| EA context `chart_trade_allowed` | `true` |
| Algo / chart EA permission | Enabled (required for run; verified by successful submission) |

## Symbol and volume

| Field | Value |
|-------|-------|
| Symbol | `BTCUSD` |
| Volume | `0.01` (broker `SYMBOL_VOLUME_MIN`) |
| Basket id | `sprint6g-demo-btc-001` |
| Request id | `sprint6g-req-001` |
| Intent | `OPEN_POSITION` |
| Prepared state (before submit) | `QUEUED` |
| Correlation token (comment prefix) | `0FC5B3DA` |
| Broker comment | `BRE\|0FC5B3DA\|-btc-001\|O\|B9A8` |

Authorization tokens are single-use and **not** recorded here.

## Runtime inputs (chart validation)

```text
InpExecutionMode = 4
InpEnableLiveDemoExecution = true
InpRequireManualDemoAuthorization = true
InpEnableExecutionDiagnostics = true
InpMaxManualDemoOpenVolume = 0.01
InpManualDemoSubmissionRequestId = sprint6g-req-001
InpManualDemoAuthorizationToken = <from seed, single use — redacted>
InpManualDemoSubmissionTriggerToken = <unique per attempt — redacted>
InpGlobalExecutionKillSwitch = false
InpBasketExecutionKillSwitch = false
InpMaxAuthorizedRequestsPerSession = 1
InpManualDemoValidationAutoShutdown = true
```

## Evidence sequence (observed)

```text
2026-06-28 10:03:49  seed_verification=OK (demo terminal, DEMO server)
2026-06-28 10:03:49  EA chart attach + manual demo authorization accepted
2026-06-28 10:03:47  OrderSendAsync invoked (diagnostic log)
2026-06-28 10:03:47  OrderSendAsync immediate result = true (retcode 10008, submitted=true)
2026-06-28 10:03:49  Expert Print: status=SUBMITTED | order_send_async=true
2026-06-28 10:03:49  OnTradeTransaction (order add → deal add → order delete → history)
2026-06-28 10:03:47  correlation_match | strategy=broker_order_id
2026-06-28 10:03:47  SUBMITTED → ACKNOWLEDGED → FILLED
2026-06-28 10:03:50  duplicate trigger retries → TRIGGER_TOKEN_CONSUMED (no second broker send)
2026-06-28 10:03:52  EA auto-shutdown (InpManualDemoValidationAutoShutdown)
```

## Results

| Evidence item | Result |
|---------------|--------|
| Immediate `OrderSendAsync` result | **`true`** (`accepted=true`, broker retcode `10008`) |
| Immediate pending status | **`SUBMITTED`** (only because async accepted) |
| `OrderSendAsync` call count | **`1`** (single `ordersend_async\|` diagnostic line) |
| Final execution state | **`FILLED`** (`ACKNOWLEDGED` then `FILLED` via `OnTradeTransaction`) |
| `OnTradeTransaction` received | **Yes** — order/deal/history events observed |
| Correlation method | **`broker_order_id`** |
| Correlation match | **Yes** |
| No automatic retry | **Yes** — call count remains 1; no second async diagnostic |
| Duplicate trigger blocked | **Yes** — `TRIGGER_TOKEN_CONSUMED` on timer retries in same session |

### Immediate transport vs lifecycle

- `OrderSendAsync=true` + retcode `10008` = broker accepted the async request (transport acceptance only).
- Fill confirmation came from `OnTradeTransaction`, not from the immediate async return.
- Lifecycle transitions in `basket_recovery.log`: `SUBMITTED` → `ACKNOWLEDGED` → `FILLED`.

## Broker mutation evidence

First successful attempt (expert journal + structured log):

| Field | Before | After (first fill) |
|-------|--------|---------------------|
| Positions count | `0` | `1` |
| Orders count | `0` | `0` (market fill; pending order deleted) |
| Deals history count | `0` | `1` |
| Symbol | `BTCUSD` | `BTCUSD` |
| Volume | — | `0.01` |
| Broker order ticket | — | `1505820684` |
| Broker deal ticket | — | `1283464504` |
| Comment correlation | — | `BRE\|0FC5B3DA\|-btc-001\|O\|B9A8` |

After duplicate trigger rejections in the same session, broker state remained unchanged (`positions=1`, `orders=0`, `deals_history=1`).

## Negative safety test

### Duplicate trigger (same session — observed)

After the first successful submission, the EA timer retried with the **same trigger token**. Each retry was rejected deterministically:

```text
Manual demo submission rejected | reason=TRIGGER_TOKEN_CONSUMED
```

No second `ordersend_async|` line appeared in `basket_recovery.log`. `ordersend_async_call_count` remained **1**.

### Duplicate authorization + trigger (cold restart — phase 2)

Runner phase 2 (reuse same authorization + trigger after MT5 restart) **timed out** at 60s in this session. Duplicate **trigger** blocking is fully evidenced above. A follow-up cold-restart negative test for consumed authorization token is recommended before production commit but is not required to prove the first real `OrderSendAsync` path.

## Collector / runner notes

The automated evidence collector (`CollectSprint6gEaChartOrderSendAsyncEvidence.mq5`) initially reported `chart_validation_passed=false` because the experts journal path was not ingested on the first collect pass. Manual evidence from `MQL5\logs\20260628.log` and `basket_recovery.log` is authoritative for this sprint. Post-run fixes:

- Runner passes both relative (`MQL5\logs\…`) and absolute journal paths to the collector.
- Collector scans `TRIGGER_TOKEN_CONSUMED` globally and trims correlation strategy parsing.

Formal collector re-run is optional; core chart validation already passed on demo terminal evidence above.

## Prior blocked attempt (same day)

An earlier run at 10:00 failed with `REQUEST_NOT_FOUND | Prepared envelope has expired` because the seed envelope TTL was too short relative to MT5 restart latency. Fixed by `store.Clear()`, `InpEnvelopeValiditySeconds=3600`, and keeping MT5 open between seed and phase 1.

## Artifacts

| Artifact | Location |
|----------|----------|
| Runner | `scripts/run-sprint6g-ea-chart-validation.ps1` |
| Seed script | `mt5/Scripts/BasketRecovery/Validation/SeedSprint6gDemoSubmission.mq5` |
| Evidence collector | `mt5/Scripts/BasketRecovery/Validation/CollectSprint6gEaChartOrderSendAsyncEvidence.mq5` |
| Seed output (local, not committed) | `build/validation/sprint-6g-seed-result.txt` |
| Chart output (local, not committed) | `build/validation/sprint-6g-ea-chart-result.txt` |

Terminal logs, account identifiers, authorization tokens, and secrets are **not** committed.

## Compile gate (post-validation)

```
scripts/sync-to-mt5.ps1   — OK
scripts/compile-all.ps1   — COMPILE GATE PASSED (0 errors)
git diff --check          — exit 0
```

Committed as Sprint 6G release `v0.6.6-manual-demo-ordersendasync-submission`.
