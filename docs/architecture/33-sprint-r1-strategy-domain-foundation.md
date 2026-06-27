# 33. Sprint R-1 — Strategy Domain Foundation

> **Kapsam:** Strategy Profile domain model + JSON loader + migrator + tests. StrategyEngine yok.

## 33.1 Klasör Ağacı

```
mt5/Include/BasketRecovery/Domain/Strategy/
├── Aggregates/StrategyProfile.mqh
├── ValueObjects/
│   ├── ExecutionZone.mqh
│   ├── RecoveryPlan.mqh
│   ├── RecoveryStep.mqh
│   ├── ProfitDistributionPlan.mqh
│   ├── ProfitLevel.mqh
│   ├── BreakEvenPlan.mqh
│   ├── BreakEvenRule.mqh
│   ├── BreakEvenTrigger.mqh
│   ├── BreakEvenAction.mqh
│   ├── RiskPlan.mqh
│   └── StrategyMetadata.mqh
├── Enums/
│   ├── RecoveryAlgorithm.mqh
│   ├── CloseMode.mqh
│   ├── BreakEvenTriggerType.mqh
│   ├── BreakEvenActionType.mqh
│   └── ExecutionZoneExpansionMode.mqh
└── Validation/StrategyProfileValidator.mqh

mt5/Include/BasketRecovery/Infrastructure/Configuration/
├── StrategyProfileJsonLoader.mqh
├── StrategyProfileJsonParser.mqh
└── StrategyProfileMigrator.mqh

mt5/Files/BasketRecovery/strategies/
└── default-recovery-v1.strategy.json

mt5/Scripts/BasketRecovery/Tests/
├── TestStrategyProfileValidation.mq5
├── TestStrategyProfileJsonLoader.mq5
├── TestStrategyProfileMigrator.mq5
└── TestDefaultRecoveryGoldenProfile.mq5
```

## 33.2 JSON Schema Özeti (v2)

| Bölüm | Zorunlu | Ana alanlar |
|-------|---------|-------------|
| Root | ✓ | `schema_version: 2`, `strategy_id` |
| metadata | ✓ | `strategy_name`, `description`, `author` |
| execution_zone | ✓ | `source`, `expansion_mode`, `above/below_entry_pips` |
| recovery_plan | ✓ | `algorithm`, `steps[]` veya `constant_*` |
| risk_plan | ✓ | `target_risk_pct`, `max_risk_pct`, `risk_reduction_mode` |
| profit_distribution_plan | ✓ | `levels[]` (sınırsız) |
| break_even_plan | ✓ | `rules[]` trigger → actions |
| execution_policy | ✓ | `magic_number_base`, retry/slippage batch sizes |

## 33.3 Uygulanan Validation Kuralları

- `schemaVersion == 2`
- `maxRiskPct >= targetRiskPct`
- Execution zone source + fixed range low < high
- CUSTOM recovery: ≥1 step, strict index order, monotonic distance
- CONSTANT recovery: positive distance/lot/maxSteps
- ATR/VOLATILITY: rejected (R-2+)
- Profit level: unique `levelId`, closePercent 0–100, ≥1 enabled
- Break-even: unique ruleId, SPECIFIC_PROFIT_LEVEL → level must exist
- Execution policy magic > 0

## 33.4 Golden Profile

`default-recovery-v1.strategy.json` — legacy default davranışı:
- SIGNAL_RANGE + symmetric +3 pip expansion
- CUSTOM recovery 4 step (0.2→1.0 pip)
- Risk 1.0% / 1.2%
- Profit levels L1/L2/L3 (33/66/100%, SIGNAL_TP)
- BE_AFTER_L1 → MOVE_SL_TO_AVERAGE + DISABLE_RECOVERY

## 33.5 Test Senaryoları

| Script | Senaryolar |
|--------|------------|
| TestStrategyProfileValidation | valid, risk, duplicate level, close %, BE ref, empty CUSTOM, non-monotonic |
| TestStrategyProfileJsonLoader | JSON success, missing field, golden file load |
| TestStrategyProfileMigrator | v1 bundle → v2, semantic defaults |
| TestDefaultRecoveryGoldenProfile | Full golden semantic assertions |

## 33.6 Derleme Durumu

MetaEditor otomatik çalıştırılmadı. `TestStrategyProfileValidation.mq5` ile doğrulayın.

## 33.7 R-2 için Kalan İş

- StrategyEngine + evaluators/resolvers
- IStrategyEngine port
- LINEAR/PROGRESSIVE recovery validation + resolution
- ATR/VOLATILITY algorithm support
- Basket.BindStrategyProfile integration
- Persistence v3 migration

## 33.8 Quality Report

| Metrik | Değer |
|--------|-------|
| Yeni domain dosyaları | 18 |
| Infrastructure | 3 |
| Test scripts | 4 |
| LOC (approx.) | ~1,800 |
| Mimari ihlal | Yok — broker/trading yok |
| Sınıf boyutu | Tüm sınıflar <300 satır |
