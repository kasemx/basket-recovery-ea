# Sprint R-3 — Strategy Profile Basket Integration

## Scope delivered

- Immutable strategy profile binding on basket creation
- Generic profit level runtime progress (orthogonal to lifecycle)
- Persistence schema v3 with v1/v2 → v3 migration
- Generic strategy events and commands (no broker execution)
- `StrategyDecisionCommandMapper` and `EvaluateBasketStrategyUseCase`
- Transition rule refactor (no TP1/TP2/TP3 lifecycle dependency)
- Runtime guards for stale version, hash mismatch, duplicate profit level / BE

## Out of scope (unchanged)

- Trade Execution Engine
- OrderSend / OrderModify / PositionClose
- Live risk, recovery open, partial close
- REST API changes

## Lifecycle model

| State | Meaning |
|-------|---------|
| `PENDING_OPEN` | Basket created, awaiting initial positions |
| `WAIT_DETAILS` | Positions opened, awaiting signal details |
| `ACTIVE` | Basket running with details |
| `SUSPENDED` | Max risk lockout |
| `CLOSING` | Close in progress |
| `FINISHED` | Terminal success |
| `ERROR` | Terminal failure |

Legacy persisted states `TP1`, `BREAK_EVEN`, `TP2`, `TP3` migrate to `ACTIVE` with mode/progress flags inferred where possible.

## Mode flags

| Flag | Purpose |
|------|---------|
| `recoveryActive` | Recovery algorithm enabled |
| `recoveryPermanentlyDisabled` | Recovery disabled for basket lifetime |
| `breakEvenActive` | Break-even rule applied (not a lifecycle state) |
| `trailingActive` | Trailing behavior active |
| `locked` | Basket locked against new actions |
| `riskReductionActive` | Risk reduction in progress |
| `maxRiskLockout` | Max risk threshold reached |

## Persistence v3

Key fields:

- `has_strategy_snapshot`, `strategy_migration_required`
- `strategy_id`, `strategy_schema_version`, `strategy_profile_hash`
- `strategy_canonical_json`, `strategy_bound_at_utc`
- `profit_level_*` parallel arrays
- `executed_break_even_rule_ids`
- Extended mode booleans

Migration never attaches a changed live JSON profile to historical baskets; legacy baskets without snapshot are marked `strategy_migration_required=true`.

## Tests

- `TestBasketStrategyIntegration.mq5` — binding, immutability, migration, profit levels, BE mode, guards, mapper idempotency
- `TestTransitionRules.mq5` — updated for generic lifecycle

Run in MetaEditor against MT5 terminal with golden strategy files under `MQL5/Files/Common/BasketRecovery/`.
