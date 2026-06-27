# 26. Sprint 0.1 — Mimari Audit Düzeltmeleri

> **Kapsam:** Sprint 0 iskeletinde tespit edilen 10 mimari ihlalin giderilmesi. Sprint 1 başlatılmaz.

## 26.1 Özet

| # | Audit Bulgusu | Çözüm |
|---|---------------|-------|
| 1 | Application → Interfaces bağımlılığı | `CEAConfiguration` Application katmanına taşındı; `CMt5ConfigurationLoader` Infrastructure'da |
| 2 | MT5 tipleri Application/Domain port'larında | `CNormalizedTradeTransaction` Shared DTO; MT5 tipleri yalnızca Infrastructure + EA composition root |
| 3 | Domain'de MT5 API çağrıları | `TimeCurrent`/`GetTickCount64`/`MathRand` Infrastructure'a taşındı; `IClock`, `IUniqueIdGenerator` port'ları |
| 4 | Profile mutability | `CProfileSnapshot` immutable factory; `CBasket.BindProfileSnapshot()` tek seferlik |
| 5 | Basket version eksik | `CBasketVersion` + `CBasket` alanları: Version, LastCommandId, LastEventId, LastModifiedUtc |
| 6 | ApplicationContext = Service Locator | Genel getter'lar kaldırıldı; dar API: `ApplyNormalizedTransaction`, `LogShutdown`, `SnapshotCount` |
| 7 | Senkron disk I/O logging | `ILogBuffer`, `IAsyncLogWriter` port'ları tanımlandı (buffering Sprint 15+) |
| 8 | SnapshotStore broker sorguları | `ApplyNormalizedTransaction` normalize-only; `CBrokerReconciliationService` startup reconcile |
| 9 | `Result<T>.Value()` güvensiz | `TryGetValue` / `ValueOr`; doğrudan `Value()` kaldırıldı |
| 10 | Dokümantasyon güncel değil | Bu belge + etkilenen mimari belgeler güncellendi |

---

## 26.2 Yeni Bağımlılık Grafiği

```
┌─────────────────────────────────────────────────────────────┐
│  EA (BasketRecoveryEA.mq5) — Composition Root               │
│  MqlTradeTransaction / Request / Result YALNIZCA BURADA     │
└────────────┬───────────────────────────────┬────────────────┘
             │                               │
             ▼                               ▼
┌────────────────────────┐    ┌──────────────────────────────┐
│  Interfaces            │    │  Infrastructure (MT5 edge)    │
│  Bootstrapper.mqh      │    │  Mt5TradeTransactionNormalizer│
└────────────┬───────────┘    │  Mt5ConfigurationLoader       │
             │                │  Mt5Clock / Mt5UniqueIdGenerator│
             ▼                │  BrokerReconciliationService  │
┌────────────────────────┐    │  InMemorySnapshotStore        │
│  Application           │    │  FileLogger (sync, ILogger)   │
│  ApplicationContext ◄──┼────┤  DefaultProfileLoader         │
│  ServiceContainer      │    └──────────────────────────────┘
│  Ports (IClock, ILogger,│
│   IPositionSnapshotStore│
│   IBrokerReconciliation│
│   ILogBuffer, IAsync…) │
│  EAConfiguration       │
│  ProfileSnapshotFactory│
└────────────┬───────────┘
             │
             ▼
┌────────────────────────┐
│  Domain                │
│  CBasket + CBasketVersion│
│  CProfileSnapshot (RO) │
│  CProfileBundle (load) │
│  CPositionSnapshot     │
└────────────┬───────────┘
             │
             ▼
┌────────────────────────┐
│  Shared                │
│  CNormalizedTradeTransaction│
│  CResult<T> (TryGetValue)│
│  Identifiers, UtcTime  │
└────────────────────────┘
```

**Katman kuralları (S0.1 sonrası):**

| Kaynak | Hedef | İzin |
|--------|-------|------|
| Domain | Shared | ✅ |
| Application | Domain, Shared | ✅ |
| Application | Interfaces | ❌ |
| Application | Infrastructure | ❌ |
| Infrastructure | Application (ports), Domain, Shared | ✅ |
| Interfaces | Application, Infrastructure | ✅ (composition root) |
| EA (.mq5) | Interfaces, Infrastructure (normalizer) | ✅ |
| Domain/Application | MT5 API / MqlTrade* | ❌ |

---

## 26.3 OnTradeTransaction Akışı (S0.1)

```
OnTradeTransaction(trans, request, result)
    │
    ▼
CMt5TradeTransactionNormalizer.Normalize()   ← Infrastructure (broker comment lookup)
    │
    ▼
CNormalizedTradeTransaction
    │
    ▼
CApplicationContext.ApplyNormalizedTransaction()
    │
    ▼
CInMemorySnapshotStore.ApplyNormalizedTransaction()   ← broker API YOK
```

Startup broker taraması:

```
CBootstrapper.Bootstrap()
    │
    ▼
CBrokerReconciliationService.ReconcileAtStartup()
    │  PositionsTotal / PositionSelectByTicket
    ▼
IPositionSnapshotStore.CreateEmpty(basketId)
```

---

## 26.4 Kalan Blokörler (Sprint 1 öncesi)

| ID | Blokör | Sprint |
|----|--------|--------|
| B1 | JSON profile dosyalarından yükleme (`JsonProfileLoader`) | S1 |
| B2 | `BasketVersion` artış mantığı (command handler sonrası) | S3+ |
| B3 | `IAsyncLogWriter` buffering implementasyonu | S15 |
| B4 | `CommandProcessor` / `ApplicationKernel` — EA henüz OnTick işlemiyor | S3 |
| B5 | `PositionEntry` listesi snapshot'ta yok — sadece sayaçlar | S4 |
| B6 | Derleme doğrulaması MetaEditor ortamında yapılmadı | CI/S0.2 |
| B7 | `g_applicationContext` global — composition root kabul edildi; DI container Sprint 3'te daraltılacak | S3 |

---

## 26.5 Değişen Dosyalar (S0.1)

### Yeni
- `Shared/DTOs/NormalizedTradeTransaction.mqh`
- `Shared/Types/UtcTime.mqh`
- `Domain/Configuration/ProfileSnapshot.mqh`
- `Domain/ValueObjects/BasketVersion.mqh`
- `Application/Configuration/EAConfiguration.mqh`
- `Application/Configuration/ProfileSnapshotFactory.mqh`
- `Application/Ports/IUniqueIdGenerator.mqh`
- `Application/Ports/ILogBuffer.mqh`
- `Application/Ports/IAsyncLogWriter.mqh`
- `Application/Ports/IBrokerReconciliationService.mqh`
- `Infrastructure/Configuration/Mt5ConfigurationLoader.mqh`
- `Infrastructure/MT5/Mt5TradeTransactionNormalizer.mqh`
- `Infrastructure/MT5/Mt5UniqueIdGenerator.mqh`
- `Infrastructure/Snapshot/BrokerReconciliationService.mqh`
- `Interfaces/Bootstrapper.mqh` (repo root `Interfaces/` kaldırıldı)

### Güncellenen
- `Application/Kernel/ApplicationContext.mqh`
- `Application/Kernel/ServiceContainer.mqh`
- `Application/Ports/IPositionSnapshotStore.mqh`
- `Domain/Entities/Basket.mqh`
- `Domain/Configuration/ProfileBundle.mqh`
- `Shared/Types/Result.mqh`
- `Shared/Types/Identifiers.mqh`
- `Infrastructure/Snapshot/InMemorySnapshotStore.mqh`
- `Infrastructure/Configuration/DefaultProfileLoader.mqh`
- `Infrastructure/Logging/FileLogger.mqh`
- `Experts/BasketRecovery/BasketRecoveryEA.mq5`

### Silinen
- `Interfaces/Bootstrapper.mqh` (repo root)
- `Interfaces/Configuration/ConfigurationLoader.mqh`
- `Interfaces/Configuration/EAConfiguration.mqh`
