# 10. Basket Engine Tasarımı

## 10.1 Basket Engine Tanımı

Basket Engine, sepetin **yaşam döngüsünü uçtan uca yöneten** üst düzey orchestration katmanıdır. Domain entity (`Basket`), state machine, ve tüm use case'leri koordine eder.

```
BasketEngine (conceptual)
├── BasketOrchestrator         → multi-basket manager
├── BasketFactory              → basket creation from signals
├── BasketStateMachine         → lifecycle
├── TakeProfitEngine           → TP1/TP2/TP3
├── BreakEvenEngine            → BE activation + SL sync
├── RecoveryEngine             → (bkz. doc 09)
├── RiskEngine                 → (bkz. doc 08)
└── BasketReconciliationEngine → restart sync
```

---

## 10.2 Basket Aggregate Root

`Basket` aggregate root'tur. Tüm mutation basket üzerinden:

```
Basket (Aggregate Root)
├── Identity: basketId, correlationKey, magicNumber
├── Trading: symbol, direction, positions[]
├── Configuration: profileSnapshot (immutable after bind), recoveryConfig, tpLevels, breakEvenConfig
├── Versioning: version, lastCommandId, lastEventId, lastModifiedUtc  (S0.1: CBasketVersion)
├── Runtime: lifecycleState, modes, realizedProfit, lastRecoveryStepIndex
├── Signal: details (nullable until Signal #2)
└── Audit: createdAt, stateHistory[], lastPersistedAt
```

### Invariant Enforcement

| Invariant | Enforcement Point |
|-----------|-------------------|
| Max 1 active basket per correlationKey | BasketFactory |
| Position count >= 0 | Basket entity |
| FINISHED → no open positions | FinishBasketUseCase |
| SL sync after BE | ActivateBreakEvenUseCase |
| No recovery after BE | Basket.canOpenRecovery() |

---

## 10.3 BasketFactory

```
BasketFactory.createFromInitialSignal(signal, config):
    basket = new Basket(
        id = generateUUID(),
        correlationKey = signal.correlationKey,
        symbol = signal.symbol,
        direction = signal.direction,
        lifecycleState = PENDING_OPEN,
        riskProfile = config.riskProfile,
        recoveryConfig = config.recoveryConfig,
        initialLot = config.defaultLot,  // 0.01
        initialPositionCount = 3
    )
    RETURN basket
```

---

## 10.4 BasketOrchestrator

Multi-basket desteği zorunlu — aynı anda birden fazla sinyal gelebilir.

```
BasketOrchestrator {
    map<BasketId, BasketContext> activeBaskets
    
    onTimer():
        PollSignalsUseCase.execute()
        for each signal: route to appropriate handler
    
    onTick(symbol, bid, ask):
        for each basket where basket.symbol == symbol:
            TickEventDispatcher.dispatch(basket, bid, ask)
    
    onTradeTransaction(trans):
        find basket by ticket/magic/comment
        update position state
        CommandQueue.markExecuted if applicable
        check lifecycle transitions
    
    onInit():
        RecoverFromRestartUseCase.execute()
}
```

### BasketContext

```
BasketContext {
    Basket basket
    BasketStateMachine stateMachine
    RiskSnapshot lastRiskSnapshot
    datetime lastRiskEvalAt
    datetime lastRecoveryEvalAt
    bool dirty  // needs persist
}
```

---

## 10.5 Take Profit Engine

### TP Level Monitoring

```
TakeProfitEngine (conceptual)
├── TPLevelMonitor          → price threshold detection
├── TakeProfitPlanner       → partial close plan
├── HandleTP1UseCase
├── HandleTP2UseCase
└── HandleTP3UseCase
```

### TP Trigger Detection

Direction-aware crossing:

```
SELL basket: TP triggered when bid <= tpPrice
BUY basket:  TP triggered when ask >= tpPrice
```

**One-shot guard:** Her TP seviyesi basket başına yalnızca bir kez tetiklenir:

```
Basket.tpTriggeredFlags { tp1: bool, tp2: bool, tp3: bool }
```

### TP1 Partial Close Algoritması

```
HandleTP1UseCase.execute(basket):
    1. floatingProfit = sum(open position profits)  // only positive positions count?
    2. targetRealize = floatingProfit × 0.33
    3. commands = TakeProfitPlanner.planTP1(basket, targetRealize)
    4. Execute commands via CommandQueue (worst entry first)
    5. basket.realizedProfit += realizedFromClose
    6. stateMachine.dispatch(TP1_REACHED)
    7. persist
```

**Spec yorumu:** "Close positions until 33% of current floating profit has been realized"
- Greedy: worst entry'den başla, kapat, kalan floating'i yeniden hesapla, ta ki realized >= 33% × original_floating

### TP2 Partial Close

```
targetRealize = floatingProfit_at_tp2 × 0.66
// cumulative realized since basket start tracked in basket.realizedProfit
```

**Netleştirme:** TP2'deki %66, TP2 anındaki floating profit'in %66'sı — TP1'de realize edilenler hariç değil, TP2 trigger anındaki snapshot.

### TP3 — Full Close

```
HandleTP3UseCase.execute(basket):
    1. close ALL remaining open positions
    2. stateMachine → CLOSING → FINISHED
    3. FinishBasketUseCase.cleanup()
```

---

## 10.6 Break-Even Engine

```
BreakEvenEngine (conceptual)
├── BreakEvenCalculator
├── ActivateBreakEvenUseCase
└── BreakEvenStopLossSyncUseCase  → SL drift correction
```

### Activation (NOT automatic at TP1)

```
Monitor every tick AFTER TP1:
    IF basket.realizedProfit >= targetRiskAmount × 0.33:
        ActivateBreakEvenUseCase.execute()
```

### SL Calculation

```
avgEntry = WeightedAverageEntryCalculator.calculate(openPositions)
spread = SymbolInfo.currentSpread
buffer = config.breakEvenSafetyBufferPips

SELL: breakEvenSL = avgEntry + spread + buffer
BUY:  breakEvenSL = avgEntry - spread - buffer
```

### Post-BE SL Sync

Yeni pozisyon kapanınca avg entry değişmez (kalan pozisyonlar). Ancak partial close sonrası kalan pozisyonların SL'i zaten set. BE sonrası yeni recovery yok → SL drift riski düşük.

Periyodik SL sync (optional): timer ile tüm SL'lerin BE fiyatında olduğunu doğrula.

---

## 10.7 Basket Identification (Broker)

Her basket broker'da tanımlanabilir olmalı:

| Alan | Değer |
|------|-------|
| Magic Number | `baseMagic + basketHash % 1000` veya dedicated per basket |
| Comment | `BR:{basket_id_short}` |
| Position Comment | `BR:{basket_id_short}:I{index}` veya `:R{step}` |

Restart reconciliation bu identifier'lara dayanır.

---

## 10.8 Multi-Basket Concurrency

Aynı symbol'de birden fazla basket olabilir (farklı correlation key):

```
Orchestrator.onTick(XAUUSD):
    basket_A (SELL, ACTIVE) → evaluate
    basket_B (BUY, WAIT_DETAILS) → skip (no SL)
```

Risk aggregation across baskets: **Spec'te yok** — her basket bağımsız. Gelecek extension: account-level risk cap.

---

## 10.9 Basket Lifecycle Cleanup

```
FinishBasketUseCase.execute(basket):
    1. Verify no open positions
    2. lifecycleState = FINISHED
    3. Archive state to history file
    4. Delete active state file
    5. Remote sync FINISHED
    6. Remove from activeBaskets map
    7. Log summary (P&L, duration, recovery count)
```

---

## 10.10 Basket Engine Event Priority

Aynı tick'te birden fazla event:

```
Priority (high → low):
1. TP3 (final exit)
2. TP2
3. TP1
4. Break-Even activation check
5. Risk Reduction
6. Recovery
7. Persist (debounced)
```

---

## 10.11 Basket Engine Observability

Her basket için runtime metrics:

```
BasketMetrics {
    int totalRecoveries
    int totalPartialCloses
    Money totalRealizedProfit
    Money maxDrawdownDuringBasket
    datetime duration
    int stateTransitionCount
}
```

Metrics remote sync ile PostgreSQL'e gönderilir (analytics).
