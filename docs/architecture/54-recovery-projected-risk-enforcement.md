# Sprint 7B — Recovery Projected Max-Risk Enforcement

**Baseline:** commit `8d506f0cec556e701ff34935450823967c7fc9ce`, tag `v0.7.0-live-basket-risk-engine`
**Status:** Implemented — mandatory projected max-risk gate for `OPEN_RECOVERY`; **no automatic execution**

## Goal

Every `OPEN_RECOVERY` strategy decision must pass projected basket SL max-risk validation before command creation. Strategy rules may propose recovery, but the risk gate blocks command mapping when projected risk exceeds the immutable basket max-risk profile.

## Decision Flow

```text
StrategyEngine proposes OPEN_RECOVERY
        |
        v
Build proposed position risk context
(CRecoveryProposedTradeRequestBuilder + CRiskCalculationContext)
        |
        v
CProjectedRiskCalculator (via CProposedPositionRiskValidator)
        |
        v
CRecoveryDecisionRiskValidator
        |
        +-- allowed --> CStrategyDecisionCommandMapper --> COpenRecoveryPositionCommand
        |
        +-- rejected --> CRecoveryRiskDomainEvent (RecoveryBlockedByRisk)
                         no execution request, no command enqueue
```

Integration sits in `CEvaluateBasketStrategyUseCase` **after** `EvaluateAll` and **before** `CStrategyDecisionCommandMapper`.

## Target vs Max Risk

| Limit | Role | Recovery behavior |
|-------|------|-------------------|
| **Max risk** | Hard projected SL gate | Blocks recovery when `projectedSlRiskMoney > maxRiskMoney` |
| **Target risk** | Advisory | Does **not** block recovery by itself; may emit `RiskReductionSuggested` with a pure `CRiskReductionPlan` |

Boundary rule: `projectedSlRiskMoney == maxRiskMoney` is **allowed** (`ExceedsMaxRisk` uses strict `>`).

## Block-Reason Matrix

| Condition | `ENUM_BRE_RECOVERY_RISK_BLOCK_REASON` |
|-----------|---------------------------------------|
| Projected SL risk > max | `BRE_RECOVERY_RISK_BLOCK_PROJECTED_EXCEEDS_MAX` |
| Basket risk UNKNOWN/UNSAFE | `BRE_RECOVERY_RISK_BLOCK_RISK_DATA_UNKNOWN` / `BRE_RECOVERY_RISK_BLOCK_RISK_DATA_UNSAFE` |
| Missing basket SL | `BRE_RECOVERY_RISK_BLOCK_MISSING_BASKET_SL` |
| Stale quote | `BRE_RECOVERY_RISK_BLOCK_STALE_QUOTE` |
| Invalid proposed volume (min/max/step) | `BRE_RECOVERY_RISK_BLOCK_INVALID_PROPOSED_VOLUME` |
| Basket SUSPENDED | `BRE_RECOVERY_RISK_BLOCK_BASKET_SUSPENDED` |
| Basket LOCKED | `BRE_RECOVERY_RISK_BLOCK_BASKET_LOCKED` |
| Basket CLOSING | `BRE_RECOVERY_RISK_BLOCK_BASKET_CLOSING` |
| Basket FINISHED | `BRE_RECOVERY_RISK_BLOCK_BASKET_FINISHED` |
| Basket ERROR / reconciling | `BRE_RECOVERY_RISK_BLOCK_BASKET_RECONCILING` |
| Basket not ACTIVE | `BRE_RECOVERY_RISK_BLOCK_BASKET_NOT_ACTIVE` |
| Unresolved pending execution | `BRE_RECOVERY_RISK_BLOCK_UNRESOLVED_PENDING_EXECUTION` |
| Profile hash mismatch | `BRE_RECOVERY_RISK_BLOCK_PROFILE_HASH_MISMATCH` |
| Direction/symbol conflict | `BRE_RECOVERY_RISK_BLOCK_DIRECTION_OR_SYMBOL_CONFLICT` |

## Events and Idempotency

Generic domain events only:

- `BRE_EVENT_RECOVERY_RISK_VALIDATED` — recovery passed projected max gate
- `BRE_EVENT_RECOVERY_BLOCKED_BY_RISK` — recovery blocked with audit payload
- `BRE_EVENT_RISK_REDUCTION_SUGGESTED` — target exceeded, advisory plan available

`CRecoveryRiskEventBuffer` dedupe key: `{eventType}:{strategyDecisionId}:{quoteSequence}`.

Rate limit: unchanged blocked condition within 30s window does not emit duplicate events.

## Strategy Context Extension

`CStrategyEvaluationContext` now carries optional `CStrategyRiskEvaluationContext`:

- immutable `CRiskLimitProfile`
- `CBasketRiskSnapshot`
- risk data quality (`ENUM_BRE_RISK_SAFETY_STATUS`)
- active basket SL
- quote sequence
- unresolved pending execution flag
- optional `CRiskReductionPlan`

Populated by `CRecoveryDecisionRiskGateService` during gate evaluation.

## Key Types

- `CRiskGatedStrategyDecision` — decision + optional gate result
- `CRecoveryDecisionRiskGateResult` — allowed flag, audit, optional reduction plan
- `CRecoveryRiskDecisionAudit` — full audit record (basket, decision, risk numbers, block reason, hash, version, timestamp)
- `CRecoveryDecisionRiskValidator` — domain validator (no broker calls)
- `CRecoveryDecisionRiskGateService` — application orchestration

## Execution Safety Proof

This sprint does **not** submit recovery orders:

- Gate runs before `COpenRecoveryPositionCommand` creation
- Blocked recoveries never reach command queue
- No `OrderSend`, `OrderSendAsync`, `PositionClose`, `PositionModify`, or `CTrade` in risk gate scope
- `COpenRecoveryPositionCommandHandler` remains stub; no new auto-submit wiring
- Target-risk reduction plan is advisory only — not executed

## Tests

`TestRecoveryProjectedRiskGate.mq5` covers allowed/blocked paths, target-vs-max behavior, event dedupe, mapper bypass prevention, and scope safety.
