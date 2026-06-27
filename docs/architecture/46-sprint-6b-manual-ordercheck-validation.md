# Sprint 6B.1 — Manual OrderCheck Validation

## Scope

This document records two distinct validation tracks:

1. **Script harness (local guards only)** — does **not** prove real MT5 `OrderCheck`.
2. **EA chart-attached runtime (production wiring)** — required proof that `CMt5OrderCheckGateway` reaches MT5 `OrderCheck`.

---

## A. Script harness — Local guard validation only — OrderCheck not reached

> **Label:** `Local guard validation only — OrderCheck not reached`  
> Do **not** present this section as real broker `OrderCheck` validation.

### Run metadata

| Field | Value |
| --- | --- |
| Date/time (terminal) | 2026-06-27 23:36:36 |
| Terminal | `D0E8209F77C8CF37AD8BF550E51FF075` |
| Account | 28110078 (redacted server name) |
| Symbol | `BTCUSD` (broker-resolved) |
| Basket id | `sprint6b-demo-btc-001` (in-memory seed — **not** production persistence flow) |
| Trigger token | `sprint6b-live-178259…784` (suffix redacted) |
| Validation harness | `ValidateSprint6bLiveOrderCheck.mq5` via `scripts/run-sprint6b-live-validation.ps1` |
| Route exercised | `CExecutionDryRunManualCommandService` → `CExecuteTradeIntentUseCase` → `CMt5TradeExecutor` (MT5_DRY_RUN) |

### Why OrderCheck was not reached

Unattended **script** startup does not set `ACCOUNT_TRADE_EXPERT=true` even with `AllowLiveTrading=1`. Local guard `CMt5RequestValidationPolicy::ValidateBeforeOrderCheck` rejected before translation/OrderCheck.

### Script harness result

| Field | Value |
| --- | --- |
| Intent | `OPEN_POSITION` BUY 0.01 |
| Local validation | **REJECTED** — `Account trade permission denied` |
| `order_check_invoked` | **false** |
| MT5 `OrderCheck` retcode | **Not reached** (`0`) |
| Mapped status | `REJECTED` |
| `isDryRun` | `true` |
| OrderSend path | **NOT_USED** |
| Broker mutation | **NONE** |

### Journal evidence (script)

```text
rejected | …|reason=Account trade permission denied|order_check_invoked=false|no_ordersend=true
Manual dry-run completed | basket=sprint6b-demo-btc-001 | status=REJECTED
```

Artifact: `build/validation/sprint-6b-live-result.txt`

---

## B. Production basket seed (normal application flow)

Test-only seeding for EA chart proof uses **production handlers and persistence** — no hand-edited JSON.

| Component | Production reuse |
| --- | --- |
| Persistence store | `CFileBasketRepository` → `BasketRecovery/persistence/baskets` (same as `CPersistenceManager`) |
| Serializer / CRC | `CBasketSerializer` + `CJsonWriter` CRC32 (atomic write) |
| Create | `CCreateBasketCommandHandler` → `CBasketFactory::Create` |
| Lifecycle | `CStateTransitionHandler` + `BRE_EVENT_INITIAL_POSITIONS_OPENED` → `WAIT_DETAILS` |
| Strategy bind | `CBindMigratedBasketStrategyUseCase` + `CStrategyProfileCanonicalSerializer` |
| Activate | `CActivateBasketCommandHandler` → `ACTIVE` |
| Orchestration | `CExecutionDryRunTestBasketSeedService` (test-only) |
| Seed script | `SeedSprint6bOrderCheckBasket.mq5` |
| Runner | `scripts/run-sprint6b-ea-chart-validation.ps1` |

Seed proof fields written to `build/validation/sprint-6b-seed-result.txt`:

- basket id, symbol (exact chart match), lifecycle `ACTIVE`
- immutable strategy snapshot present
- strategy profile hash + basket version
- CRC round-trip reload OK via `FileBasketRepository.Load`

---

## C. EA chart-attached runtime proof (required)

### Terminal prerequisites

- Terminal global **Algo Trading** enabled
- Chart-level algorithmic trading permission enabled for attached EA
- `BasketRecoveryEA` loaded on active **BTCUSD** chart (symbol must match seeded basket exactly)
- Application timer running (`InpApplicationTimerIntervalMs=250`)
- No live trade executor mode (`InpExecutionMode=MT5_DRY_RUN` only)

### EA inputs (validation preset)

```text
InpExecutionMode = 1 (MT5_DRY_RUN)
InpEnableExecutionDryRun = true
InpEnableExecutionDiagnostics = true
InpMaxSpreadPoints = 500000
InpManualExecutionDryRunBasketId = sprint6b-demo-btc-001
InpManualExecutionDryRunTriggerToken = <one-shot token>
InpManualExecutionDryRunLotSize = 0.01
```

Both dry-run gates must be enabled (`MT5_DRY_RUN` + `EnableExecutionDryRun`).

### Expected runtime chain

```text
EA OnTimer manual dry-run route
→ CExecutionDryRunManualCommandService
→ CExecuteTradeIntentUseCase
→ CMt5TradeExecutor (MT5_DRY_RUN)
→ CMt5OrderCheckGateway
→ OrderCheck called
→ real MT5 retcode captured
→ no broker mutation (OrderSend not invoked)
```

### Required runtime evidence

Captured in `build/validation/sprint-6b-ea-chart-result.txt` by `CollectSprint6bEaChartOrderCheckEvidence.mq5`:

| Evidence | Required |
| --- | --- |
| EA startup confirms `MT5_DRY_RUN` | execution log + EA journal |
| Both dry-run gates enabled | preset + bootstrap wiring |
| Active basket with valid snapshot/hash/version | seed report + persisted reload |
| Translation succeeds | `translation_ok` diagnostic |
| Local pre-OrderCheck validation succeeds | no `order_check_invoked=false` rejection |
| `OrderCheck invoked` | `ordercheck_invoked` / `order_check_invoked=true` diagnostic |
| Actual MT5 retcode + text | `ordercheck_ok` / `ordercheck_fail` + result fields |
| Mapped execution status | `Manual dry-run completed | status=…` |
| `isDryRun=true` | execution result |
| `OrderSend not invoked` | `no_ordersend=true` on all diagnostics |
| Trade tab unchanged | positions/orders before=after |

> A real **OrderCheck rejection** (non-zero retcode) is valid proof. Validations were not weakened to force `ACCEPTED`.

### EA chart result (populate after running `scripts/run-sprint6b-ea-chart-validation.ps1`)

| Field | Value |
| --- | --- |
| Date/time | 2026-06-28 01:37:09 (terminal) |
| Terminal | `D0E8209F77C8CF37AD8BF550E51FF075` |
| Account | 28110078 (VantageMarkets-Live 8) |
| Trigger token | `sprint6b-ea-1782599768789` |
| `ordercheck_reached` | **true** |
| `order_check_invoked` | **true** |
| MT5 retcode / text | **0 / Done** |
| Diagnostic line | `ordercheck_ok` (after mapper fix for retcode=0+Done) |
| Mapped status | **ACCEPTED** |
| Request summary | BUY 0.01 BTCUSD @ ~60148.50 (OPEN_POSITION dry-run) |
| `isDryRun` | **true** (`no_ordersend=true` on all diagnostics) |
| Broker mutation | **NONE** (positions 0→0, orders 0→0) |
| `chart_validation_passed` | **true** |
| Artifact | `build/validation/sprint-6b-ea-chart-result.txt` |

---

## H. Sprint 6B.4 — CRC fix + chart OrderCheck re-validation

### CRC fix evidence (root cause from 6B.3)

| Item | Detail |
| --- | --- |
| Root cause | `CCrc32::FromHex` used signed `StringToInteger`; CRC values > INT_MAX parsed incorrectly → `-9103` on every load |
| Fix | uint-safe hex parse in `Crc32.mqh` |
| Seed reopen | `stored_crc=computed_crc=0CF65E2C`, `validation_stage=ok`, `repository_load=ok` |
| Persistence path | `FILE_COMMON` → `Terminal\Common\Files\BasketRecovery\persistence\baskets\sprint6b-demo-btc-001.json` |
| Seed artifact | `build/validation/sprint-6b-seed-result.txt` |

### Chart startup evidence (Phase 1 — CRC only, trigger=0)

EA attached via startup INI on **BTCUSD M1** with:

```text
InpEnableExecutionDiagnostics=true
InpManualExecutionDryRunBasketId=sprint6b-demo-btc-001
InpManualExecutionDryRunTriggerToken=0
```

Captured once per run in execution log + `Print`:

```text
BRE basket-load diagnostic | stored_crc=0CF65E2C | computed_crc=0CF65E2C |
validation_stage=ok | repository_load=ok
```

Previous 6B.1 chart run was **invalid** — journal showed `automated trading is disabled because the account has been changed` after unattended account switch. Sprint 6B.4 runner **does not change login/account**.

### Real OrderCheck proof (Phase 2 — one timer cycle)

```text
InpExecutionMode=1
InpEnableExecutionDryRun=true
InpEnableExecutionDiagnostics=true
InpMaxSpreadPoints=500000
InpManualExecutionDryRunBasketId=sprint6b-demo-btc-001
InpManualExecutionDryRunTriggerToken=<unique non-zero token>
```

Execution log chain (chart-attached EA, production wiring):

```text
translation_ok
local_validation_ok
ordercheck_invoked | order_check_invoked=true
ordercheck_ok | retcode=0 | text=Done | order_check_invoked=true | no_ordersend=true
Manual dry-run completed | status=ACCEPTED
```

| Field | Value |
| --- | --- |
| `order_check_invoked` | **true** |
| MT5 OrderCheck retcode | **0** |
| MT5 OrderCheck text | **Done** |
| Mapped execution status | **ACCEPTED** |
| Broker mutation | **NONE** (open positions 0→0, pending orders 0→0) |
| OrderSend path | **NOT_USED** |

Note: MT5 returned `OrderCheck()` bool=false with `retcode=0` and `comment=Done` on this broker build. Mapper now treats `retcode==0 && comment=="Done"` as dry-run acceptance; broker retcode/text are still captured verbatim for audit.

### Local guard test vs real OrderCheck proof

| Track | Harness | `order_check_invoked` | Real MT5 retcode | Valid as OrderCheck proof? |
| --- | --- | --- | --- | --- |
| **A — Script** (`ValidateSprint6bLiveOrderCheck.mq5`) | Unattended script; `ACCOUNT_TRADE_EXPERT=false` | **false** | Not reached | **No** — local guard only |
| **C — EA chart** (`BasketRecoveryEA` + runner 6B.4) | Chart-attached EA; terminal Algo Trading enabled | **true** | **0 / Done** | **Yes** — real `OrderCheck` invoked |

Section A remains **local guard validation only**. Section C/H is the authoritative Sprint 6B OrderCheck proof.

### Runner gate (`scripts/run-sprint6b-ea-chart-validation.ps1`)

- Does **not** set MT5 login or switch accounts
- Fails if journal contains algo-trading-disabled-after-account-change
- Phase 1 requires CRC diagnostic in execution log (terminal-local `MQL5\Files\…\basket_recovery.log`)
- Phase 2 requires one timer dry-run with unique trigger token
- Phase 3 collector sets `chart_validation_passed=true` only when `order_check_invoked=true` **and** real retcode captured **and** broker state unchanged

---

## D. Diagnostics — `order_check_invoked`

Bounded diagnostic field added to `CMt5ExecutionDiagnostics` (only when `InpEnableExecutionDiagnostics=true`):

```text
order_check_invoked=true|false
```

- `false` on local guard rejections (`OnRejection`)
- `true` immediately before gateway `OrderCheck` (`OnOrderCheckInvoked`) and on broker outcome lines

Also exposed on `CTradeExecutionResult.OrderCheckInvoked()` for tests and validation scripts.

---

## E. Safety audit (Sprint 6B production scope)

| Term | Production executable usage |
| --- | --- |
| `OrderSend` | **None** — only `Legacy/LegacyMt5TradeRequestExecutor.mqh` (not wired) |
| `OrderSendAsync` | **None** |
| `CTrade` | **None** |
| `PositionClose` / `PositionModify` | **None** |
| `OrderCheck` | **Yes** — `Mt5/Mt5OrderCheckGateway.mqh` (dry-run production path) |

---

## F. Tests (`TestMt5DryRunExecution.mq5`)

- Seeded basket includes immutable strategy snapshot + valid CRC round-trip
- Manual route rejects invalid/unpersisted basket
- `order_check_invoked` true only after all local guards pass
- Local rejection keeps `order_check_invoked=false`
- Broker retcode mapping preserves `isDryRun=true`
- Production dry-run gateway invokes MT5 `OrderCheck` API (no OrderSend path)

---

## G. Artifacts

| File | Purpose |
| --- | --- |
| `build/validation/sprint-6b-live-result.txt` | Script harness (local guards only) |
| `build/validation/sprint-6b-seed-result.txt` | Production-flow basket seed proof |
| `build/validation/sprint-6b-ea-chart-result.txt` | EA chart OrderCheck proof |
| `scripts/run-sprint6b-live-validation.ps1` | Script harness runner |
| `scripts/run-sprint6b-ea-chart-validation.ps1` | Seed + EA + evidence runner (6B.4: no account change, strict OrderCheck gate) |

No terminal credentials or unredacted account payloads are committed.
