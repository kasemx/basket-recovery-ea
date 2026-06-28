# Sprint 7A — Live Basket Risk Engine and Projected SL Risk

**Baseline:** commit `329dcd73b0a47fab6c77e28e03cbd6ab75de5ca7`, tag `v0.6.6-manual-demo-ordersendasync-submission`
**Status:** Implemented — read-only risk engine; **no execution** in this sprint

## Scope

Sprint 7A adds a broker-accurate, snapshot-based basket risk engine that computes:

- Current floating basket PnL
- Weighted average entry
- Current SL-based loss exposure
- Projected SL risk after a proposed OPEN_POSITION
- Target vs max risk compliance
- Deterministic risk-reduction plans

The engine **does not** open, close, modify, or submit trades. Strategy, REST, OnTick, OnTimer, and OnTradeTransaction paths remain unable to initiate submission.

## Core types

| Type | Purpose |
|------|---------|
| `CBasketRiskSnapshot` | Basket-level risk state |
| `CPositionRiskSnapshot` | Per-position SL risk |
| `CProjectedBasketRisk` | Current + proposed combined risk |
| `CRiskLimitProfile` | Immutable target/max limits + reduction policy |
| `CRiskValidationResult` | Allowed/rejected gate output |
| `ENUM_BRE_RISK_VIOLATION_REASON` | Deterministic rejection reasons |
| `CRiskReductionPlan` | Pure planner output (no broker calls) |
| `CRiskCalculationContext` | Account, quote, profile, basket SL, settings |

Location: `mt5/Include/BasketRecovery/Domain/Risk/`

## Formulas and broker assumptions

All calculations use broker symbol properties from `CMarketQuote`:

- `TickSize()` — `SYMBOL_TRADE_TICK_SIZE`
- `TickValue()` — `SYMBOL_TRADE_TICK_VALUE`
- `Point()`, `Constraints().VolumeMin/Max/Step`

### Per-position worst-case loss at SL

```
distance = |entryPrice - effectiveStopLoss| + spreadBufferPrice
ticks    = distance / tickSize
loss     = ticks * tickValue * volume
         + |commission|            (if enabled)
         + |swap|                    (if enabled and swap < 0)
```

**Effective SL** = basket shared SL (`CSignalDetails::StopLoss()`), not per-position broker SL overrides.

### Basket aggregates

```
currentSlRiskMoney = Σ position.worstCaseLossAtSl
floatingProfit     = Σ position.floatingProfit
weightedAvgEntry   = Σ(entry * volume) / Σ(volume)
```

### Limits (from immutable profile — no hardcoded 1% / 1.2%)

```
targetRiskMoney = PERCENT_EQUITY → equity * value / 100
                | MONEY          → value
maxRiskMoney    = same resolution
utilization     = currentSlRiskMoney / maxRiskMoney
headroom        = maxRiskMoney - currentSlRiskMoney
```

### Projected risk

```
proposedLoss      = SL risk of proposed OPEN_POSITION at ask/bid entry
projectedSlRisk   = currentSlRiskMoney + proposedLoss
```

Hard gate: `projectedSlRisk > maxRiskMoney` → reject (`PROJECTED_EXCEEDS_MAX`).

## Target vs max behavior

| Limit | Role |
|-------|------|
| **Target risk** | Advisory soft limit; triggers risk-reduction planner when current SL risk exceeds target |
| **Max risk** | Hard gate for projected recovery/open validation |

Missing SL, invalid tick value, or unavailable cross-currency conversion → **UNKNOWN/UNSAFE** (never treated as zero risk).

## Missing-SL policy

- `basketStopLoss <= 0` → position/basket risk **UNKNOWN**
- Basket with any unknown position → **UNSAFE**
- No recovery projection eligibility when current basket risk is unknown

## Projected-risk flow

```
PositionSnapshot (read-only)
  → CBasketRiskCalculator → CBasketRiskSnapshot
  → CProjectedRiskCalculator (+ proposed OPEN_POSITION request)
  → CProposedPositionRiskValidator
       → allowed / rejected + CRiskReductionPlan (advisory)
```

Integration (read-only, no blocking this sprint):

- `CMarketContextProviderAdapter` — real `CRiskRuntimeContext` from snapshots
- `CStrategyEvaluationContextFactory::TryCalculateBasketRisk`
- `CExecutionSubmissionPreparer::EvaluateRiskReadOnly`
- `CDemoManualSubmissionValidationService::LastReadOnlyRiskValidation`

## Risk-reduction planner

Pure domain planner (`CRiskReductionPlanner`):

- Trigger: `ABOVE_TARGET_RISK` when `currentSlRiskMoney > targetRiskMoney`
- Close order: `WORST_ENTRY_FIRST` (BUY → highest entry first; SELL → lowest entry first)
- Output: tickets, requested volumes (step/min normalized), estimated risk reduction
- **No broker calls, no partial-close execution**

### Example

```
Equity=10,000 | Target=100 USD | Max=120 USD
Current SL risk=135 USD (two BUY positions)
→ Plan closes worst-entry ticket first until estimated reduction ≥ 35 USD
```

## Known limitations

- Account currency conversion not implemented; `RequireCrossCurrencyConversion` marks risk UNKNOWN when required but unavailable
- `SYMBOL_TRADE_CONTRACT_SIZE` not used; tick size/value formula is authoritative
- Cross-symbol baskets not supported (single symbol per basket assumed)
- Risk-reduction planner estimates reduction proportionally; does not simulate post-close basket SL recalculation

## Explicit non-goals (this sprint)

- No `OrderSend` / `OrderSendAsync` additions
- No `PositionClose` / `PositionModify` / `CTrade`
- No automatic trading, auto-close, or recovery order generation
- No strategy decision changes unless future wiring explicitly consumes `CRiskValidationResult`

## Tests

`mt5/Scripts/BasketRecovery/Tests/TestLiveBasketRiskEngine.mq5` covers:

- BUY/SELL SL risk, multi-position basket, weighted average entry
- Commission/swap inclusion, missing SL, invalid tick value
- Target percent equity, max money limits
- Projected risk exceeds max, risk-reduction plan worst-entry-first
- Volume step normalization, immutable profile binding
