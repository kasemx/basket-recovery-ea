# Sprint 6F — Live Submission Safety Gate and Manual Demo Authorization

**Baseline:** commit `47ef7af067a9773d349f09ac79d814c141569615`, tag `v0.6.4-simulated-submission-acknowledgement-path`
**Scope:** Authorization model, deterministic safety gates, and one-shot manual demo token policy. **No broker submission.**

## Goal

Define exactly when a prepared execution request is eligible for **future** broker submission and require explicit one-shot human authorization. This sprint **never** invokes `OrderSend`, `OrderSendAsync`, `CTrade`, `PositionClose`, or `PositionModify`.

Successful authorization produces only:

```text
AUTHORIZED_FOR_FUTURE_SUBMISSION
```

No submission gateway is called. No broker state is mutated.

## Authorization flow

```text
manual authorization test route (explicit EA inputs only)
→ resolve prepared QUEUED request (CPreparedSubmissionValidator)
→ validate one-shot token format, expiry, binding fingerprint
→ verify demo account eligibility (read-only MT5 snapshot)
→ evaluate CLiveSubmissionSafetyGate (deterministic matrix)
→ return AUTHORIZED_FOR_FUTURE_SUBMISSION or precise rejection reason
→ consume token only on success (persist token hash, never plaintext)
→ no broker call
```

```text
                    ┌─────────────────────────┐
                    │  Manual route enabled?  │
                    │  (mode + inputs)        │
                    └───────────┬─────────────┘
                                │ no
                                ▼
                         LIVE_DISABLED / reject
                                │ yes
                                ▼
                    ┌─────────────────────────┐
                    │ Kill switches / cap     │
                    └───────────┬─────────────┘
                                │ pass
                                ▼
                    ┌─────────────────────────┐
                    │ Token parse + expiry    │
                    │ + binding fingerprint   │
                    └───────────┬─────────────┘
                                │ pass
                                ▼
                    ┌─────────────────────────┐
                    │ Prepared QUEUED entry   │
                    └───────────┬─────────────┘
                                │ pass
                                ▼
                    ┌─────────────────────────┐
                    │ CLiveSubmissionSafetyGate│
                    └───────────┬─────────────┘
                                │ pass
                                ▼
              AUTHORIZED_FOR_FUTURE_SUBMISSION
              (token consumed, hash persisted)
```

## Authorization model

| Type | Role |
|------|------|
| `ExecutionAuthorizationToken` | Plaintext token format, binding fingerprint (CRC32), hash, expiry |
| `ExecutionAuthorizationScope` | Authorization scope enum |
| `ExecutionAuthorizationStatus` | Includes `AUTHORIZED_FOR_FUTURE_SUBMISSION` |
| `ManualDemoExecutionAuthorization` | Persisted record (hash only, consumed state, result) |
| `ExecutionAuthorizationRegistry` | Session cap, consumed-token tracking, restore |
| `ExecutionAuthorizationPolicy` | Default scope, demo-only resolution, kill-switch helpers |

### Authorization scopes

| Scope | Meaning in 6F |
|-------|---------------|
| `NONE` | No authorization |
| `DRY_RUN_ONLY` | Reserved — not auto-enabled |
| `SIMULATED_ONLY` | Reserved — not auto-enabled |
| `DEMO_SINGLE_REQUEST` | Issued on successful manual demo authorization |
| `DEMO_BASKET_SESSION` | Reserved for future session-scoped demo |
| `LIVE_DISABLED` | **Default runtime** — rejects all future submission authorization |

Default runtime behavior: **`LIVE_DISABLED`**. No mode enables real order submission in this sprint.

## One-shot manual demo authorization

A future demo submission must require **all** of:

| Requirement | Input / check |
|-------------|---------------|
| Demo account | `CMt5AccountExecutionEligibilityProvider` — explicit `ACCOUNT_TRADE_MODE_DEMO` only |
| Terminal Algo Trading | `TERMINAL_TRADE_ALLOWED` |
| Chart EA permission | `MQL_TRADE_ALLOWED` |
| Execution mode | `InpExecutionMode` = `BRE_EXEC_RUNTIME_DEMO_AUTHORIZATION` (3) |
| Live demo flag | `InpEnableLiveDemoExecution = true` |
| Manual token | `InpManualDemoAuthorizationToken` non-empty and new |
| Request binding | Token fingerprint tied to request metadata (see below) |

### Token binding and expiry

Token format:

```text
BRE-DEMO-{bindingFingerprint}-{expiryUtc}
```

Binding fingerprint (8-char CRC32 hex) covers:

- `executionRequestId`
- `basketId`
- `symbol`
- intent type
- requested volume
- expected basket version
- strategy profile hash

Rules:

- Token may be consumed **exactly once** on successful authorization.
- Token is invalid after restart unless explicitly restored under safe policy (expired → invalid; consumed → stays consumed).
- Token cannot authorize a different request, basket, volume, side, symbol, or profile hash.
- Plaintext token is **never** persisted — only `ComputeTokenHash(plaintext)` is stored.

## Safety gate matrix

`CLiveSubmissionSafetyGate::Evaluate` runs deterministically. First failure wins with a precise `ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON`.

| # | Gate | Rejection reason |
|---|------|------------------|
| 1 | Global execution kill switch | `GLOBAL_KILL_SWITCH` |
| 2 | Basket execution kill switch | `BASKET_KILL_SWITCH` |
| 3 | Account is explicit demo | `ACCOUNT_NOT_DEMO` / `ACCOUNT_UNKNOWN` |
| 4 | Account trade permission | `ACCOUNT_TRADE_DISABLED` |
| 5 | Terminal Algo Trading | `TERMINAL_ALGO_DISABLED` |
| 6 | Chart EA trading permission | `CHART_EA_TRADE_DISABLED` |
| 7 | Basket lifecycle ACTIVE | `BASKET_NOT_ACTIVE` / `BASKET_LOCKED` |
| 8 | Strategy profile hash match | `PROFILE_HASH_MISMATCH` |
| 9 | Expected basket version match | `BASKET_VERSION_MISMATCH` |
| 10 | Request QUEUED + prepared | `NOT_QUEUED_PREPARED` |
| 11 | Envelope not expired | `ENVELOPE_EXPIRED` |
| 12 | Quote fresh | `STALE_QUOTE` |
| 13 | Spread within threshold | `WIDE_SPREAD` |
| 14 | Market/session open | `MARKET_UNAVAILABLE` |
| 15 | Volume min/max valid | `VOLUME_INVALID` |
| 16 | Stop/freeze constraints valid | `STOP_FREEZE_INVALID` |
| 17 | No conflicting pending request | `CONFLICTING_PENDING` |
| 18 | No UNKNOWN/RECONCILING/TIMED_OUT block | `BASKET_RECONCILING_BLOCK` |
| 19 | Daily loss placeholder | `DAILY_LOSS_GATE` |
| 20 | Max concurrent placeholder | `MAX_CONCURRENT_GATE` |

Use-case pre-gates (before safety matrix):

| Check | Rejection reason |
|-------|------------------|
| Runtime mode / demo flag | `LIVE_DISABLED`, `EXECUTION_MODE_INVALID`, `DEMO_EXECUTION_DISABLED` |
| Manual token required | `TOKEN_MISSING`, `TOKEN_INVALID`, `TOKEN_EXPIRED`, `TOKEN_CONSUMED` |
| Session cap | `SESSION_CAP_EXCEEDED` |
| Token binding | `TOKEN_BINDING_MISMATCH` |
| Prepared request exists | `REQUEST_NOT_FOUND` |

## Demo account classification policy

`IAccountExecutionEligibilityProvider` / `CMt5AccountExecutionEligibilityProvider` — **read-only** only:

| Field | Source |
|-------|--------|
| Account trade mode | `ACCOUNT_TRADE_MODE` |
| Account trade allowed | `ACCOUNT_TRADE_ALLOWED` |
| Terminal trade allowed | `TERMINAL_TRADE_ALLOWED` |
| Chart EA trade allowed | `MQL_TRADE_ALLOWED` |
| Server/name/login metadata | Account info strings |
| Balance/equity placeholders | `ACCOUNT_BALANCE`, `ACCOUNT_EQUITY` |

Conservative classification:

| Classification | Authorization |
|----------------|---------------|
| `ACCOUNT_TRADE_MODE_DEMO` | Pass demo gate |
| `ACCOUNT_TRADE_MODE_REAL` | **Reject** |
| Unknown / other | **Reject** |

No broker submission calls from this adapter.

## Kill switches (default off)

| Input | Default | Behavior |
|-------|---------|----------|
| `InpEnableLiveDemoExecution` | `false` | Blocks demo authorization path |
| `InpRequireManualDemoAuthorization` | `true` | Token required when enabled |
| `InpGlobalExecutionKillSwitch` | `false` | Immediately rejects all future submissions |
| `InpBasketExecutionKillSwitch` | `false` | Rejects matching basket (or all if basket id empty) |
| `InpMaxAuthorizedRequestsPerSession` | `1` | Session authorization cap |
| `InpAuthorizationTokenExpirySeconds` | `300` | Token TTL guidance for issuance |

Rules:

- Disabling an input **never** mutates existing positions.
- No automatic fallback from rejected authorization to simulation or dry-run.
- One authorized request per token; session cap enforced in registry.

## Runtime isolation

Authorization is **not** wired to:

| Path | Wired? |
|------|--------|
| StrategyEngine | **No** |
| REST signal intake | **No** |
| OnTick | **No** |
| Automatic OnTimer execution | **No** |
| Normal fast-path evaluation | **No** |
| `CSubmitPreparedExecutionUseCase` / submission gateway | **No** |
| `ITradeExecutor` production dry-run | **No** |

Manual test route only:

- EA inputs: `InpManualDemoAuthorizationToken`, `InpManualDemoAuthorizationRequestId`, `InpManualDemoAuthorizationBasketId`
- `CApplicationContext::TryProcessManualDemoAuthorizationValidation`
- `CManualDemoAuthorizationValidationService::TryProcessManualAuthorizationForBasket`

Isolation flags (`CApplicationContext`):

- `IsDemoAuthorizationWiredToStrategy()` → `false`
- `IsDemoAuthorizationWiredToAutomaticTimer()` → `false`
- `IsDemoAuthorizationWiredToRestIntake()` → `false`
- `IsDemoAuthorizationWiredToOnTick()` → `false`
- `IsLiveSubmissionApiWiredToProductionRuntime()` → `false`

## Persistence and restart

Persisted metadata (safe only):

- Token **hash** (never plaintext)
- Execution request id
- Basket id
- Expiry UTC
- Consumed state
- Authorization status / scope
- Rejection reason and detail on failure

On restart:

- Expired tokens → invalid
- Consumed tokens → stay consumed
- Authorized-but-not-submitted requests → **no auto-submit**
- Pending QUEUED requests still require new explicit authorization for any future real submission

## Explicit non-goals (this sprint)

- **No order submission** of any kind
- **No** `OrderSend` / `OrderSendAsync` / `CTrade` / position mutation APIs
- **No** wiring authorization success to `CSubmitPreparedExecutionUseCase`
- **No** commit to automatic submission paths

## Prerequisites before OrderSendAsync integration

1. Implement non-simulated `ISubmissionGateway` with async MT5 adapter (separate sprint).
2. Require prior `AUTHORIZED_FOR_FUTURE_SUBMISSION` record for the specific request id + binding.
3. Re-run full `CLiveSubmissionSafetyGate` immediately before submit (quote/envelope may have changed).
4. Keep `CSubmitPreparedExecutionUseCase` as sole `TryBrokerSubmitTransition` caller.
5. Gate bootstrap with explicit production execution-mode flag and demo-account guard.
6. Preserve idempotency store, correlation stamping, and pending execution state machine from 6D–6E.
7. Never auto-submit on restart or timer — human authorization remains one-shot per request.

## Key files

| Area | Files |
|------|-------|
| Domain | `ExecutionAuthorizationScope.mqh`, `ExecutionAuthorizationStatus.mqh`, `ExecutionAuthorizationToken.mqh`, `ManualDemoExecutionAuthorization.mqh`, `ExecutionAuthorizationResult.mqh`, `LiveSubmissionSafetyRejectionReason.mqh`, `AccountExecutionEligibilitySnapshot.mqh`, `AccountExecutionEligibilityClassification.mqh` |
| Application | `ExecutionAuthorizationPolicy.mqh`, `ExecutionAuthorizationRegistry.mqh`, `LiveSubmissionSafetyGate.mqh`, `LiveSubmissionSafetyGateContext.mqh`, `ManualDemoAuthorizationUseCase.mqh`, `ManualDemoAuthorizationValidationService.mqh`, `DemoExecutionAuthorizationConfig.mqh`, `ExecutionAuthorizationPersistenceCodec.mqh`, `Ports/IExecutionAuthorizationStore.mqh`, `Ports/IAccountExecutionEligibilityProvider.mqh` |
| Infrastructure | `Mt5AccountExecutionEligibilityProvider.mqh`, `InMemoryExecutionAuthorizationStore.mqh`, `InMemoryAccountExecutionEligibilityProvider.mqh` |
| Tests | `TestLiveSubmissionSafetyAndDemoAuthorization.mq5` |
