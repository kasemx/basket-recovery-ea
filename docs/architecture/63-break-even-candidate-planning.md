# Sprint 9A — Basket Break-Even Candidate Planning

**Baseline:** commit `451418fbd29a458c1d0c71c6c98116b7b7a8be2c`, tag `v0.8.2-history-aware-reconciliation`
**Status:** Implemented — read-only break-even candidate planner; **break-even execution remains disabled**

## Goal

Evaluate configured `break_even_plan` rules and produce one deterministic break-even **candidate** and audit record only. No `PositionModify`, no stop-loss mutation, no recovery disable mutation, and no automated execution.

The planner answers:

```text
Has the configured break-even trigger been reached?
If yes, what exact broker-valid stop-loss price should be proposed?
Should recovery be permanently disabled after break-even activation?
```

Recommendations (`recoveryDisableRecommended`, `lockRecommended`, `trailingHandoffPlaceholder`) are audit-only in Sprint 9A.

## Generic Trigger / Action Model

Rules come from immutable `StrategyProfile.BreakEvenPlan()` — no TP1/TP2/TP3-specific lifecycle.

Each `CBreakEvenRule` supports:

| Field | Purpose |
|-------|---------|
| `rule_id` | Stable identifier |
| `priority` | Lower number evaluates first among eligible rules |
| `run_once` | Skip when rule id already in executed set |
| `trigger` | When to propose break-even |
| `actions[]` | SL move + optional policy recommendations |

### Supported candidate trigger types

Resolved by `CBreakEvenCandidateTriggerEvaluator` from profile `CBreakEvenTrigger`:

| Candidate trigger | Profile source | Reached when |
|-------------------|----------------|--------------|
| `FLOATING_PROFIT_MONEY` | `FLOATING_PROFIT` + `floating_profit_usd` | `floatingProfitUsd >= threshold` |
| `FLOATING_PROFIT_PCT_TARGET_RISK` | `FLOATING_PROFIT` + `percent_of_target_risk` | `floatingProfitUsd >= targetRiskMoney × pct / 100` |
| `REALIZED_PROFIT_MONEY` | `REALIZED_PROFIT` + `realized_profit_usd` or pct | Realized profit threshold met |
| `PROFIT_LEVEL_COMPLETED` | `SPECIFIC_PROFIT_LEVEL` | Profit level progress completed or runtime reached |
| `RISK_REDUCTION_COMPLETED` | `SPECIFIC_BASKET_STATE` = `RISK_REDUCTION_COMPLETED` | Context `riskReductionCompleted` |
| `MANUAL_EVENT` | `MANUAL` | `manualBreakEvenRequested` |
| Future / unsupported | `SPECIFIC_EVENT`, `TARGET_RISK_REACHED`, etc. | `NOT_IMPLEMENTED` |

## BUY / SELL Stop-Loss Formulas

Weighted average entry uses active basket positions (`CSlRiskMath::ComputeWeightedAverageEntry`).

From the first `MOVE_SL_TO_AVERAGE` or `MOVE_SL_WITH_OFFSET` action:

```text
spreadComponent   = include_spread ? (ask - bid) : 0
safetyBuffer      = buffer_pips × pipSize   (MOVE_SL_TO_AVERAGE)
                  = sl_offset_pips × pipSize (MOVE_SL_WITH_OFFSET)

BUY:  proposedSL = weightedAverageEntry + spreadComponent + safetyBuffer
SELL: proposedSL = weightedAverageEntry - spreadComponent - safetyBuffer
```

Post-formula:

1. Normalize to symbol `tickSize` (`MathRound(price / tickSize) × tickSize`)
2. Validate against read-only `CSymbolTradingConstraints` stop/freeze levels
3. **Do not weaken** the proposal to force validity — invalid placement returns `INVALID_STOP_PRICE`

Executable price for validation: BUY → bid, SELL → ask.

## Broker Validity Rules

`CBreakEvenStopPriceValidator` (domain-only, no MT5 APIs):

| Check | BUY | SELL |
|-------|-----|------|
| SL vs executable | `proposedSL < bid` | `proposedSL > ask` |
| Stops level | `bid - proposedSL >= stopsLevel × point` | `proposedSL - ask >= stopsLevel × point` |
| Freeze level | Same distance vs `freezeLevel × point` | Same |

Failures map to `INVALID_STOP_PRICE` with `STOP_LEVEL_VIOLATION` or `FREEZE_LEVEL_VIOLATION`.

## Status Matrix

| Status | Meaning | Execution |
|--------|---------|-----------|
| `NOT_REACHED` | Trigger not satisfied or duplicate quote | None |
| `DUE` | Trigger reached, SL valid | Audit/event only |
| `ALREADY_ACTIVATED` | `breakEvenActive` or all rules executed | None |
| `BLOCKED_BY_PENDING_EXECUTION` | Unresolved pending execution | None |
| `BLOCKED_BY_SAFETY` | Non-ACTIVE lifecycle, locked, no positions | None |
| `INVALID_PROFILE` | Empty/invalid plan or missing SL action | None |
| `INVALID_MARKET_CONTEXT` | Missing/stale quote, closed session | None |
| `INVALID_STOP_PRICE` | Broker stop/freeze constraint violation | None |
| `NOT_IMPLEMENTED` | Unsupported trigger type | None |

## Progress / Idempotency

- Idempotency key: `break-even-candidate:{basketId}:rule:{ruleId}:q:{quoteSequence}`
- Event dedupe: `eventType:basketId:quoteSequence` (`CBreakEvenCandidateEventBuffer`)
- Duplicate quote sequence → `NOT_REACHED` + `DUPLICATE_QUOTE_SEQUENCE`
- `DUE` does **not** set `breakEvenActive`, disable recovery, or lock basket
- Only a future broker-confirmed stop-loss modification may mark BE activated and apply policy actions

## Events

- `BRE_EVENT_BREAK_EVEN_EVALUATED`
- `BRE_EVENT_BREAK_EVEN_CANDIDATE_AVAILABLE` (DUE)
- `BRE_EVENT_BREAK_EVEN_CANDIDATE_BLOCKED`
- `BRE_EVENT_BREAK_EVEN_STOP_PRICE_INVALID`

## Explicit Non-Goals (Sprint 9A)

- No `PositionModify`, `CTrade`, `OrderSend`, or `OrderSendAsync`
- No automatic break-even, trailing, recovery, or partial-close execution
- No wiring into `StrategyDecisionCommandMapper` for BE submission
- Existing `CBreakEvenEvaluator` decision path unchanged

## Key Files

| File | Role |
|------|------|
| `Domain/Strategy/Services/BreakEvenCandidatePlanner.mqh` | Main read-only planner |
| `Domain/Strategy/Services/BreakEvenCandidateTriggerEvaluator.mqh` | Trigger reach checks |
| `Domain/Strategy/Services/BreakEvenPriceCalculationService.mqh` | SL price math |
| `Domain/Strategy/Services/BreakEvenStopPriceValidator.mqh` | Stop/freeze validation |
| `Application/Strategy/BreakEvenCandidatePlanningService.mqh` | Context build + events |
| `Scripts/BasketRecovery/Tests/TestBreakEvenCandidatePlanner.mq5` | Sprint test coverage |

## Tests

`TestBreakEvenCandidatePlanner.mq5` covers BUY/SELL weighted-average math, spread/buffer, tick normalization, stop/freeze invalid price, trigger gates, safety blocks, dedupe, progress non-mutation, and `NOT_IMPLEMENTED` triggers.

## Runtime Wiring (Sprint 9A.1)

`CBreakEvenCandidatePlanningService` is now evaluated in the read-only basket evaluation runtime path via `CEvaluateBasketStrategyUseCase`.

### Integration point

After market context refresh and read-only recovery / profit-level candidate evaluation, and **before** recovery risk gate and manual registration:

```text
ACTIVE basket
→ live market/risk/profit context (StrategyEvaluationContextFactory)
→ recovery candidate planning (ApplyRecoveryCandidatePlanning)
→ profit-level close planning (ApplyProfitLevelCloseCandidatePlanning)
→ break-even candidate planning (ApplyBreakEvenCandidatePlanning)
→ recovery risk gate + manual registration (unchanged)
→ audit/events only (CBreakEvenCandidateEventBuffer)
```

Wiring is composed in `Bootstrapper` → `ApplicationKernel.ConfigureBreakEvenCandidatePlanning` and `ApplicationContext.RegisterBreakEvenCandidateRuntime`.

### Runtime behavior

- Eligible ACTIVE baskets evaluate configured `break_even_plan` rules each evaluation tick.
- Emits `BRE_EVENT_BREAK_EVEN_EVALUATED`, `BRE_EVENT_BREAK_EVEN_CANDIDATE_AVAILABLE`, `BRE_EVENT_BREAK_EVEN_CANDIDATE_BLOCKED`, or `BRE_EVENT_BREAK_EVEN_STOP_PRICE_INVALID` according to planner status and existing quote-sequence dedupe policy.
- `DUE` does **not** set `breakEvenActive`, disable recovery, lock the basket, or mutate persistence.
- Stale quote or pending execution produces blocked audit only; duplicate quote sequence dedupes to `NOT_REACHED`.

### Execution remains disabled

- BE candidate planning does **not** append `CStrategyDecisionSet` entries for break-even.
- `StrategyDecisionCommandMapper`, execution request factories, manual submission services, and `Mt5AsyncSubmissionGateway` are untouched.
- A generated candidate still does **not** modify stop-loss on the broker; automated break-even execution remains intentionally disabled for a future sprint.

### Runtime tests

`TestBreakEvenCandidateRuntimeWiring.mq5` covers runtime DUE + audit emit, quote-sequence dedupe, stale quote / pending execution blocked audits, and confirms no mapper or `CTradeExecutionRequest` execution path is introduced by wiring.

## Compile Notes

`TestBreakEvenCandidateRuntimeWiring.mq5` initially referenced a non-existent include path (`Infrastructure/Queue/InMemoryCommandQueue.mqh`). The correct path is `Infrastructure/Commands/InMemoryCommandQueue.mqh` (same as other runtime wiring tests such as `TestStrategyCommandWiring.mq5`). That typo produced 25 MetaEditor compile **errors** (miscounted as warnings in an intermediate gate summary), all resolved in Sprint 9A.1 finalization.

After the include fix, `TestBreakEvenCandidateRuntimeWiring.mq5` compiles with **0 errors and 0 warnings**. No baseline compiler warnings required suppression for this sprint.
