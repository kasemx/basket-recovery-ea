# 24. Backtesting Adapter

> **Revizyon:** v2 — Backtesting birinci sınıf mimari concern. Trading logic MT5'e bağımlı değil.

## 24.1 Tasarım Prensibi

Domain ve application katmanları **execution environment abstraction** üzerinden çalışır:

```
IExecutionEnvironment
    ├── ICommandSource          (REST poll vs historical replay)
    ├── ITradeExecutor          (Mt5TradeExecutor vs SimulatedTradeExecutor)
    ├── IPositionSnapshotStore  (same interface, in-memory or persisted)
    ├── IClock                  (live vs simulated bar time)
    ├── IPriceFeed              (live tick vs historical OHLC/tick)
    ├── IAccountSnapshotReader  (live equity vs simulated)
    └── IConfigurationProfileLoader
```

Live MT5 ve Backtest **aynı CommandProcessor + EventBus + TransitionEngine + RiskCalculator** pipeline'ını paylaşır.

---

## 24.2 Execution Environment Implementations

| Bileşen | Live (MT5) | Backtest |
|---------|------------|----------|
| Command Source | RestCommandSourceAdapter | HistoricalCommandSource |
| Trade Executor | Mt5TradeExecutor | SimulatedTradeExecutor |
| Snapshot Store | FileBackedSnapshotStore | InMemorySnapshotStore |
| Clock | Mt5Clock | SimulatedClock |
| Price Feed | Mt5TickFeed | HistoricalBarFeed / TickReplayFeed |
| Account Reader | Mt5AccountReader | SimulatedAccountReader |
| Event Bus | InMemoryEventBus | InMemoryEventBus (same) |

---

## 24.3 ICommandSource Port

```
ICommandSource {
    fetchPending() → list<Command>
    acknowledge(commandId) → Result
}

RestCommandSourceAdapter:
    REST GET → map to commands → return

HistoricalCommandSource:
    load commands from CSV/JSON timeline
    fetchPending() → commands WHERE timestamp <= clock.now()
    // simulates signal arrival at historical times
```

---

## 24.4 IPriceFeed Port

```
IPriceFeed {
    subscribe(symbol, callback)
    getCurrentPrice(symbol) → PricePair { bid, ask }
    advance() → bool          // backtest: next bar/tick
    isEndOfData() → bool
}

HistoricalBarFeed:
    load OHLC CSV / MT5 export
    advance bar-by-bar
    generate synthetic bid/ask from OHLC + spread config
```

---

## 24.5 SimulatedTradeExecutor

```
SimulatedTradeExecutor implements ITradeExecutor {
    -IFillModel fillModel
    -ISlippageModel slippageModel
    
    executeOpen(request, currentPrice):
        fillPrice = fillModel.getFillPrice(request, currentPrice)
        slippage = slippageModel.apply(request, fillPrice)
        transaction = NormalizedTransaction(OPEN, ...)
        snapshotStore.applyTransaction(transaction)
        eventBus.publish(...)
        // NO OrderSend
}
```

### Fill Models (Pluggable)

| Model | Davranış |
|-------|----------|
| `InstantFillModel` | Anında, sıfır slippage |
| `BarOpenFillModel` | Sonraki bar open'da fill |
| `RealisticSlippageModel` | Config spread + slippage |
| `WorstCaseFillModel` | Stress test |

---

## 24.6 SimulatedAccountReader

```
SimulatedAccountReader {
    equity = balance + sum(floating from snapshots)
    
    onPositionClosed(realized):
        balance += realized
        equity recalculate
}
```

Margin simulation (optional Phase 2): reject opens when insufficient margin.

---

## 24.7 Backtest Runner

```
BacktestRunner {
    -IExecutionEnvironment env
    -CommandProcessor processor
    -TradeExecutor executor
    
    run(historicalData, commandTimeline, profile):
        env.clock.set(startTime)
        
        WHILE NOT env.priceFeed.isEndOfData():
            env.priceFeed.advance()
            env.clock.tick()
            
            // 1. Inject commands at scheduled times
            commands = env.commandSource.fetchPending()
            FOR cmd in commands: commandQueue.enqueue(cmd)
            
            // 2. Process commands
            processor.processBatch()
            
            // 3. Process trade requests
            executor.processBatch()
            
            // 4. Update floating P&L on snapshots
            priceFeedHandler.onTick()
            
            // 5. Price monitors (TP, recovery step)
            priceMonitorHandler.evaluate()
        
        RETURN BacktestReport
}
```

---

## 24.8 Backtest Report

```
BacktestReport {
    int totalBaskets
    Money totalPnL
    int winCount, lossCount
    Money maxDrawdown
    list<BasketSummary> baskets
    list<DomainEvent> eventLog
    map<string, metric> customMetrics
}
```

---

## 24.9 Historical Command Timeline Format

```json
[
  {
    "timestamp": "2026-01-15T10:00:00Z",
    "command_type": "CreateBasketCommand",
    "payload": { "symbol": "XAUUSD", "direction": "SELL", "correlation_key": "..." }
  },
  {
    "timestamp": "2026-01-15T10:00:30Z",
    "command_type": "ActivateBasketCommand",
    "payload": { "basket_id": "...", "stop_loss": 4020, "tp1": 4012 }
  }
]
```

Python servisinden export veya Telegram geçmişinden türetilebilir.

---

## 24.10 MT5 Strategy Tester Entegrasyonu

İki mod:

| Mod | Açıklama |
|-----|----------|
| **A) Native Tester** | EA live adapter'larla tester'da — sınırlı (WebRequest mock) |
| **B) Offline Runner** | `BacktestRunner.mq5` script — tam control, önerilen |

Mod B tercih: domain logic aynı, MT5 tester kısıtlarından bağımsız.

---

## 24.11 Composition Root — Environment Switch

```
Bootstrapper.createEnvironment(mode):
    SWITCH mode:
        LIVE:
            return LiveExecutionEnvironment(...)
        BACKTEST:
            return BacktestExecutionEnvironment(...)
        PAPER:
            return LiveExecutionEnvironment(demoAccount, ...)

Bootstrapper.bootstrap(mode):
    env = createEnvironment(mode)
    wire(env)  // same wiring for all modes
    return ApplicationKernel(env)
```

EA input: `ExecutionMode = LIVE | BACKTEST | PAPER`

---

## 24.12 Test Pyramid (Updated)

```
Level 1: Domain unit tests        (no environment)
Level 2: Command + Event tests    (InMemory everything)
Level 3: Backtest replay tests    (HistoricalCommandSource + SimulatedExecutor)
Level 4: MT5 demo integration     (Live environment)
Level 5: E2E Telegram pipeline  (Full stack)
```

Level 3 backtest CI'da koşturulabilir — MT5 terminal gerekmez (pure MQL5 script veya future C++ port).

---

## 24.13 v1 "Future Extension" → v2 First-Class

Backtesting artık `16-future-extensions.md`'de opsiyonel değil — `IExecutionEnvironment` port'u Sprint 2-3'te tanımlanır, Sprint 4'te SimulatedTradeExecutor stub'lanır.
