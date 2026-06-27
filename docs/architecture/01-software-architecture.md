# 1. Yazılım Mimarisi

> **Revizyon v2:** Command Queue, Event Bus, Trade Executor, Position Snapshot, Configuration Profiles, Backtesting Adapter eklendi.

## 1.1 Mimari Stil

**Hexagonal Architecture + Event-Driven Command Processing + Clean Architecture**

```
┌─────────────────────────────────────────────────────────────────┐
│                     Interfaces (Driving)                         │
│  ExpertAdvisor.mq5 · OnTick · OnTimer · OnTradeTransaction      │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                   Application Kernel                               │
│  CommandProcessor · EventBus · TransitionEngine                   │
│  Command Handlers · Event Handlers · PriceThresholdMonitor         │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                        Domain Layer                                │
│  Entities · TransitionRuleRegistry · Domain Services             │
│  (MT5, HTTP, OrderSend YOK)                                       │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│              Infrastructure (Driven Adapters)                      │
│  RestCommandSource · Mt5TradeExecutor · FilePersistence            │
│  PositionSnapshotStore · ProfileLoader · SimulatedExecutor         │
└───────────────────────────────────────────────────────────────────┘
```

### v2 Merkezi Akış

```
REST (transport) → Command Queue → Handler → Trade Request Queue → Trade Executor
                      ↓                              ↓
                 Event Bus ←────────────────── Snapshot Store
                      ↓
              Event Handlers → (enqueue new commands)
                      ↓
              TransitionEngine (explicit rules)
                      ↓
              Risk Engine (reads snapshot ONLY)
```

## 1.2 SOLID Uygulaması (v2)

| Prensip | v2 Uygulama |
|---------|-------------|
| **S** | Command handler = tek command tipi; Event handler = tek event tipi |
| **O** | Yeni command/event → yeni handler register; domain değişmez |
| **L** | `IExecutionEnvironment` live/backtest değiştirilebilir |
| **I** | `ICommandQueue`, `ITradeRequestQueue`, `IPositionSnapshotStore`, `IEventBus` ayrı |
| **D** | Domain → port'lar; adapter'lar implement eder |

## 1.3 Bounded Contexts

```
┌──────────────────────┐         ┌──────────────────────────────────┐
│  Signal Ingestion    │         │  Basket Recovery Engine (MT5)     │
│  (Python)            │         │                                   │
│  Telegram → Parser   │  REST   │  Command Queue                    │
│  → PostgreSQL        │───────►│  Event Bus                        │
│  → Command DTO       │         │  Trade Executor (sole broker API)  │
└──────────────────────┘         │  Position Snapshot                │
                                 │  Transition Engine                │
                                 └──────────────────────────────────┘
```

## 1.4 v2 Mimari Kararlar

### Karar 1: Command Queue (Polling değil)

| | v1 | v2 |
|---|-----|-----|
| Merkez | REST poll → use case | REST → enqueue Command → process |
| Idempotency | Trade command UUID | Command IdempotencyKey + TradeRequest key |
| Audit | Partial | Full command log |

Polling **transport adapter** olarak kalır; iş hattı command-centric. Bkz. doc 18.

### Karar 2: Event Bus (Direct call değil)

Modüller birbirini **doğrudan çağırmaz**. Command handler event publish eder; subscriber handler'lar react eder. Bkz. doc 19.

### Karar 3: Explicit Transition Rules

State class `handle()` yerine deklaratif rule table. Bkz. doc 20.

### Karar 4: Trade Executor Singleton Boundary

Yalnızca `Mt5TradeExecutor` → OrderSend/Modify/Close. Bkz. doc 21.

### Karar 5: Position Snapshot

Risk Engine → `IPositionSnapshotStore.get()`. Broker scan yasak (restart reconcile hariç). Bkz. doc 22.

### Karar 6: Configuration Profiles

Risk/recovery/TP → JSON profiles. Basket'e immutable snapshot bind. Bkz. doc 23.

### Karar 7: Backtesting First-Class

`IExecutionEnvironment` port — live ve backtest aynı kernel. Bkz. doc 24.

## 1.5 IExecutionEnvironment (Composition Root)

```
IExecutionEnvironment {
    getCommandSource() → ICommandSource
    getCommandQueue() → ICommandQueue
    getEventBus() → IEventBus
    getTradeRequestQueue() → ITradeRequestQueue
    getTradeExecutor() → ITradeExecutor
    getSnapshotStore() → IPositionSnapshotStore
    getTransitionEngine() → TransitionEngine
    getProfileLoader() → IConfigurationProfileLoader
    getClock() → IClock
    getPriceFeed() → IPriceFeed
}
```

Bootstrapper:
```
Bootstrapper.bootstrap(ExecutionMode mode):
    env = createEnvironment(mode)   // LIVE | BACKTEST | PAPER
    registerCommandHandlers(env)
    registerEventHandlers(env)
    loadTransitionRules(env)
    validateProfiles(env)
    return ApplicationKernel(env)
```

## 1.6 Two-Phase Processing Loop

Reentrancy önleme (doc 25):

```
OnTimer(fast):   // 100ms
    Phase 1: commandProcessor.processBatch(N)
    Phase 2: eventBus.drainQueue()
    Phase 3: tradeExecutor.processBatch(M)

OnTimer(slow):   // 3s
    restAdapter.fetchAndEnqueueCommands()
```

## 1.7 Cross-Cutting Concerns (v2)

| Concern | v2 Yaklaşım |
|---------|-------------|
| Idempotency | Command + TradeRequest IdempotencyKey + IdempotencyStore |
| Config | Configuration Profiles (doc 23) |
| Logging | Structured + domain event correlation |
| Error | Result<T,E>; dead letter queue for commands |
| Concurrency | Single-threaded two-phase loop |
| Time | IClock — live/backtest |

## 1.8 Test Stratejisi (v2)

```
L1  Domain pure functions + transition rule table tests
L2  Command handler + event handler (InMemory env)
L3  Backtest replay (SimulatedTradeExecutor)
L4  MT5 demo (Live environment)
L5  E2E Telegram pipeline
```

## 1.9 Performans Hedefleri (v2)

| Metrik | Hedef |
|--------|-------|
| OnTick | < 0.5ms (price cache + threshold check) |
| Command batch | < 10ms (trade hariç) |
| REST fetch | Ayrı timer; command loop'u bloke etmez |
| Risk eval | Snapshot read O(n); debounced except thresholds |
| Broker API | Yalnızca TradeExecutor + restart reconcile |

## 1.10 Güvenlik

- API key + account binding
- Command schema validation
- TradeExecutor grep CI rule
- Profile files — no secrets
- IdempotencyStore replay protection

## 1.11 İlgili Belgeler

| Konu | Belge |
|------|-------|
| Command Queue | 18-command-queue.md |
| Event Bus | 19-event-bus.md |
| Transition Rules | 20-transition-rules.md |
| Trade Executor | 21-trade-executor.md |
| Position Snapshot | 22-position-snapshot.md |
| Config Profiles | 23-configuration-profiles.md |
| Backtesting | 24-backtesting-adapter.md |
| Remaining weaknesses | 25-architecture-review-v2.md |
