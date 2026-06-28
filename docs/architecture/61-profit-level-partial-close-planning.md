# Sprint 8B — Profit-Level Partial-Close Candidate Planning

**Baseline:** commit `36775aeaababfe20bbea6f50c80c63949ddb3769`, tag `v0.7.4-pending-terminalization`
**Status:** Implemented — read-only profit-level partial-close candidate planner; **close execution remains disabled**

## Goal

Evaluate configured basket profit levels and produce a deterministic partial-close **candidate** and audit record only. No broker close request, no close command submission, no automated execution.

The planner answers:

```text
Has a configured profit level been reached?
If yes, which active basket positions should be reduced?
How much volume should be reduced from each position?
Would the resulting close plan be valid under broker volume constraints?
```

## Generic Unlimited Profit-Level Model

Profit levels come from immutable `StrategyProfile.ProfitDistributionPlan()` — unlimited `levels[]` entries. No TP1/TP2/TP3 lifecycle states.

Each level supports:

| Field | Purpose |
|-------|---------|
| `level_id` / `level_index` | Stable identifier and ordering |
| `source` / `trigger_type` | Trigger semantics (see below) |
| `trigger_value` / `price` | Threshold for trigger evaluation |
| `close_percent` | Share of **current basket floating profit** to realize |
| `close_mode` | Position-selection policy |
| `partial_close` | Profile hint (planner always plans volume reductions) |
| `enabled` | Skip when false |

Progress is tracked separately via `CBasketProfitLevelProgress` (`not started` → `candidate generated` → `manually submitted` → `completed` after future broker-confirmed fill). **Sprint 8B never marks a level complete.**

## Trigger Semantics

Resolved by `CProfitLevelTriggerResolver` + `CProfitLevelTriggerEvaluator`.

| Trigger type | Reached when | Sprint 8B |
|--------------|--------------|-----------|
| `FLOATING_PROFIT_MONEY` | `floatingProfitUsd >= triggerValue` | Implemented |
| `FLOATING_PROFIT_PCT_TARGET_RISK` | `floatingProfitUsd >= targetRiskMoney × triggerValue / 100` | Implemented |
| `FLOATING_PROFIT_PCT_EQUITY` | `floatingProfitUsd >= equity × triggerValue / 100` | Implemented |
| `STRATEGY_PRICE_LEVEL` | Executable close-side price crosses configured level (`FIXED_PRICE` infers this) | Implemented |
| `SIGNAL_TP`, `DYNAMIC`, `FUTURE_PLACEHOLDER` | — | `NOT_IMPLEMENTED` |

Rules:

- Floating profit must be positive when `require_floating_profit_positive` is true (default).
- Only the **first enabled, unfinished** level is evaluated per cycle.
- Unsupported triggers return explicit `NOT_IMPLEMENTED` or `INVALID_PROFILE` — never silent pass.

### Target close money

For a reached level:

```text
targetCloseMoney = currentBasketFloatingProfit × (configuredClosePercent / 100)
```

The percentage applies to floating profit at evaluation time, not cumulative basket volume.

## Position-Selection Policies

Deterministic ordering via `CProfitLevelPositionSelector`:

| Policy | Behavior |
|--------|----------|
| `WORST_ENTRY_FIRST` | Worst entry for basket direction first |
| `BEST_ENTRY_FIRST` | Best entry for basket direction first |
| `LARGEST_PROFIT_FIRST` (`PROFIT_BASED`) | Highest floating profit first |
| `LARGEST_VOLUME_FIRST` (`LARGEST_LOT_FIRST`) | Largest lot first |
| `FIFO` | Oldest open time first |
| `LIFO` | Newest open time first |

Each position’s contribution uses proportional floating profit: `estimatedCloseMoney = floatingProfit × (closeVolume / lot)`.

## Volume Normalization

`CProfitLevelCloseVolumePlanner`:

- Greedy allocation along ordered positions until `targetCloseMoney` is met (or all positions for 100%).
- Every volume normalized **down** via `CSlRiskMath::NormalizeVolumeDown`.
- Never exceeds position lot; never emits zero-volume instructions.
- If broker min/step prevents meeting target → `INVALID_CLOSE_PLAN`.
- If min/step forces closing more than target → `DUE` with `BROKER_MIN_VOLUME_OVERRUN` reason and `minimumVolumeOverrun=true`.

## Status Matrix

| Status | Meaning | Execution |
|--------|---------|-----------|
| `NOT_REACHED` | Trigger not satisfied, duplicate quote, or negative floating profit gate | None |
| `DUE` | Level reached, plan valid | Audit/event only — **no close command** |
| `ALREADY_COMPLETED` | All levels completed | None |
| `BLOCKED_BY_PENDING_EXECUTION` | Unresolved pending execution | None |
| `BLOCKED_BY_SAFETY` | Non-ACTIVE lifecycle, basket locked, symbol mismatch | None |
| `INVALID_PROFILE` | Profile validation failure | None |
| `INVALID_MARKET_CONTEXT` | Missing/stale quote, closed session | None |
| `INVALID_CLOSE_PLAN` | No positions or volume plan failed | None |
| `NOT_IMPLEMENTED` | Unsupported trigger type | None |

## Idempotency and Progress

- Idempotency key: `profit-level-close:{basketId}:level:{profitLevelId}:q:{quoteSequence}`
- Event dedupe: `eventType:basketId:profitLevelId:quoteSequence` (`CProfitLevelCloseCandidateEventBuffer`)
- Duplicate quote sequence → `NOT_REACHED` + `DUPLICATE_QUOTE_SEQUENCE`; no second audit emission
- Candidate generation does **not** mutate basket progress or mark levels complete

## Integration Flow

```text
ACTIVE basket
→ StrategyEngine.EvaluateAll
→ ApplyRecoveryCandidatePlanning (unchanged)
→ ApplyProfitLevelCloseCandidatePlanning (NEW — read-only)
→ ApplyRecoveryRiskGate
→ StrategyDecisionCommandMapper (no close mapping from 8B candidate)
```

Wired in `CEvaluateBasketStrategyUseCase`, `CApplicationKernel`, `Bootstrapper`.

## Events

- `BRE_EVENT_PROFIT_LEVEL_EVALUATED`
- `BRE_EVENT_PROFIT_LEVEL_CLOSE_CANDIDATE_AVAILABLE` (DUE)
- `BRE_EVENT_PROFIT_LEVEL_CLOSE_CANDIDATE_BLOCKED`
- `BRE_EVENT_PROFIT_LEVEL_CLOSE_PLAN_INVALID`

## Explicit Non-Goals (Sprint 8B)

- No `PositionClose`, `PositionModify`, `CTrade`, `OrderSend`, or `OrderSendAsync`
- No connection to `CTradeExecutionRequest`, close handlers, or `Mt5AsyncSubmissionGateway`
- No automatic partial-close execution
- No TP1/TP2/TP3-specific lifecycle states

## Key Files

| File | Role |
|------|------|
| `Domain/Strategy/Services/ProfitLevelCloseCandidatePlanner.mqh` | Main read-only planner |
| `Domain/Strategy/Services/ProfitLevelTriggerEvaluator.mqh` | Trigger reach checks |
| `Domain/Strategy/Services/ProfitLevelCloseVolumePlanner.mqh` | Volume/money planning |
| `Application/Strategy/ProfitLevelCloseCandidatePlanningService.mqh` | Integration + events |
| `Scripts/BasketRecovery/Tests/TestProfitLevelCloseCandidatePlanner.mq5` | Sprint test coverage |
