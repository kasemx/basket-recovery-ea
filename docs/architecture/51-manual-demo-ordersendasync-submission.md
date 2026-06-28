# Sprint 6G — Manual One-Shot Demo OrderSendAsync Submission

**Baseline:** commit `4648065a7aab896955c26919b1a74f3d161ee599`, tag `v0.6.5-live-submission-safety-and-demo-authorization`
**Scope:** First real MT5 broker submission for manually authorized, one-shot, demo-only `OPEN_POSITION` market orders.

## Warning

This sprint enables **manual demo submission only**. It is **not** automatic strategy execution. Strategy, REST, OnTick, OnTradeTransaction, and normal timer paths do **not** submit orders.

## Goal

```text
manual input trigger
→ resolve prepared QUEUED request
→ validate authorization token + trigger token
→ revalidate all safety gates
→ CDemoManualSubmissionService
→ CMt5AsyncSubmissionGateway (OrderSendAsync once)
→ SUBMITTED (never FILLED from async return)
→ await OnTradeTransaction for terminal outcome
```

## Runtime mode

| Mode | Value | Behavior |
|------|-------|----------|
| `LIVE_DISABLED` | 0 | **Default** — no submission |
| `DEMO_MANUAL_SUBMISSION` | 4 | Manual one-shot demo submit route |

Requires all Sprint 6F gates plus explicit inputs:

| Input | Required |
|-------|----------|
| `InpExecutionMode` | `DEMO_MANUAL_SUBMISSION` (4) |
| `InpEnableLiveDemoExecution` | `true` |
| `InpRequireManualDemoAuthorization` | `true` |
| `InpManualDemoAuthorizationToken` | Valid one-shot token |
| `InpManualDemoSubmissionRequestId` | Prepared request id |
| `InpManualDemoSubmissionTriggerToken` | New unique one-shot value |
| `InpManualDemoAuthorizationBasketId` | Basket id |
| `InpMaxManualDemoOpenVolume` | Volume cap (default 0.01) |

## State diagram

```text
QUEUED + prepared envelope
→ AUTHORIZED_FOR_FUTURE_SUBMISSION (record, token not consumed yet)
→ revalidate safety gates (service + gateway)
→ OrderSendAsync
   ├─ false → REJECTED (stay not SUBMITTED)
   └─ true  → SUBMITTED only
              → OnTradeTransaction
              → ACKNOWLEDGED / PARTIALLY_FILLED / FILLED / REJECTED / UNKNOWN
```

**Never** interpret `OrderSendAsync == true` as fill confirmation.

## OrderSendAsync isolation

`OrderSendAsync` exists **only** in:

```text
mt5/Include/BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionGateway.mqh
```

Tests use `CMockMt5AsyncOrderSendTransport` — no real broker call.

Still forbidden everywhere:

- `OrderSend`
- `CTrade`
- `PositionClose`
- `PositionModify`

## Hard limits (this sprint)

| Limit | Enforcement |
|-------|-------------|
| Demo account only | `CLiveSubmissionSafetyGate` + eligibility provider |
| `OPEN_POSITION` only | Service + gateway intent check |
| Market `DEAL` only | `CMt5EnvelopeTradeRequestTranslator` |
| One open per session | `HasSubmissionSessionCapacity` |
| One symbol per session | `LockSessionSymbol` |
| Max demo volume | `InpMaxManualDemoOpenVolume` |
| One auth token per submission attempt | Consumed when `OrderSendAsync` invoked |
| One trigger token per attempt | Consumed after route completes |
| No retry without new tokens | No automatic re-attempt on timer |
| No restart auto-submit | Pending restore only |
| No strategy/REST/OnTick/timer submit | Isolation flags + manual route only |

## Immediate vs final result

| Phase | Source | Meaning |
|-------|--------|---------|
| Immediate | `OrderSendAsync` return + retcode | Transport acceptance → `SUBMITTED` |
| Final | `OnTradeTransaction` via router | ACK / fill / reject / unknown |

## Rollback / no-retry policy

- `OrderSendAsync == false`: no `SUBMITTED` transition; entry → `REJECTED`; diagnostics preserved
- No automatic retry on false, unknown, or timeout
- New submission requires new authorization token **and** new trigger token
- Kill switch disable never mutates open positions

## Demo validation checklist

Before live demo submit on chart:

1. Demo account connected (`ACCOUNT_TRADE_MODE_DEMO`)
2. Terminal Algo Trading enabled
3. EA chart trading permission enabled
4. `InpExecutionMode = 4`
5. `InpEnableLiveDemoExecution = true`
6. Prepared `QUEUED` request exists (via preparation path)
7. Fresh quote, spread within threshold, envelope not expired
8. New authorization token bound to exact request metadata
9. New trigger token never used before
10. Volume ≤ `InpMaxManualDemoOpenVolume`
11. Session cap not exceeded

## Key files

| Area | Files |
|------|-------|
| Domain | `DemoManualSubmissionResult.mqh`, `ExecutionRuntimeMode.mqh` |
| Application | `DemoManualSubmissionService.mqh`, `DemoManualSubmissionValidationService.mqh`, `DemoManualSubmissionTriggerRegistry.mqh` |
| Infrastructure | `Mt5/Mt5AsyncSubmissionGateway.mqh`, `Mt5AsyncSubmissionResult.mqh`, `Mt5AsyncSubmissionDiagnostics.mqh`, `Mt5EnvelopeTradeRequestTranslator.mqh`, `IMt5AsyncOrderSendTransport.mqh`, `MockMt5AsyncOrderSendTransport.mqh` |
| Tests | `TestManualDemoOrderSendAsyncSubmission.mq5` |
