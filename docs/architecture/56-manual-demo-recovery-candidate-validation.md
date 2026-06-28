# Sprint 7D — Manual Demo Recovery Candidate Validation

Baseline: `v0.7.2-recovery-candidate-planner` / commit `b96fd27bc82dd88260bc0feb9e266952eea5c672`

Automatic recovery execution remains **disabled**. Sprint 7D adds a controlled manual demo path for one risk-approved `DUE` recovery candidate per session.

## Candidate-to-order flow

```text
StrategyEngine → OPEN_RECOVERY
→ RecoveryCandidatePlanner (7C)
→ RecoveryDecisionRiskGate (7B projected max-risk)
→ ManualRecoveryCandidateRegistrationService
→ ManualRecoveryCandidateRegistry (AVAILABLE)
→ operator selects candidate (EA input InpManualRecoveryCandidateId)
→ RecoveryCandidateSubmissionValidator (revalidation)
→ RecoveryCandidateExecutionRequestFactory (immutable sealed OPEN_POSITION)
→ ExecutionSubmissionPreparer
→ manual demo authorization (InpManualDemoAuthorizationToken)
→ CDemoManualSubmissionService → CMt5AsyncSubmissionGateway → OrderSendAsync
→ OnTradeTransaction correlation
→ RecoveryStepExecutionTracker (FILLED only)
```

## Registry eligibility

A candidate enters `CManualRecoveryCandidateRegistry` only when all conditions hold:

| Condition | Enforcement |
|-----------|-------------|
| `DUE` | `RecoveryCandidatePlanner` + registration filter |
| Projected max-risk allowed | `RecoveryDecisionRiskValidator` at registration |
| Basket `ACTIVE` | Planner + registration context |
| No unresolved pending execution | `RecoveryPendingExecutionChecker` |
| Recovery enabled | Basket mode flags |
| Quote fresh | Planner stale threshold |
| In execution zone | Planner trigger/zone evaluation |

Stored fields: basket id, strategy decision id, candidate idempotency key, step index, symbol, direction, trigger/reference price, executable bid/ask, volume, basket SL, current/projected SL risk, target/max risk, profile hash, basket version, quote sequence, expiry, status.

## Expiry and revalidation

- Config: `InpManualRecoveryCandidateExpirySeconds` (default **30**)
- Registry sweeps stale entries on each registration pass
- Before submit, `CRecoveryCandidateSubmissionValidator` re-checks:
  - expiry
  - quote freshness
  - executable side price / zone / step still due
  - volume validity
  - basket lifecycle + version + profile hash
  - no pending execution
  - projected max-risk gate
  - step not already executed
- Any failure → `REJECTED` / requires newly generated candidate

## Manual authorization rules

Required EA inputs for recovery submit:

| Input | Purpose |
|-------|---------|
| `InpExecutionMode = DEMO_MANUAL_SUBMISSION` | Route gate |
| `InpEnableLiveDemoExecution = true` | Demo execution enabled |
| `InpRequireManualDemoAuthorization = true` | Token required |
| `InpManualRecoveryCandidateId` | Candidate idempotency key |
| `InpManualDemoAuthorizationToken` | One-shot auth token |
| `InpManualRecoverySubmissionTriggerToken` | One-shot submit trigger |
| `InpManualDemoAuthorizationBasketId` | Basket binding |

Rules:

- Only `OPEN_RECOVERY` candidates accepted
- Direction/volume/symbol/SL/step come from candidate entry — **not** from free-form UI lot/side inputs
- Recovery trigger consumed after one attempt
- Authorization token consumed only after broker submission attempt (existing demo policy)
- Rejected/expired candidates cannot be reused
- `InpMaxManualDemoOpenVolume` still applies
- Max **one** recovery submission per demo session (`MaxRecoverySubmissionsPerSession = 1`)

## Recovery step advancement policy

| Event | Step state |
|-------|------------|
| Candidate registered | No advancement |
| Manual submit accepted | `MarkSubmitted` only (not executed) |
| Broker reject / timeout / unknown | No advancement |
| `OnTradeTransaction` → `FILLED` | `RecoveryStepExecutionTracker.TryMarkFilled` once |
| Duplicate transaction | Ignored (no double advance) |

Broker-confirmed fill is the sole signal that advances executed recovery-step tracking for this sprint.

## Safety restrictions (7D)

- Demo account only (existing live submission safety gate)
- One recovery submission per session
- One symbol per session (existing auth registry lock)
- Market `DEAL` open only
- No recovery close/reduce/modify
- No TP/BE/trailing via this route
- No auto-retry
- No automatic recovery submission from StrategyEngine, REST, OnTick, automatic OnTimer, or OnTradeTransaction
- No real-account support
- No restart auto-submit for recovery candidates

## Components

| Layer | Types |
|-------|-------|
| Domain | `ManualRecoveryCandidateEntry`, `ManualRecoveryCandidateSelection`, `RecoveryCandidateManualAuthorizationContext`, `RecoveryCandidateExecutionRequestFactory` |
| Application | `ManualRecoveryCandidateRegistry`, `ManualRecoveryCandidateRegistrationService`, `RecoveryCandidateSubmissionValidator`, `ManualRecoveryCandidateSubmissionService`, `RecoveryStepExecutionTracker`, `ManualRecoveryCandidateTriggerRegistry` |
| Events | `RecoveryCandidateAvailable`, `RecoveryCandidateExpired`, `RecoveryCandidateManuallySelected`, `RecoverySubmissionRejected`, `RecoverySubmissionSubmitted` |

## Broker API constraint

No new `OrderSendAsync` caller. Recovery manual submit reuses `CDemoManualSubmissionService` → `CMt5AsyncSubmissionGateway`.

## Tests

`TestManualRecoveryCandidateValidation.mq5` covers registry admission, expiry, factory binding, trigger one-shot, step fill idempotency, stale quote / pending execution revalidation, session cap, and no automatic wiring flags.

## Explicit statement

**Automatic recovery execution is still disabled.** Sprint 7D validates manual demo submission of a single approved candidate only; strategy commands for `OPEN_RECOVERY` remain stubbed/non-broker for automatic paths.
