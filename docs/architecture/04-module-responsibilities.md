# 4. Modül Sorumlulukları

## 4.1 Katman Özeti

| Katman | Sorumluluk | Bağımlılık |
|--------|------------|------------|
| **Interfaces** | EA lifecycle, event wiring, config load | Application |
| **Application** | Use case orchestration, port tanımları | Domain |
| **Domain** | İş kuralları, state machine, hesaplamalar | Shared only |
| **Infrastructure** | MT5, REST, dosya I/O, logging | Application ports |
| **Shared** | Value types, Result, constants | — |

---

## 4.2 Domain Modülleri

### Entities (`Domain/Entities/`)

| Sınıf | Sorumluluk |
|-------|------------|
| `Basket` | Sepet aggregate root; tüm basket invariant'larını korur |
| `BasketPosition` | Tek pozisyon verisi; ticket, entry, lot, SL/TP |
| `TradingSignal` | Immutable sinyal representation |
| `AccountSnapshot` | Equity, balance, margin — risk hesabı için |

**Basket Aggregate Invariant'ları:**
- FINISHED state'te açık pozisyon olamaz
- `recoveryPermanentlyDisabled == true` iken recovery açılamaz
- WAIT_DETAILS'te SL/TP/recovery/TP engine devre dışı
- Break-even aktifken tüm açık pozisyonların SL'i senkronize olmalı

### State Machine (`Domain/StateMachine/`)

| Bileşen | Sorumluluk |
|---------|------------|
| `BasketStateMachine` | Event dispatch, transition guard, state history |
| `IBasketState` implementasyonları | State-specific behavior ve geçiş kuralları |
| `TransitionGuard` | Geçersiz geçişleri engeller |

State sınıfları **trade execution yapmaz** — yalnızca "ne yapılması gerektiğini" döner (intent/command plan).

### Domain Services (`Domain/Services/`)

| Servis | Sorumluluk | Girdi | Çıktı |
|--------|------------|-------|-------|
| `RiskCalculator` | Basket ve pozisyon riski USD/% hesabı | Basket, equity, symbol info | `RiskSnapshot` |
| `RecoveryEvaluator` | Recovery tetikleme kararı | Basket, current price | `bool` + step index |
| `RiskReductionPlanner` | Risk azaltma kapatma planı | Basket, target risk | `list<CloseCommand>` |
| `TakeProfitPlanner` | TP1/TP2 partial close planı | Basket, floating profit | `list<CloseCommand>` |
| `BreakEvenCalculator` | BE aktivasyon + SL fiyatı | Basket, spread, buffer | `Price` |
| `WeightedAverageEntryCalculator` | Ağırlıklı ortalama entry | Positions | `Price` |
| `PositionRankingService` | Worst-entry sıralaması | Positions, direction | Sorted list |

---

## 4.3 Application Modülleri

### Use Cases

| Use Case | Tetikleyici | Sorumluluk |
|----------|-------------|------------|
| `PollSignalsUseCase` | OnTimer | REST'ten pending sinyalleri çek, route et |
| `ProcessInitialSignalUseCase` | Signal #1 | Yeni basket oluştur, correlation key bağla |
| `ProcessDetailsSignalUseCase` | Signal #2 | Mevcut basket'e SL/TP/range uygula |
| `OpenInitialBasketUseCase` | Signal #1 sonrası | 3× market order aç, WAIT_DETAILS persist |
| `ActivateBasketUseCase` | Signal #2 sonrası | ACTIVE'e geç, SL/TP set, risk baseline hesapla |
| `EvaluateRiskUseCase` | Price change / trade event | Güncel risk snapshot üret |
| `ExecuteRecoveryUseCase` | Recovery trigger | 1 pozisyon aç, risk doğrula, persist |
| `ReduceRiskUseCase` | Risk > target + favorable price | Worst entry kapat, risk <= target olana kadar |
| `HandleTP1UseCase` | Price >= TP1 | %33 realize partial close |
| `ActivateBreakEvenUseCase` | Realized >= target×33% | SL'leri avg entry'ye taşı, recovery kapat |
| `HandleTP2UseCase` | Price >= TP2 | %66 realize partial close |
| `HandleTP3UseCase` | Price >= TP3 | Tüm pozisyonları kapat, FINISHED |
| `FinishBasketUseCase` | Basket tamamlandı | Cleanup, persist, ack, audit sync |
| `RecoverFromRestartUseCase` | OnInit | Local state + broker reconcile |

### Orchestrators

| Sınıf | Sorumluluk |
|-------|------------|
| `BasketOrchestrator` | Tüm aktif basket'leri yönetir; event'leri doğru use case'e yönlendirir |
| `TickEventDispatcher` | Fiyat eşik geçişlerini tespit eder (TP1/2/3, recovery step) |

### Ports (Interfaces)

| Port | Sorumluluk |
|------|------------|
| `ITradeGateway` | Broker emir gönderimi |
| `IPositionReader` | Açık pozisyon okuma ve senkronizasyon |
| `ISignalRepository` | Sinyal fetch + ack |
| `IBasketStateRepository` | Local basket state CRUD |
| `IRemoteStateSync` | PostgreSQL audit sync (REST) |
| `IClock` | Zaman abstraction (testability) |
| `ILogger` | Structured logging |
| `ISymbolInfoProvider` | Pip size, tick value, spread, digits |

---

## 4.4 Infrastructure Modülleri

| Modül | Sorumluluk |
|-------|------------|
| `Mt5TradeGateway` | OrderSend, OrderClose, PositionModify sarmalayıcı; retry + slippage |
| `Mt5PositionReader` | PositionsTotal loop; magic/comment filtre |
| `Mt5TradeTransactionHandler` | OnTradeTransaction parse → domain event |
| `RestClient` | WebRequest wrapper; timeout, retry, error mapping |
| `RestSignalRepository` | `/signals/pending`, `/signals/{id}/ack` |
| `RestRemoteStateSync` | `/baskets/{id}/state` POST |
| `FileBasketStateRepository` | JSON serialize/deserialize; atomic write |
| `FileLogger` | Rotating log files; JSON lines format |

---

## 4.5 Python Servis Modülleri

| Modül | Sorumluluk |
|-------|------------|
| `telegram/listener.py` | Telegram mesaj dinleme |
| `parser/telegram_parser.py` | Raw mesaj → structured signal |
| `parser/correlation_key_generator.py` | Signal #1/#2 eşleştirme anahtarı |
| `parser/signal_normalizer.py` | Sembol alias (Gold → XAUUSD), yön normalizasyon |
| `repository/signal_repository.py` | PostgreSQL CRUD; consumed flag |
| `api/routes/signals.py` | MT5 REST endpoints |
| `api/routes/baskets.py` | State sync audit endpoints |

---

## 4.6 Modüller Arası Yasak Bağımlılıklar

```
❌ Domain → Infrastructure
❌ Domain → Application
❌ Domain → MT5 API (#include <Trade\Trade.mqh>)
❌ Use Case → Use Case (doğrudan; orchestrator üzerinden)
❌ Infrastructure → Domain Entity mutation (adapter okur, DTO döner)
✅ Infrastructure → Domain (readonly entity oluşturma)
✅ Application → Domain
✅ Interfaces → Application + Infrastructure (composition root)
```

---

## 4.7 Sepet Başına Sorumluluk Matrisi

| Davranış | Sorumlu Modül | Lifecycle Gereksinimi |
|----------|---------------|----------------------|
| 3 pozisyon aç | `OpenInitialBasketUseCase` | Signal #1 |
| SL/TP set | `ActivateBasketUseCase` | Signal #2 → ACTIVE |
| Recovery aç | `ExecuteRecoveryUseCase` | ACTIVE, recovery enabled |
| Risk azalt | `ReduceRiskUseCase` | ACTIVE, risk > target |
| TP1 partial | `HandleTP1UseCase` | ACTIVE veya TP1 |
| Break-even | `ActivateBreakEvenUseCase` | TP1 sonrası, realized threshold |
| TP2 partial | `HandleTP2UseCase` | BREAK_EVEN veya TP1 |
| TP3 close all | `HandleTP3UseCase` | TP2 sonrası |
| Recovery durdur | `ActivateBreakEvenUseCase` | Break-even activation |
