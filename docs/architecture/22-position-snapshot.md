# 22. Position Snapshot

> **Revizyon:** v2 — Risk Engine broker'ı **asla taramaz**. Tüm pozisyon okuma in-memory snapshot üzerinden.

## 22.1 Problem (v1 Zayıflığı)

v1'de `Mt5PositionReader.getOpenPositions()` broker loop'u yapıyordu. Risk Engine ve recovery modülleri dolaylı olarak broker'a bağımlıydı:
- Performans: O(n) broker scan
- Tutarsızlık: scan anı vs trade fill anı race
- Test: broker mock gerekli
- Backtest: mümkün değil

---

## 22.2 Position Snapshot Modeli

```
PositionSnapshot {
    SnapshotVersion     version         // monotonic per basket
    BasketId            basketId
    datetime            updatedAt
    list<PositionEntry> positions
    Money               totalFloatingProfit
    Price               weightedAvgEntry
    int                 openCount
}

PositionEntry {
    ulong       ticket
    string      symbol
    TradeDirection direction
    Price       entryPrice
    LotSize     lot
    Price       stopLoss
    Price       takeProfit
    Money       floatingProfit
    PositionRole role
    int         recoveryStepIndex
    datetime    openTime
    bool        isClosed              // soft delete; history için
}
```

---

## 22.3 IPositionSnapshotStore Port

```
IPositionSnapshotStore {
    get(basketId) → PositionSnapshot | null
    getAll(accountId) → list<PositionSnapshot>
    
    applyTransaction(tx) → Result       // ONLY mutation entry point
    createEmpty(basketId) → Result
    remove(basketId) → Result           // basket finished
    
    getVersion(basketId) → SnapshotVersion
}
```

**Kural:** Snapshot'a yalnızca `TradeExecutor` (fill sonrası) ve `RestartReconciliationService` (startup) yazabilir.

---

## 22.4 TradeTransaction Normalizer

> **S0.1:** `MqlTradeTransaction` / `MqlTradeRequest` / `MqlTradeResult` yalnızca Infrastructure (`CMt5TradeTransactionNormalizer`) ve EA composition root'ta bulunur. Application port'u `CNormalizedTradeTransaction` alır.

```
OnTradeTransaction(trans, request, result):
    normalized = Mt5TradeTransactionNormalizer.normalize(trans, request, result)
    // broker comment lookup (OrderSelect / HistoryDealSelect) — Infrastructure ONLY
    
    ApplicationContext.applyNormalizedTransaction(normalized)
    // → PositionSnapshotStore.applyNormalizedTransaction(normalized)
    EventBus.publish(PositionSnapshotUpdated{basketId, version})   // Sprint 4+
```

```
CNormalizedTradeTransaction {          // Shared/DTOs — MT5-free
    long         transactionType
    ulong        orderId, dealId, positionId
    string       symbol, comment
    CBasketId    basketId                // parsed from comment "BR:{id}:..."
    datetime     occurredAtUtc
    ...
}
```

---

## 22.5 Snapshot Update Kuralları

| Transaction | Snapshot Değişikliği |
|-------------|---------------------|
| OPEN | Add PositionEntry; version++ |
| CLOSE | Mark isClosed; remove from open list; version++ |
| MODIFY_SL | Update entry.stopLoss; version++ |
| MODIFY_TP | Update entry.takeProfit; version++ |

Derived fields her update'te yeniden hesaplanır:
- `weightedAvgEntry`
- `totalFloatingProfit` (price cache'den)
- `openCount`

---

## 22.6 Risk Engine — Snapshot-Only Okuma

```
RiskEvaluationHandler subscribes PositionSnapshotUpdated:
    snapshot = snapshotStore.get(basketId)
    equity = accountSnapshotReader.get()
    symbolInfo = symbolInfoProvider.get(snapshot.symbol)
    
    risk = RiskCalculator.calculate(snapshot, equity, symbolInfo, profile)
    
    eventBus.publish(RiskSnapshotCalculated{basketId, risk})
    
    IF risk.isAboveTarget: publish(TargetRiskReached)
    IF risk.isAtOrAboveMax: publish(MaxRiskReached)
```

```
RiskCalculator.calculate(snapshot, equity, symbolInfo, profile):
    // INPUT: PositionSnapshot — NOT broker, NOT Basket entity positions
    FOR each entry in snapshot.positions WHERE NOT isClosed:
        positionRisk = |entry - effectiveSL| × lot × tickValue
    ...
```

**RiskCalculator broker veya MT5 API bilmez.**

---

## 22.7 Floating Profit Güncelleme

Snapshot'taki floating profit tick ile güncellenir:

```
PriceCacheHandler.onTick(symbol, bid, ask):
    FOR each snapshot WHERE symbol matches:
        snapshot.recalculateFloating(bid, ask)
        // version artmaz — sadece derived field
        // Risk re-eval: debounced 100ms or on threshold cross
```

Floating recalc version artırmaz — yalnızca `TradeTransaction` version artırır. Risk eval debounce ile whipsaw önlenir.

---

## 22.8 Restart Reconciliation

Startup'ta snapshot broker ile senkronize edilir — **tek seferlik broker scan**:

```
RestartReconciliationService:
    brokerPositions = brokerScan()    // ONLY place besides TradeExecutor internals
    localSnapshots = snapshotStore.loadAllFromDisk()
    
    FOR each basket:
        reconcile(localSnapshot, brokerPositions)
        snapshotStore.applyReconciliation(result)
    
    publish(RestartRecoveryCompleted)
```

Normal runtime'da broker scan **yok**. TradeExecutor dışında broker scan yalnızca restart reconciliation'da.

---

## 22.9 Snapshot Persistence

```
MQL5/Files/BasketRecovery/snapshots/
└── basket_{basketId}_v{version}.json   // or single file with version field
```

Her `applyTransaction` → async debounced persist (max 200ms).  
Restart: load snapshot + reconcile with broker.

---

## 22.10 Backtest Snapshot

```
SimulatedTradeExecutor.applyFill():
    snapshotStore.applyTransaction(simulatedTx)
    // identical path to live
```

Historical replay aynı snapshot pipeline — Risk Engine kodu değişmez.

---

## 22.11 v1 Mt5PositionReader Kaldırıldı

| v1 | v2 |
|----|-----|
| `IPositionReader.getOpenPositions()` | `IPositionSnapshotStore.get()` |
| Risk Engine → broker scan | Risk Engine → snapshot read |
| `Mt5PositionReader` runtime | Yalnızca `RestartReconciliationService` broker scan |

---

## 22.12 Consistency Guarantees

| Garanti | Mekanizma |
|---------|-----------|
| Snapshot broker'dan geride kalmaz | OnTradeTransaction zorunlu handler |
| Risk stale data okumaz | `PositionSnapshotUpdated` event trigger |
| Duplicate transaction | Normalizer idempotency by deal_id |
| Partial close doğru lot | Transaction carries closed lot; entry updated |
