# 9. Recovery Engine Tasarımı

## 9.1 Recovery Tanımı (Spec)

```
Recovery Step = 0.2 pip (configurable)

WHEN price moves AGAINST the basket by >= recovery step:
    IF projected_basket_risk <= max_risk:
        Open 1 additional position (configured recovery lot)
    ELSE:
        Do NOT open (max risk lockout)

AFTER Break-Even activated:
    Recovery PERMANENTLY disabled for this basket
```

---

## 9.2 Recovery Engine Bileşenleri

```
RecoveryEngine (conceptual module)
├── RecoveryEvaluator        → should we trigger?
├── RecoveryLevelTracker     → step index + anchor price
├── ExecuteRecoveryUseCase   → open + persist
└── RiskCalculator           → projected risk gate
```

---

## 9.3 Adverse Price Movement Tanımı

| Direction | Against (adverse) | For (favorable) |
|-----------|-------------------|-----------------|
| SELL basket | Bid **rising** | Bid falling |
| BUY basket | Ask **falling** | Ask rising |

### Step Crossing Logic

```
anchor = basket.lastRecoveryAnchorPrice  (initially: weighted avg entry at activation)
current = direction == SELL ? bid : ask
adverseMove = direction-aware distance(current, anchor)

IF adverseMove >= recoveryStep × (lastRecoveryStepIndex + 1):
    TRIGGER recovery evaluation
```

**Önemli:** Her recovery sonrası anchor güncellenmez — step index artar, threshold kümülatif:

```
Step 0 → trigger at 0.2 pip adverse from anchor
Step 1 → trigger at 0.4 pip adverse from anchor
Step 2 → trigger at 0.6 pip adverse from anchor
...
```

Alternatif (daha agresif): her recovery sonrası anchor = current price.  
**Öneri:** Spec "whenever price moves against" diyor — **kümülatif anchor** (başlangıç entry'den) daha güvenli; config ile `anchorMode: CUMULATIVE | RESET_ON_RECOVERY` seçilebilir.

---

## 9.4 Recovery Pre-conditions (Guard Chain)

Recovery açılmadan önce tüm guard'lar geçilmeli:

```
1. lifecycle IN (ACTIVE, TP1)           // not WAIT_DETAILS, not BREAK_EVEN+
2. recoveryPermanentlyDisabled == false
3. maxRiskLockout == false
4. basket.details.stopLoss != null      // SL must exist
5. openPositionCount < maxPositions     // config safety cap
6. RecoveryEvaluator.shouldTrigger() == true
7. RiskCalculator.canOpenRecovery() == true
8. No pending OPEN command in queue     // idempotency
9. Reentrancy guard not active
```

---

## 9.5 Recovery Execution Flow

```
ExecuteRecoveryUseCase.execute(basket):
    1. snapshot = RiskCalculator.calculateBasketRisk(...)
    2. newEntry = current market price (SELL→bid, BUY→ask)
    3. projected = RiskCalculator.projectRiskAfterRecovery(
           basket, recoveryLot, newEntry, basket.details.stopLoss)
    4. IF projected > maxRiskUsd:
           set maxRiskLockout = true
           LOG "Recovery blocked: max risk"
           RETURN Failure
    5. command = TradeCommand(OPEN_RECOVERY, lot=recoveryLot)
    6. CommandQueue.enqueue(command)
    7. On fill:
           basket.positions.add(newPosition)
           basket.lastRecoveryStepIndex++
           set mode recoveryActive = false
           persist
    8. Remote sync
```

---

## 9.6 Recovery Lot Size

Config'den:

```
RecoveryConfig {
    Price recoveryStepPips       // 0.2 default
    LotSize recoveryLotSize      // e.g. 0.01
    int maxRecoverySteps         // safety cap, e.g. 50
    int maxTotalPositions        // e.g. 20
}
```

Spec: "using configured lot size" — sabit lot. Gelecek extension: equity-scaled recovery lot.

---

## 9.7 Recovery vs Risk Reduction — Mutual Exclusion

Aynı tick'te ikisi de tetiklenebilir mi?

```
Recovery: price moving AGAINST
Risk Reduction: price moving FAVORABLE + risk > target
```

**Mantıksal olarak mutex** — aynı tick'te ikisi birden olmamalı. Guard:

```
IF riskReductionActive:
    SKIP recovery evaluation this tick
IF recoveryActive (pending open):
    SKIP risk reduction this tick
```

Öncelik sırası (configurable):
1. **Risk Reduction** (risk azaltma öncelikli — spec'te açık değil, öneri)
2. Recovery
3. TP checks

---

## 9.8 Recovery Position Metadata

Her recovery pozisyonu etiketlenir:

```
BasketPosition {
    ...
    PositionRole role  // INITIAL | RECOVERY
    int recoveryStepIndex
}
```

Comment format (broker'da):
```
"BR:{basket_id}:R{step_index}"
```

Magic number: basket başına unique veya global EA magic + basket hash.

---

## 9.9 Break-Even Sonrası Recovery Kill Switch

```
ActivateBreakEvenUseCase.execute():
    ...
    basket.recoveryPermanentlyDisabled = true
    basket.modes.recoveryActive = false
    basket.modes.maxRiskLockout = false  // irrelevant now
    // State → BREAK_EVEN
```

Bu flag **asla reset edilmez** — basket FINISHED olana kadar.

---

## 9.10 Recovery Engine Disable Matrix

| Lifecycle State | Recovery Allowed |
|-----------------|-----------------|
| PENDING_OPEN | ❌ |
| WAIT_DETAILS | ❌ |
| ACTIVE | ✅ |
| TP1 | ✅ (until BE) |
| BREAK_EVEN | ❌ permanent |
| TP2 | ❌ |
| TP3 | ❌ |
| FINISHED | ❌ |
| ERROR | ❌ |
| SUSPENDED | ❌ |

---

## 9.11 Duplicate Recovery Prevention

Aynı step seviyesinde birden fazla recovery açılmasını engelle:

```
RecoveryLevelTracker {
    int lastTriggeredStepIndex
    bool recoveryInFlight  // command queued but not filled
    
    canTrigger(stepIndex):
        return stepIndex > lastTriggeredStepIndex AND NOT recoveryInFlight
}
```

OnTradeTransaction fill → `recoveryInFlight = false`, `lastTriggeredStepIndex = stepIndex`.

---

## 9.12 Recovery Engine Test Senaryoları

| # | Senaryo | Beklenen |
|---|---------|----------|
| 1 | 0.2 pip adverse, headroom ok | 1 recovery opened |
| 2 | 0.2 pip adverse, projected > max | blocked, lockout |
| 3 | BE activated | no more recovery ever |
| 4 | Same step double tick | only 1 recovery (idempotent) |
| 5 | maxRecoverySteps reached | no more recovery |
| 6 | WAIT_DETAILS | recovery disabled |
| 7 | Favorable price + risk > target | risk reduction, not recovery |

---

## 9.13 Performans Notları

- Recovery step check: O(1) per basket per tick
- Yalnızca ACTIVE/TP1 basket'lerde çalışır
- Price cache kullan; symbol mismatch → skip
- Recovery evaluation debounce: aynı step için 1 tick'te max 1 evaluation
