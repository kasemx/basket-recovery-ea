# Sprint 6E — Simulated Broker Submission and Acknowledgement Path

**Baseline:** commit `2db5f5160eae0916679a877ec0eb1a8ed81cc30d`, tag `v0.6.3-submission-preparation-envelope`
**Scope:** Deterministic simulated broker submission lifecycle without MT5 broker mutation.

## Goal

Prove the complete broker-submission lifecycle through a test-only simulated gateway:

```text
CREATED
→ QUEUED
→ prepared envelope
→ simulated broker submit accepted
→ SUBMITTED
→ simulated acknowledgement (ORDER_ADD via router)
→ ACKNOWLEDGED
→ injected transaction (DEAL_ADD / ORDER_DELETE)
→ PARTIALLY_FILLED / FILLED / REJECTED / UNKNOWN
```

**No `OrderSend`, `OrderSendAsync`, `CTrade`, `PositionClose`, or `PositionModify`.**

## State machine

```text
                    ┌─────────────┐
                    │   CREATED   │
                    └──────┬──────┘
                           │ preparation
                           ▼
                    ┌─────────────┐
              ┌────│   QUEUED    │──── envelope expired / validation fail
              │    │ + prepared  │
              │    └──────┬──────┘
              │           │ CSubmitPreparedExecutionUseCase + gateway accept
              │           ▼
              │    ┌─────────────┐
              │    │  SUBMITTED  │◄── only TryBrokerSubmitTransition(..., true)
              │    └──────┬──────┘
              │           │ ORDER_ADD (ack)
              │           ▼
              │    ┌───────────────┐
              │    │ ACKNOWLEDGED  │
              │    └───────┬───────┘
              │            │ DEAL_ADD / ORDER_DELETE
              │            ▼
              │    PARTIALLY_FILLED ──► FILLED
              │            │
              │            └──► REJECTED
              │
              ├── gateway reject ──► REJECTED (never SUBMITTED)
              ├── gateway unknown ──► UNKNOWN (blocks resubmit)
              └── deadline ──► TIMED_OUT ──► RECONCILING ──► FILLED/REJECTED/RECONCILED
```

| Transition | Actor |
|------------|-------|
| QUEUED → SUBMITTED | `CSubmitPreparedExecutionUseCase` via `TryBrokerSubmitTransition(..., true)` only |
| SUBMITTED → ACKNOWLEDGED | `CTradeTransactionRouter` on `ORDER_ADD` |
| ACKNOWLEDGED → PARTIALLY_FILLED / FILLED | Router on `DEAL_ADD` with volume accumulation |
| ACKNOWLEDGED / PARTIAL → REJECTED | Router on `ORDER_DELETE` |
| SUBMITTED+ → TIMED_OUT → RECONCILING | `CExecutionTimeoutMonitor` (no retry) |
| RECONCILING → terminal | Router reconciliation path only |

## Simulated gateway contract (`ISubmissionGateway`)

```cpp
virtual CSubmissionGatewayResult Submit(const CBrokerSubmissionEnvelope &envelope)=0;
virtual bool IsSimulated(void) const=0;
```

`CSimulatedSubmissionGateway` implements deterministic scenarios:

| Scenario | Gateway outcome | Follow-up (test injector) |
|----------|-----------------|---------------------------|
| ACCEPT_ACK | Accepted + placeholder request ID | Inject ORDER_ADD |
| ACCEPT_FILL | Accepted | ORDER_ADD + full DEAL_ADD |
| ACCEPT_PARTIAL_FILL_FILL | Accepted | ORDER_ADD + partial + fill deals |
| ACCEPT_PARTIAL_FILL_REJECT | Accepted | ORDER_ADD + partial + ORDER_DELETE |
| REJECT_BEFORE_ACK | Rejected | Entry stays REJECTED, never SUBMITTED |
| ACCEPT_TIMEOUT | Accepted | Timeout monitor → RECONCILING |
| ACCEPT_UNKNOWN | Unknown | Entry → UNKNOWN, blocks resubmit |
| DUPLICATE_ATTEMPT | Replay prior result | No second gateway mutation |
| STALE / EXPIRED ENVELOPE | Validator blocks before gateway | — |

Gateway **never** calls MT5 APIs. `IsSimulated()` returns `true`.

## Acknowledgement vs transaction

| Event | Mechanism | Status effect |
|-------|-----------|---------------|
| **Acknowledgement** | Simulated broker accepts order; test injects `ORDER_ADD` through router | SUBMITTED → ACKNOWLEDGED |
| **Transaction (fill)** | Test injects `DEAL_ADD` with correlated comment/token | ACKNOWLEDGED/PARTIAL → PARTIALLY_FILLED / FILLED |
| **Transaction (reject)** | Test injects `ORDER_DELETE` | → REJECTED |

Acknowledgement assigns broker order placeholder IDs on the entry correlation. Transactions use existing correlation priority (order → deal → ticket → magic+symbol+comment → fingerprint). Tests must not bypass the router.

## Controlled submission use case

`CSubmitPreparedExecutionUseCase` flow:

```text
pending QUEUED entry
→ CPreparedSubmissionValidator (prepared metadata, envelope match, not expired)
→ block resubmit if SUBMITTED / UNKNOWN / TIMED_OUT / RECONCILING / terminal
→ replay cached outcome on duplicate idempotency key (no gateway re-call)
→ ISubmissionGateway.Submit(envelope)
→ on accept: TryBrokerSubmitTransition(..., true), persist, placeholder ID
→ on reject: REJECTED without SUBMITTED
→ on unknown: UNKNOWN without SUBMITTED
```

**Only this use case invokes `TryBrokerSubmitTransition`.** A prepared envelope alone does not transition status.

## Retry prohibition

- No automatic retry policy.
- Duplicate idempotency key returns original outcome (`IsDuplicateReplay=true`, `GatewayInvoked=false`).
- `UNKNOWN`, `TIMED_OUT`, `RECONCILING`, terminal, and already-submitted states block resubmission.
- Timeout hands off to reconciliation; does not re-submit to gateway.

## Restart policy

- `IPendingExecutionStore` restores QUEUED prepared entries; **no auto-submit**.
- SUBMITTED entries restore with correlation metadata and placeholder IDs.
- Duplicate transactions after restart are idempotently ignored via processed transaction keys.
- Timeout monitor continues from restored `deadlineUtc`.
- UNKNOWN remains blocked for blind resend.

## Runtime isolation

| Route | Submission wired? |
|-------|-------------------|
| Strategy / REST / OnTick / OnTimer | **No** |
| Production manual dry-run (`ITradeExecutor`) | **No** |
| Bootstrap production composition | **No** — `CSubmissionGatewayCompositionGuard` blocks simulated gateway auto-wire |
| Tests (`TestSimulatedSubmission.mq5`) | **Yes** — explicit harness only |

`CApplicationContext::IsSubmissionGatewayWiredToProduction()` returns `false`.

## Diagnostics (`CSubmissionDiagnostics`)

Default **off**. Bounded lines may cover: submit attempted, envelope validation, simulated accept/reject, placeholder IDs, ack correlation, transitions, duplicate blocks, timeout/reconciliation handoff. No raw account or sensitive payload logging.

## Prerequisites before real OrderSendAsync

1. Implement non-simulated `ISubmissionGateway` adapter calling MT5 async API.
2. Gate bootstrap registration with explicit execution-mode flag (`CSubmissionGatewayCompositionGuard::AllowsProductionAutoWire`).
3. Keep `CSubmitPreparedExecutionUseCase` as the sole `TryBrokerSubmitTransition` caller.
4. Require prepared envelope + validator pass before any live submit.
5. Preserve stamped comment correlation and idempotency store replay semantics.
6. Chart validation with live async submit + transaction correlation.

## Key files

| Area | Files |
|------|-------|
| Domain | `SubmissionGatewayStatus.mqh`, `SubmissionGatewayResult.mqh`, `BrokerSubmissionAcknowledgement.mqh`, `SimulatedBrokerSubmissionScenario.mqh`, `PreparedSubmissionResult.mqh`, `PreparedSubmissionFailureReason.mqh` |
| Application | `Ports/ISubmissionGateway.mqh`, `SubmitPreparedExecutionUseCase.mqh`, `PreparedSubmissionValidator.mqh`, `SubmissionResultMapper.mqh`, `SimulatedBrokerSubmissionInjector.mqh`, `SubmissionGatewayCompositionGuard.mqh`, `SubmissionDiagnostics.mqh` |
| Infrastructure | `SimulatedSubmissionGateway.mqh` |
| Tests | `TestSimulatedSubmission.mq5` |
