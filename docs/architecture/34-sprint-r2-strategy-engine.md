# 34. Sprint R-2 — Strategy Engine Pure Evaluator

> **Kapsam:** Pure domain evaluator — karar üretir, execute etmez.

## 34.1 Klasör Ağacı

```
Application/Ports/IStrategyEngine.mqh

Domain/Strategy/
├── Context/
│   ├── StrategyEvaluationContext.mqh
│   ├── MarketContext.mqh
│   ├── BasketStrategyState.mqh
│   ├── ProfitLevelRuntimeState.mqh
│   ├── RiskRuntimeContext.mqh
│   └── PositionRuntimeView.mqh
├── Decisions/
│   ├── StrategyDecision.mqh
│   ├── StrategyDecisionSet.mqh
│   ├── OpenRecoveryPositionDecision.mqh
│   ├── ClosePositionsDecision.mqh
│   ├── MoveBreakEvenDecision.mqh
│   ├── DisableRecoveryDecision.mqh
│   ├── ReduceRiskDecision.mqh
│   └── NoActionDecision.mqh
├── Enums/StrategyDecisionType.mqh
└── Services/
    ├── StrategyEngine.mqh
    ├── ExecutionZoneResolver.mqh
    ├── RecoveryPlanResolver.mqh
    ├── ProfitDistributionEvaluator.mqh
    ├── BreakEvenEvaluator.mqh
    ├── RiskReductionEvaluator.mqh
    └── CloseOrderingResolver.mqh
```

## 34.2 Decision Model

| Type | Payload |
|------|---------|
| OPEN_RECOVERY | stepIndex, distancePips, lot, expectedEntryPrice, tradeRole, idempotencyKey |
| CLOSE_POSITIONS | levelId, closePercent, closeMode, tickets[], partialClose |
| MOVE_BREAK_EVEN | ruleId, bufferPips / slOffset |
| DISABLE_RECOVERY | ruleId, permanent |
| REDUCE_RISK | reductionMode, tickets[] |
| NO_ACTION | reason (unsupported action warning) |

`CStrategyDecisionSet` dedupe by `idempotencyKey`.

## 34.3 Evaluator Flow

```
EvaluateAll(context):
  1. RiskReductionEvaluator   → currentRiskPct > targetRiskPct
  2. Recovery (StrategyEngine) → zone + adverse move + risk gate
  3. ProfitDistributionEvaluator → reached enabled levels
  4. BreakEvenEvaluator       → trigger/action rules
  → Merge + dedupe
```

## 34.4 Test Senaryoları

| Script | Kapsam |
|--------|--------|
| TestExecutionZoneResolver | SELL +2 above, BUY +2 below |
| TestRecoveryPlanResolver | CUSTOM, CONSTANT, LINEAR, PROGRESSIVE, ATR unsupported |
| TestProfitDistributionEvaluator | 20/30/50 custom levels |
| TestBreakEvenEvaluator | L1 trigger, realized profit |
| TestRiskReductionEvaluator | worst entry reduction |
| TestStrategyEngineGoldenBehavior | golden recovery, dedupe, BE disable, L1 close |

## 34.5 Derleme

MetaEditor ile test scriptleri derlenmeli.

## 34.6 R-3 Kalan İş

- Basket.BindStrategyProfile
- Event handlers → IStrategyEngine → Command enqueue
- Persistence v3
- TransitionRuleRegistry generic events

## 34.7 Quality Report

| Metrik | Değer |
|--------|-------|
| Yeni dosyalar | ~25 |
| LOC (approx.) | ~2,200 |
| Broker/REST/Persistence | Dokunulmadı |
| Sınıf boyutu | ≤300 satır |
