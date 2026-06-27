# Sprint R-3.1 — Strategy Command Wiring & Controlled Migration

## Scope

Strategy command registration, persistence round-trip, scheduler integration, controlled migration, and stub execution-intent handlers. **No Trade Executor, broker API, or live risk calculations.**

## Handler Registration Map

### Commands (priority)

| Priority | Handler | Command type |
|---------:|---------|--------------|
| 10 | `CCreateBasketCommandHandler` | `BRE_COMMAND_CREATE_BASKET` |
| 20 | `CActivateBasketCommandHandler` | `BRE_COMMAND_ACTIVATE_BASKET` |
| 30 | `CCloseBasketCommandHandler` | `BRE_COMMAND_CLOSE_BASKET` |
| 40 | `CEvaluateStrategyCommandHandler` | `BRE_COMMAND_EVALUATE_STRATEGY` |
| 50 | `COpenRecoveryPositionCommandHandler` | `BRE_COMMAND_OPEN_RECOVERY_POSITION` |
| 50 | `CClosePositionsCommandHandler` | `BRE_COMMAND_CLOSE_POSITIONS` |
| 50 | `CMoveBasketStopLossCommandHandler` | `BRE_COMMAND_MOVE_BASKET_STOP_LOSS` |
| 50 | `CReduceBasketRiskCommandHandler` | `BRE_COMMAND_REDUCE_BASKET_RISK` |
| 60 | `CDisableRecoveryCommandHandler` | `BRE_COMMAND_DISABLE_RECOVERY` |
| 60 | `CMarkProfitLevelCompletedCommandHandler` | `BRE_COMMAND_MARK_PROFIT_LEVEL_COMPLETED` |

Execution-intent handlers (priority 50) validate version/hash/idempotency, append audit, emit `BRE_EVENT_EXECUTION_PENDING`, and **never** call broker APIs or mutate position state.

### Events (priority 30)

| Handler | Event type |
|---------|------------|
| `CStrategyProfileBoundEventHandler` | `BRE_EVENT_STRATEGY_PROFILE_BOUND` |
| `CProfitLevelReachedEventHandler` | `BRE_EVENT_PROFIT_LEVEL_REACHED` |
| `CProfitLevelCloseRequestedEventHandler` | `BRE_EVENT_PROFIT_LEVEL_CLOSE_REQUESTED` |
| `CProfitLevelCloseCompletedEventHandler` | `BRE_EVENT_PROFIT_LEVEL_CLOSE_COMPLETED` |
| `CBreakEvenActivatedEventHandler` | `BRE_EVENT_BREAK_EVEN_ACTIVATED` |
| `CRecoveryDisabledEventHandler` | `BRE_EVENT_RECOVERY_DISABLED` |
| `CRiskReductionRequestedEventHandler` | `BRE_EVENT_RISK_REDUCTION_REQUESTED` |
| `CBasketLockedEventHandler` | `BRE_EVENT_BASKET_LOCKED` |

Registration is centralized in `CKernelHandlerRegistration` and wired from `CApplicationKernel`.

## Evaluate Strategy Flow

1. Load basket from repository
2. Reject `strategy_migration_required` / stale version / hash mismatch (`CBasketRuntimeGuard`)
3. Build market + risk context via `IMarketContextProvider` (missing quote → safe defer / fail)
4. `IStrategyEngine.EvaluateAll` → `CStrategyDecisionCommandMapper`
5. Enqueue mapped commands (not executed in same handler)
6. Append evaluation audit + save basket

## Command Persistence

`CCommandSerializer` delegates strategy payloads to `CCommandSerializerStrategy`.

Round-trip fields for all seven strategy commands:

- `basket_id`, `expected_basket_version`, `strategy_profile_hash`
- `idempotency_key`, `correlation_key`
- Command-specific payload (step index, level id, close percent, rule id, etc.)

Queue recovery uses `CPersistentCommandQueue` + `CFileCommandPersistence` (same path as existing command persistence).

## Controlled Migration

`CBindMigratedBasketStrategyUseCase`:

- Requires `strategy_migration_required == true`
- Requires explicit canonical JSON + parsed `CStrategyProfile` (never silent current-file bind)
- Rejects already-bound baskets
- Creates immutable snapshot/hash via `CStrategyProfileCanonicalSerializer`
- Saves basket and emits `BRE_EVENT_STRATEGY_PROFILE_BOUND`

## Scheduler Integration

`CApplicationContext.OnApplicationTimer` → `CApplicationTimerPipeline.OnTimer`:

1. REST command ingestion (if poll interval due)
2. `CCommandProcessor.RunCycle`
3. `CPersistenceManager.FlushIfDue`
4. `CStrategyEvaluationScheduler.RunIfDue`

Constraints:

- `OnTick` is empty (no network/persistence)
- Evaluation only for `BRE_STATE_ACTIVE` baskets with bound strategy and no migration flag
- Configurable interval (`strategyEvalIntervalMs`) and cap (`maxBasketsPerEvalCycle`)
- Loop limit suspends affected basket via `CommandProcessor.LastProcessedBasketId`

## Bootstrap / EA

- Single command queue: `CPersistenceManager.CommandQueue()` shared by REST ingestion and kernel
- `BasketRecoveryEA.mq5`: millisecond application timer, new inputs for timer/eval tuning
- `CEAConfiguration`: `applicationTimerIntervalMs`, `strategyEvalIntervalMs`, `maxBasketsPerEvalCycle`

## Tests

`TestStrategyCommandWiring.mq5` covers:

- Evaluate dispatch + version bump
- Stale version / hash mismatch / migration-required rejection
- Controlled migration success
- Duplicate profit level / break-even event rejection
- Serialization round-trip (7 commands)
- Restart recovery (7 pending commands)
- Execution stub → `EXECUTION_PENDING` only
- Active-only scheduler
- Timer pipeline ordering (processor before scheduler)

## Remaining Work (before Trade Execution Engine)

1. Trade Execution Engine (OrderSend, OrderModify, PositionClose)
2. Wire `BRE_EVENT_EXECUTION_PENDING` to executor pipeline
3. Live position snapshot + MT5 market provider (replace in-memory stub)
4. Recovery / partial-close execution handlers (replace stubs)
5. Live risk calculation integration
6. REST ingestion mapping for new strategy command types
7. End-to-end EA smoke test on demo account
