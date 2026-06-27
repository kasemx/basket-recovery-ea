# Sprint 6D — Submission Preparation and Correlation Envelope

**Baseline:** commit `b938ab2cfa6ed2dc841a92fb5e28e589258908de`, tag `v0.6.2-pending-execution-correlation`
**Scope:** Prepare validated broker submission envelopes without live order submission.

## Goal

Build a deterministic, validated submission envelope and broker comment stamp so a future `OrderSendAsync` adapter can submit with safe correlation. **No `OrderSend`, `OrderSendAsync`, `OrderCheck`, or broker mutation in this sprint.**

## Envelope schema (`CBrokerSubmissionEnvelope`)

| Field | Description |
|-------|-------------|
| executionRequestId | Immutable request identity |
| idempotencyKey | Idempotent replay key |
| basketId / expectedBasketVersion / strategyProfileHash | Basket guard context |
| symbol / intentType / direction / ticket | Trade intent |
| requestedVolume / requestedPrice / SL / TP | Requested economics |
| magicNumber | Broker magic for correlation |
| brokerComment | Stamped MT5 comment |
| correlationToken | Short token extracted from comment |
| fingerprint | `CExecutionRequestFingerprint` hash |
| quoteTimestampUtc | Quote used for validation |
| preparedAtUtc | Preparation timestamp |
| expirationUtc | Envelope validity deadline |

## Broker comment format

```text
BRE|<short-correlation>|<basket-short>|<intent-code>|<checksum>
```

| Segment | Rule |
|---------|------|
| short-correlation | First 8 hex chars of CRC32(idempotencyKey or executionRequestId) |
| basket-short | Basket id truncated to 8 chars (suffix preserved) |
| intent-code | `O` open, `C` close, `S` SL, `T` TP, `R` reduce, `X` cancel |
| checksum | First 4 hex chars of CRC32(correlation\|basket\|intent) |

**Max length:** configurable (default **31** MT5 comment limit). Truncation shortens basket/correlation segments; checksum is recomputed after truncation.

**Security:** no credentials, account ids, or strategy JSON in comments.

## Checksum / collision policy

- Invalid checksum → transaction **not** correlated (`OnTradeTransaction` returns unrelated).
- Active pending entries scanned for duplicate broker comment or correlation token before preparation.
- Duplicate idempotency key with valid non-expired envelope → same envelope returned (no resubmit metadata loss).

## Lifecycle: QUEUED vs PREPARED vs SUBMITTED

```text
CREATED → QUEUED (validation)
QUEUED + preparation metadata (preparedAtUtc, comment, fingerprint) → still QUEUED
QUEUED → SUBMITTED only via CBrokerSubmissionTransitionGate + TryBrokerSubmitTransition(brokerSubmitAccepted=true)
```

| State | Meaning |
|-------|---------|
| QUEUED | Ready or prepared; **not** sent to broker |
| PREPARED metadata | `preparedAtUtc`, comment, fingerprint on entry — status remains QUEUED |
| SUBMITTED | Reserved for future real broker submit adapter only |

Preparation **never** sets `SUBMITTED`.

## Submission preparation flow

```text
Execution request (sealed)
→ validate basket version/profile hash
→ read-only quote + spread/session/volume/stops/freeze validation
→ build fingerprint + BRE comment stamp
→ collision check
→ create CBrokerSubmissionEnvelope
→ upsert CPendingExecutionEntry (QUEUED + preparation metadata)
→ persist to IPendingExecutionStore
→ return CSubmissionPreparationResult
```

Wired via `CExecutionSubmissionPreparer` in bootstrap. **Not** connected to strategy, REST, timer, OnTick, or automatic OnTradeTransaction execution.

## Restart behavior

`CFilePendingExecutionStore` persists entries + envelopes to `BasketRecovery/pending_executions.dat`.

On startup (`CPendingExecutionRestartService`):

1. Restore queued/prepared entries into `CPendingExecutionRegistry`
2. Detect duplicate comments/tokens (warn/skip)
3. **Do not auto-submit** — explicit future submission policy required

## Correlation compatibility

`CTradeTransactionCorrelationContext` parses `BRE|…` comments with checksum validation before extracting correlation token.

Priority unchanged: order → deal → ticket → magic+symbol+comment → fingerprint. Price-only matching forbidden.

## Prerequisites before OrderSendAsync

1. Implement broker submit adapter calling `TryBrokerSubmitTransition(..., brokerSubmitAccepted=true)` only after broker accepts async submit.
2. Wire submit adapter to prepared envelope from registry (never blind resend).
3. Keep `ITradeExecutor` boundary; do not bypass preparation/idempotency store.
4. Extend reconciliation for pending orders if needed.
5. Chart validation with async submit + stamped comment correlation.

## Key files

| Area | Files |
|------|-------|
| Domain | `BrokerSubmissionEnvelope.mqh`, `BrokerCommentStamp.mqh`, `ExecutionRequestFingerprint.mqh`, `SubmissionPreparationResult.mqh`, `BrokerSubmissionTransitionGate.mqh` |
| Application | `ExecutionSubmissionPreparer.mqh`, `SubmissionPreparationValidator.mqh`, `PendingExecutionRestartService.mqh` |
| Infrastructure | `InMemoryPendingExecutionStore.mqh`, `FilePendingExecutionStore.mqh` |
| Tests | `TestSubmissionPreparation.mq5` |
