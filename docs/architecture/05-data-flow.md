# 5. Veri Akışı

> **Revizyon v2:** Command Queue + Event Bus + Trade Request Queue + Position Snapshot merkezli akış.

## 5.1 End-to-End Flow (v2)

```
Telegram → Python → PostgreSQL → REST Adapter
                                      ↓
                               Command Queue (persisted, idempotent)
                                      ↓
                               Command Handler
                                      ↓
                          ┌───────────┴───────────┐
                          ↓                       ↓
                    Domain Events           Trade Request Queue
                          ↓                       ↓
                    Event Handlers            Trade Executor
                          ↓                       ↓
                    TransitionEngine         Snapshot Store
                          ↓                       ↓
                    Persistence              Risk Engine (reads snapshot)
```

---

## 5.2 Signal #1 → CreateBasketCommand

```
REST GET /commands/pending
    → CreateBasketCommand { idempotencyKey: "create:sig_001" }
    → CommandQueue.enqueue()

CommandProcessor:
    → CreateBasketCommandHandler
        → bind ProfileSnapshot to new Basket
        → TradeRequestQueue.enqueue(OpenMarketRequest × 3)
        → publish(BasketCreated)

TradeExecutor.processBatch():
    → OrderSend × 3 (ONLY here)
    → SnapshotStore.applyTransaction × 3
    → publish(InitialPositionsOpened × 3 or batch)

TransitionEngine:
    InitialPositionsOpened → WAIT_DETAILS

PersistenceHandler subscribes StateTransitioned → save
```

---

## 5.3 Signal #2 → ActivateBasketCommand

```
ActivateBasketCommand { basketId, sl, tp1-4, ... }
    → ActivateBasketCommandHandler
        → TradeRequestQueue.enqueue(ModifyStopLossRequest × N)
        → TradeRequestQueue.enqueue(ModifyTakeProfitRequest × N)
        → publish(BasketActivated)

TransitionEngine: WAIT_DETAILS → ACTIVE

RiskEvaluationHandler subscribes BasketActivated:
    → snapshot = store.get(basketId)
    → RiskCalculator.calculate(snapshot, ...)
    → publish(RiskSnapshotCalculated)
```

---

## 5.4 Recovery Flow (Event-Driven)

```
PriceThresholdMonitor:
    adverse step crossed → publish(RecoveryStepCrossed)

RecoveryEvaluationHandler subscribes:
    → RecoveryEvaluator.shouldTrigger(snapshot, price, profile)
    → IF ok: enqueue(OpenRecoveryPositionCommand)

OpenRecoveryCommandHandler:
    → RiskCalculator.projectRiskAfterRecovery(snapshot, ...)
    → IF within max: TradeRequestQueue.enqueue(OpenMarketRequest)
    → ELSE: publish(RecoveryBlocked)

TradeExecutor fills → publish(RecoveryPositionOpened)
RiskEvaluationHandler → updated risk events
```

---

## 5.5 Risk Reduction Flow

```
RiskEvaluationHandler:
    risk > target → publish(TargetRiskReached)

RiskReductionHandler subscribes (if price favorable):
    → enqueue(ReduceRiskCloseCommand)

ReduceRiskCommandHandler:
    → RiskReductionPlanner.plan(snapshot, target)
    → TradeRequestQueue.enqueue(ClosePositionRequest)

TradeExecutor → publish(PositionClosed)
RiskEvaluationHandler → risk recalc → maybe publish(RiskReduced)
```

---

## 5.6 TP1 + Break-Even Flow

```
PriceThresholdMonitor: publish(TP1Reached)

TP1Handler subscribes:
    → enqueue(ExecuteTPPartialCloseCommand { level: TP1, fraction: profile.tp1 })

TPPartialCloseCommandHandler:
    → TakeProfitPlanner.plan(snapshot, fraction)
    → TradeRequestQueue.enqueue(ClosePositionRequest × N)
    → publish(TP1PartialCloseCompleted)

TransitionEngine: ACTIVE → TP1

RiskEvaluationHandler monitors realized:
    → publish(BreakEvenEligible) when threshold met

BEHandler subscribes BreakEvenEligible:
    → enqueue(ActivateBreakEvenCommand)
    → ModifyStopLossRequest × all (all synced guard)
    → publish(BreakEvenActivated)
    → publish(RecoveryPermanentlyDisabled)

TransitionEngine: TP1 → BREAK_EVEN
```

---

## 5.7 Configuration Profile Binding

```
CreateBasketCommandHandler:
    profile = profileLoader.resolveForSymbol(symbol)
    basket.profileSnapshot = profile.snapshot()   // immutable

All engines read basket.profileSnapshot.risk / .recovery / .takeProfit
NOT global config — per-basket frozen params
```

---

## 5.8 Backtest Data Flow

```
HistoricalCommandSource.fetchPending()
    → same Command objects, timestamp-filtered

SimulatedTradeExecutor.processNext()
    → fillModel.simulate() — NO OrderSend
    → SnapshotStore.applyTransaction()
    → same EventBus events

RiskEngine, TransitionEngine, TP/Recovery handlers — IDENTICAL code path
```

---

## 5.9 Persistence Touchpoints

| Trigger Event | Persist |
|---------------|---------|
| Command enqueued | commands/pending.json |
| Command completed | commands/completed.jsonl |
| TradeRequest enqueued | trade_requests/queued.json |
| PositionSnapshotUpdated | snapshots/ (debounced) |
| StateTransitioned | basket state JSON |
| BasketFinished | archive + cleanup |

---

## 5.10 Yasak Veri Akışları (v2)

```
❌ REST fetch → direct handler call (bypass queue)
❌ Event handler → OrderSend (bypass TradeExecutor)
❌ Risk Engine → PositionsTotal() broker scan
❌ Module A → Module B direct method call (bypass EventBus)
❌ Active basket ← live profile hot-reload
```
