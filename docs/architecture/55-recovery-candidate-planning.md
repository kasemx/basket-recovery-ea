# Sprint 7C — Recovery Candidate Planning

**Baseline:** commit `b5efe004e3225b76f817dd8634adfce5f0baa465`, tag `v0.7.1-recovery-projected-risk-gate`
**Status:** Implemented — read-only recovery candidate planner; **no recovery execution**

## Goal

Turn immutable strategy profile recovery configuration into a broker-accurate, read-only recovery candidate planner that answers:

```text
Should this basket propose the next recovery step now?
If yes, at what reference price and with what normalized volume?
Would the candidate pass projected max-risk validation?
```

No broker orders or execution requests are created by the planner.

## Decision Flow

```text
StrategyEngine proposes OPEN_RECOVERY
        |
        v
CRecoveryCandidatePlanner (trigger, zone, volume, safety gates)
        |
        +-- not DUE / blocked --> CRecoveryCandidateDomainEvent (audit only)
        |                         no OpenRecoveryPositionCommand
        |
        +-- DUE --> projected max-risk preview (CRecoveryDecisionRiskValidator)
        |
        +-- BLOCKED_BY_RISK --> audit event only
        |
        +-- still DUE --> Sprint 7B projected max-risk gate
        |
        +-- allowed --> CStrategyDecisionCommandMapper --> COpenRecoveryPositionCommand (stub handler)
```

Integration sits in `CEvaluateBasketStrategyUseCase` **after** `EvaluateAll` and **before** the Sprint 7B `ApplyRecoveryRiskGate`.

## Trigger Rules (BUY / SELL)

Reference price:

| Condition | Reference |
|-----------|-----------|
| No accepted recovery step yet | BUY → signal range **high**; SELL → signal range **low** |
| Prior recovery accepted | Entry price of highest open recovery step |

Executable price:

| Direction | Price used |
|-----------|------------|
| BUY | Ask |
| SELL | Bid |

Adverse move (pips):

| Direction | Formula |
|-----------|---------|
| BUY | `(reference - ask) / pipSize` |
| SELL | `(bid - reference) / pipSize` |

Due when `adverseMovePips >= step.DistancePips()` and movement is not favorable (`adverseMovePips >= 0`).

Step distance/lot resolved by `CRecoveryPlanResolver` for CONSTANT, CUSTOM, LINEAR, and PROGRESSIVE algorithms.

## Volume Resolution

| Policy | Behavior |
|--------|----------|
| Fixed volume | Step/profile lot value |
| Custom per-step | `steps[].lot` |
| Linear / progressive | Resolver-computed lot |
| Multiplier from prior recovery | Optional step policy (`LotMultiplierEnabled`) |
| Risk-budget derived | Placeholder — returns `RISK_BUDGET_NOT_IMPLEMENTED` |
| Normalization | `CSlRiskMath::NormalizeVolumeDown`; round-down only; invalid if normalized exceeds max or zero |

## Candidate Status Matrix

| Status | Meaning | Command created |
|--------|---------|-----------------|
| `NOT_DUE` | Insufficient adverse move, favorable move, or duplicate quote sequence | No |
| `DUE` | All gates passed including projected max-risk preview | Yes (subject to 7B gate) |
| `BLOCKED_BY_ZONE` | Executable price outside effective zone | No |
| `BLOCKED_BY_STEP_LIMIT` | No further profile steps | No |
| `BLOCKED_BY_PENDING_EXECUTION` | Unresolved pending execution | No |
| `BLOCKED_BY_RISK` | Projected max-risk preview failed | No |
| `BLOCKED_BY_SAFETY` | Lifecycle, recovery flags, BE disable, symbol mismatch | No |
| `INVALID_PROFILE` | Profile validation / unsupported algorithm | No |
| `INVALID_MARKET_CONTEXT` | Missing quote, stale quote, closed session | No |

## Zone Behavior

`CExecutionZoneResolver` produces `CEffectiveRecoveryZone` from profile execution zone + signal range (or fixed range) + expansion mode (SYMMETRIC, ASYMMETRIC, ABOVE_ONLY, BELOW_ONLY) + optional max recovery distance cap.

Candidate uses executable side price for zone containment check.

## Risk Gate Integration

Before returning `DUE`, `CRecoveryCandidatePlanningService` runs read-only `CRecoveryDecisionRiskValidator` preview. Failure sets `BLOCKED_BY_RISK`.

Allowed `DUE` candidates still pass through Sprint 7B `CRecoveryDecisionRiskGateService` before command mapping. Max risk remains hard gate; target risk remains advisory only.

## Idempotency

Dedupe key: `{basketId}:step:{stepIndex}:q:{quoteSequence}`

At most one candidate audit event per basket + step + quote sequence (`CRecoveryCandidateEventBuffer`).

Candidate evaluation does not mutate broker state or increment opened-recovery count.

## Events

- `BRE_EVENT_RECOVERY_CANDIDATE_EVALUATED`
- `BRE_EVENT_RECOVERY_CANDIDATE_DUE`
- `BRE_EVENT_RECOVERY_CANDIDATE_BLOCKED_BY_RISK`

## Explicit Non-Goals (Sprint 7C)

- No `OrderSend` / `OrderSendAsync` wiring
- No automatic recovery execution
- No REST / OnTick / OnTradeTransaction execution routes
- `COpenRecoveryPositionCommandHandler` remains stub

## Tests

`TestRecoveryCandidatePlanner.mq5` covers trigger direction, step models, zone behavior, safety blocks, volume normalization, risk block, and no-command guarantees.
