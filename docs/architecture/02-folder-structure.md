# 2. Klasör Yapısı

> **Revizyon v2:** Application katmanı UseCase/Orchestrator yerine CommandHandlers + EventHandlers + Kernel. Infrastructure'a Backtest, Snapshot, Commands, Events eklendi. Detay: §2.7.

## 2.1 Monorepo Genel Yapı

```
basket-recovery-ea/
├── docs/
│   └── architecture/              # Bu belgeler
├── mt5/
│   ├── Experts/
│   │   └── BasketRecovery/
│   │       └── BasketRecoveryEA.mq5    # Composition root (~100 satır)
│   ├── Include/
│   │   └── BasketRecovery/
│   │       ├── Shared/                 # Ortak tipler, sabitler, Result
│   │       ├── Domain/
│   │       ├── Application/
│   │       ├── Infrastructure/
│   │       └── Interfaces/
│   └── Scripts/
│       └── BasketRecovery/
│           └── Tests/                  # Domain unit test scriptleri
├── python/
│   ├── signal_service/
│   │   ├── api/                        # FastAPI REST endpoints
│   │   ├── parser/                     # Telegram message parser
│   │   ├── repository/                 # PostgreSQL access
│   │   ├── models/                     # SQLAlchemy / Pydantic models
│   │   └── telegram/                   # Telegram listener
│   ├── migrations/                     # Alembic DB migrations
│   └── tests/
├── deploy/
│   ├── docker-compose.yml              # PostgreSQL + Python API
│   └── mt5/
│       └── allowed_urls.txt            # WebRequest whitelist dokümantasyonu
└── README.md
```

## 2.2 MT5 Include Detay Yapısı

```
Include/BasketRecovery/
│
├── Shared/
│   ├── Types/
│   │   ├── Result.mqh                  # Result<T,E> monad
│   │   ├── Money.mqh                   # Para birimi/value object
│   │   ├── Price.mqh                   # Fiyat + pip dönüşümleri
│   │   ├── LotSize.mqh
│   │   ├── Percentage.mqh
│   │   └── Identifiers.mqh             # BasketId, SignalId, CommandId UUID
│   ├── Constants/
│   │   ├── ErrorCodes.mqh
│   │   └── Defaults.mqh
│   └── Utils/
│       ├── JsonHelper.mqh              # Minimal JSON read/write
│       └── MathUtils.mqh
│
├── Domain/
│   ├── Entities/
│   │   ├── Basket.mqh
│   │   ├── BasketPosition.mqh
│   │   ├── TradingSignal.mqh
│   │   └── AccountSnapshot.mqh
│   ├── ValueObjects/
│   │   ├── SignalDetails.mqh           # SL, TP1-4, range
│   │   ├── RiskProfile.mqh             # target_risk, max_risk
│   │   ├── RecoveryConfig.mqh
│   │   ├── TakeProfitLevels.mqh
│   │   └── BreakEvenConfig.mqh
│   ├── Enums/
│   │   ├── BasketLifecycleState.mqh
│   │   ├── BasketMode.mqh              # Orthogonal flags
│   │   ├── SignalType.mqh
│   │   └── TradeDirection.mqh
│   ├── StateMachine/
│   │   ├── IBasketState.mqh
│   │   ├── BasketStateMachine.mqh
│   │   ├── States/
│   │   │   ├── WaitDetailsState.mqh
│   │   │   ├── ActiveState.mqh
│   │   │   ├── TP1State.mqh
│   │   │   ├── BreakEvenState.mqh
│   │   │   ├── TP2State.mqh
│   │   │   ├── TP3State.mqh
│   │   │   ├── FinishedState.mqh
│   │   │   └── ErrorState.mqh
│   │   └── Transitions/
│   │       └── TransitionGuard.mqh
│   ├── Services/
│   │   ├── RiskCalculator.mqh
│   │   ├── RecoveryEvaluator.mqh
│   │   ├── RiskReductionPlanner.mqh
│   │   ├── TakeProfitPlanner.mqh
│   │   ├── BreakEvenCalculator.mqh
│   │   ├── WeightedAverageEntryCalculator.mqh
│   │   └── PositionRankingService.mqh  # Worst entry sıralama
│   └── Events/
│       ├── DomainEvent.mqh
│       └── BasketEventTypes.mqh
│
├── Application/
│   ├── Ports/                          # Interface tanımları
│   │   ├── ITradeGateway.mqh
│   │   ├── IPositionReader.mqh
│   │   ├── ISignalRepository.mqh
│   │   ├── IBasketStateRepository.mqh
│   │   ├── IRemoteStateSync.mqh
│   │   ├── IClock.mqh
│   │   ├── ILogger.mqh
│   │   └── ISymbolInfoProvider.mqh
│   ├── UseCases/
│   │   ├── Bootstrap/
│   │   │   └── RecoverFromRestartUseCase.mqh
│   │   ├── Signals/
│   │   │   ├── PollSignalsUseCase.mqh
│   │   │   ├── ProcessInitialSignalUseCase.mqh
│   │   │   └── ProcessDetailsSignalUseCase.mqh
│   │   ├── Basket/
│   │   │   ├── OpenInitialBasketUseCase.mqh
│   │   │   ├── ActivateBasketUseCase.mqh
│   │   │   └── FinishBasketUseCase.mqh
│   │   ├── Risk/
│   │   │   ├── EvaluateRiskUseCase.mqh
│   │   │   └── ReduceRiskUseCase.mqh
│   │   ├── Recovery/
│   │   │   └── ExecuteRecoveryUseCase.mqh
│   │   ├── TakeProfit/
│   │   │   ├── HandleTP1UseCase.mqh
│   │   │   ├── HandleTP2UseCase.mqh
│   │   │   └── HandleTP3UseCase.mqh
│   │   └── BreakEven/
│   │       └── ActivateBreakEvenUseCase.mqh
│   ├── Orchestrators/
│   │   ├── BasketOrchestrator.mqh      # Ana koordinatör
│   │   └── TickEventDispatcher.mqh
│   ├── Commands/
│   │   ├── TradeCommand.mqh
│   │   └── CommandQueue.mqh            # Idempotent command queue
│   └── DTOs/
│       ├── SignalDto.mqh
│       └── BasketStateDto.mqh
│
├── Infrastructure/
│   ├── MT5/
│   │   ├── Mt5TradeGateway.mqh
│   │   ├── Mt5PositionReader.mqh
│   │   ├── Mt5SymbolInfoProvider.mqh
│   │   ├── Mt5Clock.mqh
│   │   └── Mt5TradeTransactionHandler.mqh
│   ├── Rest/
│   │   ├── RestClient.mqh
│   │   ├── RestSignalRepository.mqh
│   │   ├── RestRemoteStateSync.mqh
│   │   └── ApiResponseParser.mqh
│   ├── Persistence/
│   │   ├── FileBasketStateRepository.mqh
│   │   ├── StateSerializer.mqh
│   │   └── AtomicFileWriter.mqh
│   └── Logging/
│       ├── FileLogger.mqh
│       ├── StructuredLogEntry.mqh
│       └── LogLevel.mqh
│
└── Interfaces/
    ├── Bootstrapper.mqh                # Composition root wiring (S0.1: mt5/Include altında)
    └── EAEventHandlers.mqh               # (planned)
```

> **S0.1:** Repo root `Interfaces/` kaldırıldı. `CEAConfiguration` → `Application/Configuration/`. `CMt5ConfigurationLoader` → `Infrastructure/Configuration/`.

## 2.3 Python Servis Yapısı

```
python/signal_service/
├── main.py                             # FastAPI app entry
├── config.py
├── api/
│   ├── routes/
│   │   ├── signals.py                  # GET pending, POST ack
│   │   ├── baskets.py                  # State sync endpoints
│   │   └── health.py
│   └── dependencies.py
├── parser/
│   ├── telegram_parser.py
│   ├── signal_normalizer.py
│   └── correlation_key_generator.py
├── models/
│   ├── signal.py                       # DB + API schema
│   └── basket_audit.py
├── repository/
│   ├── signal_repository.py
│   └── basket_audit_repository.py
└── telegram/
    └── listener.py
```

## 2.4 Dosya Adlandırma Kuralları

| Öğe | Kural | Örnek |
|-----|-------|-------|
| Domain entity | İsim + `.mqh` | `Basket.mqh` |
| Use case | Fiil + UseCase | `OpenInitialBasketUseCase.mqh` |
| Port | I + İsim | `ITradeGateway.mqh` |
| Adapter | Teknoloji + Port adı | `Mt5TradeGateway.mqh` |
| State | Durum + State | `WaitDetailsState.mqh` |
| Test | Test + sınıf adı | `TestRiskCalculator.mq5` |

## 2.5 Include Guard Kuralı

Her `.mqh` dosyası benzersiz include guard kullanır:

```cpp
#ifndef BASKET_RECOVERY_DOMAIN_BASKET_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_MQH
// ...
#endif
```

## 2.6 Derleme Birimi Stratejisi

Her sprint sonunda derlenebilir olması için:

- Her modül kendi bağımlılık ağacına sahip
- Henüz implement edilmemiş use case'ler **Null Object** adapter ile stub'lanır
- `#ifdef FEATURE_RECOVERY_ENGINE` gibi feature flag'ler sprint bazlı açılır
- Feature flag'ler `Shared/Constants/FeatureFlags.mqh` dosyasında merkezi yönetilir

---

## 2.7 v2 Ek Klasörler (Application Refactor)

v1 UseCase/Orchestrator yapısı v2'de aşağıdaki ile **değiştirilir**:

```
Application/
├── Commands/                    # External + internal command DTOs
│   ├── CreateBasketCommand.mqh
│   ├── ActivateBasketCommand.mqh
│   ├── UpdateSLCommand.mqh
│   ├── UpdateTPCommand.mqh
│   ├── CloseBasketCommand.mqh
│   └── Internal/
├── CommandHandlers/             # ICommandHandler implementations
├── EventHandlers/               # IEventHandler implementations
├── Events/DomainEvents.mqh
├── Kernel/
│   ├── ApplicationKernel.mqh
│   ├── CommandProcessor.mqh
│   └── PriceThresholdMonitor.mqh
├── TradeRequests/               # TradeRequest DTOs (NOT commands)
└── Ports/
    ├── ICommandQueue.mqh
    ├── IEventBus.mqh
    ├── ITradeRequestQueue.mqh
    ├── IPositionSnapshotStore.mqh
    ├── IExecutionEnvironment.mqh
    └── IConfigurationProfileLoader.mqh

Domain/
├── StateMachine/
│   ├── TransitionRuleRegistry.mqh    # replaces State classes
│   ├── TransitionEngine.mqh
│   └── ModeTransitionRuleRegistry.mqh
├── Snapshots/PositionSnapshot.mqh
└── Configuration/ProfileConfig types

Infrastructure/
├── MT5/Mt5TradeExecutor.mqh          # ONLY OrderSend/Modify/Close
├── Snapshot/FileBackedSnapshotStore.mqh
├── Commands/FileCommandQueue.mqh
├── Events/InMemoryEventBus.mqh
├── Backtest/SimulatedTradeExecutor.mqh
├── Configuration/JsonProfileLoader.mqh
└── Rest/RestCommandSourceAdapter.mqh

MQL5/Files/BasketRecovery/
├── profiles/default/*.profile.json
├── commands/
├── trade_requests/
├── snapshots/
└── events/
```

### v1 → v2 Kaldırılanlar

| v1 | v2 Karşılık |
|----|-------------|
| `PollSignalsUseCase` | `RestCommandSourceAdapter` + `CommandProcessor` |
| `BasketOrchestrator` | `ApplicationKernel` + event handlers |
| `Mt5TradeGateway` | `Mt5TradeExecutor` |
| `Mt5PositionReader` (runtime) | `IPositionSnapshotStore` |
| `IBasketState` subclasses | `TransitionRuleRegistry` |
| `UseCases/*` | `CommandHandlers/*` + `EventHandlers/*` |
