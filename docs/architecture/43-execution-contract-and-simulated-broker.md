# Sprint 6A — Execution Contract and Simulated Broker Executor

**Baseline:** `566e332` / `v0.5.2-runtime-observability`

**This sprint has no broker execution.** No `OrderSend`, `OrderSendAsync`, `OrderCheck`, `PositionClose`, `PositionModify`, or `CTrade` calls are introduced. OnTick and OnTradeTransaction do not execute trades.

## Execution boundary

```text
Persistent strategy command
        │
        ▼
CExecuteTradeIntentUseCase
  ├─ load basket + version/hash guard
  ├─ CExecutionRequestFactory → CTradeExecutionRequest (immutable, sealed)
  ├─ CExecutionRequestValidator
  ├─ IExecutionRequestRepository / IExecutionJournal (CREATED → QUEUED)
  ├─ ITradeExecutor.Execute(request)   ← CSimulatedTradeExecutor (Sprint 6A)
  ├─ CExecutionResultMapper → CExecutionDomainEvent
  └─ aggregate-safe generic event (ExecutionRequested / Accepted / Filled / …)
```

Legacy Sprint 5 per-operation adapters are isolated under `Infrastructure/Execution/Legacy/` (`ITradeRequestExecutor`, `CLegacyMt5TradeRequestExecutor`) and are not composition-root eligible. See `docs/architecture/44-execution-port-compatibility-audit.md`.

## Request / result schema

### `CTradeExecutionRequest` (immutable after factory seal)

| Field | Required |
|-------|----------|
| executionRequestId | yes |
| idempotencyKey | yes |
| correlationId | yes |
| basketId | yes |
| expectedBasketVersion | yes |
| strategyProfileHash | yes |
| symbol | yes |
| intentType | yes |
| direction | open intents |
| ticket | close/modify/cancel intents |
| requestedVolume | volume intents |
| requestedPrice / stopLoss / takeProfit | when applicable |
| requestedAtUtc | yes |
| sourceCommandId | yes |
| reason | optional label |

### Intent types

`OPEN_POSITION`, `CLOSE_POSITION`, `MODIFY_STOP_LOSS`, `MODIFY_TAKE_PROFIT`, `REDUCE_POSITION`, `CANCEL_PENDING_REQUEST`

### Result / receipt

- `CTradeExecutionResult` — status, failure reason, requested/filled volume, broker placeholders
- `CTradeExecutionReceipt` — request + current status + transitions + retry count

## State machine

```text
CREATED → QUEUED → SUBMITTED → ACCEPTED → PARTIALLY_FILLED → FILLED
                              ↘ REJECTED / FAILED / TIMED_OUT / CANCELLED / UNKNOWN
```

Rules (`CExecutionLifecycleRules`):

- Terminal states are immutable (`FILLED`, `REJECTED`, `FAILED`, `TIMED_OUT`, `CANCELLED`, `UNKNOWN`)
- Terminal requests cannot be submitted again
- `UNKNOWN` blocks blind resend — requires reconciliation
- Partial fills preserve requested vs filled volume on the receipt result

## Idempotency policy

1. `ExecuteTradeIntentUseCase` checks `IExecutionRequestRepository.FindByIdempotencyKey` **before** building a new execution path.
2. Duplicate key returns the **original receipt** mapped to a domain event (`IsDuplicateReplay=true` on receipt).
3. Retries must preserve the same `executionRequestId` and `idempotencyKey` (caller responsibility; repository enforces uniqueness by idempotency key).
4. Validation failures and guard failures produce deterministic **rejection receipts**, not exceptions.

## Timeout and unknown-result policy

- Simulated timeout scenario → status `TIMED_OUT`, event `ExecutionTimedOut`
- Simulated unknown scenario → status `UNKNOWN`, event `ExecutionUnknown`
- `CExecutionLifecycleRules::BlocksBlindResend(UNKNOWN)` prevents automatic resubmit; reconciliation required before any future real executor retry policy

## Partial-fill policy

- Simulator emits `PARTIALLY_FILLED` with `filledVolume = requestedVolume * 0.5`
- Final transition to `FILLED` or `REJECTED` preserves cumulative filled volume on the result object
- Domain event uses `ExecutionPartiallyFilled` while status is partial, `ExecutionFilled` when complete

## Simulated scenarios

| Scenario | Idempotency prefix / policy | Outcome |
|----------|---------------------------|---------|
| Accept → fill | default / `sim:accept-fill:` | ACCEPTED → FILLED |
| Rejected | `sim:reject:` | REJECTED |
| Timeout | `sim:timeout:` | TIMED_OUT |
| Partial → fill | `sim:partial-fill:` | PARTIAL → FILLED |
| Partial → reject | `sim:partial-reject:` | PARTIAL → REJECTED |
| Unknown | `sim:unknown:` | UNKNOWN |
| Duplicate idempotency | same key twice | original receipt, executor not called again |
| Stale version | use case guard | REJECTED (`stale_basket_version`) |
| Hash mismatch | use case guard | REJECTED (`profile_hash_mismatch`) |

## Real MT5 executor prerequisites (designed, not activated)

`CExecutionSafetyPreconditions::IsLiveExecutionEnabled()` returns **false**. When enabled in a future sprint, checks include:

- live quote freshness
- max spread
- market/session availability
- account trade permission
- basket lifecycle ACTIVE
- recovery disabled / basket locked
- expected basket version + strategy profile hash
- ticket belongs to basket
- volume symbol constraints
- duplicate idempotency key

All checks return deterministic rejection receipts via `CTradeExecutionResult::Rejected(...)`.

## Tests

`TestExecutionContract.mq5` covers request validation, lifecycle rules, idempotency, guards, all simulator scenarios, journal transitions, event mapping, terminal resubmit blocking, and in-process-only simulation (no MT5 trade APIs).

## Key files

| Area | Path |
|------|------|
| Domain types | `Domain/Execution/*`, `Domain/Events/ExecutionDomainEvent.mqh` |
| Port | `Application/Execution/Ports/ITradeExecutor.mqh` |
| Active adapter | `Infrastructure/Execution/SimulatedTradeExecutor.mqh` |
| MT5 placeholder | `Infrastructure/Execution/Mt5TradeExecutor.mqh` (inactive until Sprint 6B) |
| Legacy (tests only) | `Infrastructure/Execution/Legacy/` |
