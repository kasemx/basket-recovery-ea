# 8. Risk Engine Tasarımı

> **Revizyon v2:** Risk Engine **yalnızca `PositionSnapshot` okur** — broker taraması yasak. Parametreler **Configuration Profile**'dan gelir. Event Bus üzerinden tetiklenir. Bkz. [22-position-snapshot.md](./22-position-snapshot.md), [23-configuration-profiles.md](./23-configuration-profiles.md).

## 8.1 Risk Tanımları

| Terim | Tanım | Formül |
|-------|-------|--------|
| **Target Risk** | Hedef sepet riski (soft limit) | `equity × targetRiskPct / 100` |
| **Max Risk** | Mutlak üst sınır (hard limit) | `equity × maxRiskPct / 100` |
| **Current Basket Risk** | SL vurulursa kaybedilecek tutar | `Σ positionRiskUsd` |
| **Position Risk** | Tek pozisyonun SL riski | `\|entry - SL\| × lot × tickValuePerPoint` |
| **Headroom** | Max risk'e kadar kalan alan | `maxRiskUsd - currentBasketRiskUsd` |
| **Projected Risk** | Yeni pozisyon sonrası tahmini | `currentBasketRisk + newPositionRisk` |

### Örnek (Spec'ten)

```
Target Risk = 1%    → 10,000 USD equity = 100 USD
Max Risk    = 1.2%  → 10,000 USD equity = 120 USD
Break-Even Trigger = 100 × 33% = 33 USD realized profit
```

---

## 8.2 RiskCalculator — Sorumluluklar

```
RiskCalculator
├── calculate(snapshot, equity, symbolInfo, riskProfile) → RiskSnapshot
├── calculatePositionRisk(entry, effectiveSl, lot, symbolInfo) → Money
├── projectRiskAfterRecovery(snapshot, newLot, newEntry, sl, profile) → Money
├── projectRiskAfterClose(snapshot, closingTicket, profile) → Money
├── isWithinMaxRisk(projectedUsd, maxRiskUsd) → bool
├── isAboveTargetRisk(currentUsd, targetRiskUsd) → bool
└── computeBreakEvenTriggerAmount(targetRiskUsd, profile) → Money
```

**Input değişikliği (v2):** `Basket` entity veya broker positions **değil** — `PositionSnapshot` + `RiskProfileConfig`.

---

## 8.3 RiskSnapshot Value Object

```
RiskSnapshot {
    Money  currentRiskUsd
    Percentage currentRiskPct
    Money  targetRiskUsd
    Money  maxRiskUsd
    Money  headroomUsd
    bool   isAboveTarget
    bool   isAtOrAboveMax
    bool   canOpenRecovery      // projected <= max AND NOT recoveryPermanentlyDisabled
    Money  projectedRecoveryRisk // pre-computed for next recovery lot
}
```

---

## 8.4 Effective Stop Loss Hesabı

Sepetteki tüm pozisyonlar **shared SL** kullanır (Signal #2'den):

```
effective_sl = basket.details.stopLoss  // tüm pozisyonlar için aynı
```

Break-even sonrası:

```
effective_sl = basket.breakEvenStopLoss  // weighted avg + spread + buffer
```

Pozisyon bazlı SL modify edilmişse (partial close sonrası kalanlar):
- Break-even sonrası **tüm kalan pozisyonlar aynı SL'e** zorlanır (sync use case)

---

## 8.5 Risk Evaluation Trigger Points (v2 — Event Bus)

| Event (subscribe) | Handler Aksiyonu |
|-------------------|------------------|
| `BasketActivated` | Baseline risk calc → publish `RiskSnapshotCalculated` |
| `PositionSnapshotUpdated` | Recalculate → maybe `TargetRiskReached` / `MaxRiskReached` |
| `RecoveryStepCrossed` | Projected risk gate (before command enqueue) |
| Price tick (debounced) | Floating update → debounced risk eval |

**Yasak:** `PositionsTotal()`, `PositionSelect()` — Risk Engine içinde broker API **yok**.

**Performans:** O(n) snapshot read; debounced except threshold crossings (doc 25 § 25.5).

---

## 8.6 Risk Reduction Engine

### Koşul (Spec)

```
IF currentBasketRisk > targetRisk
AND price moving favorably (basket direction'a uygun)
THEN close worst entries until currentBasketRisk <= targetRisk
```

### Favorable Price Tanımı

| Direction | Favorable |
|-----------|-----------|
| SELL basket | Bid decreasing (kar yönünde) |
| BUY basket | Ask increasing |

**Direction check window:** Anlık tick yeterli değil — whipsaw koruması için:
- Son N tick'te net favorable hareket > minThreshold
- Veya: son recovery'den bu yana fiyat en az X pip favorable

### RiskReductionPlanner Algoritması

```
1. positions = rankByWorstEntry(basket.positions, basket.direction)
2. currentRisk = calculateBasketRisk(...)
3. IF currentRisk <= targetRisk: RETURN empty
4. FOR each position in positions (worst first):
     projectedRisk = projectRiskAfterClose(basket, position.ticket)
     IF projectedRisk <= targetRisk:
         ADD close command for this position
         BREAK
     ELSE:
         ADD close command for this position
         UPDATE currentRisk = projectedRisk
5. RETURN close commands (ordered)
```

Greedy worst-first yaklaşım spec'e uygun. Optimal değil ama deterministik ve test edilebilir.

---

## 8.7 Max Risk Lockout

```
IF projectRiskAfterRecovery > maxRiskUsd:
    → Do NOT open recovery
    → SET maxRiskLockout = true
    → LOG warning
    → Optional: lifecycle → SUSPENDED
```

Lockout kalkış koşulu:
```
currentBasketRisk < maxRiskUsd × releaseThreshold  // e.g. 95%
AND price favorable
→ maxRiskLockout = false
```

---

## 8.8 WAIT_DETAILS Risk Gap

Signal #1 → Signal #2 arasında SL yok.

**Risk Engine davranışı:**
- `calculateBasketRisk()` → `RiskSnapshot.UNDEFINED` döner
- Recovery, TP, risk reduction **devre dışı**
- **Emergency guard:** max lot exposure limit (config: max 3 × 0.01 = 0.03 lot default)
- **Timeout guard:** Signal #2 gelmezse emergency close (bkz. State Machine §7.9)

---

## 8.9 Equity Snapshot

Risk hesabı anlık equity kullanır:

```
AccountSnapshot {
    Money equity
    Money balance
    Money freeMargin
    datetime capturedAt
}
```

**Kural:** Her risk evaluation'da fresh equity okunur (IClock + IAccountReader port). Cached equity kullanılmaz.

---

## 8.10 Symbol Info Bağımlılığı

```
SymbolInfo {
    double tickSize
    double tickValue
    double pointSize
    int    digits
    double contractSize
    double currentSpread
}
```

Cross-symbol basket yok — her basket tek symbol. Ancak `ISymbolInfoProvider` port symbol-agnostic kalır.

---

## 8.11 Test Senaryoları (Risk Engine)

| # | Senaryo | Beklenen |
|---|---------|----------|
| 1 | 3×0.01 SELL, SL 20 pip away, equity 10k, target 1% | currentRisk ≈ calculated |
| 2 | Recovery projected > max | canOpenRecovery = false |
| 3 | Risk > target, favorable price | riskReductionActive, close worst |
| 4 | Break-even trigger | realized >= target×0.33 |
| 5 | SL undefined (WAIT_DETAILS) | UNDEFINED risk, no recovery |
| 6 | Partial close sonrası | risk recalculated correctly |
| 7 | Break-even SL hit | all remaining close ≈ breakeven |

---

## 8.12 Risk Engine Modül Sınırları (v2)

```
Domain/Services/RiskCalculator.mqh              → pure; reads PositionSnapshot only
Domain/Services/RiskReductionPlanner.mqh        → close plan (pure)
Application/EventHandlers/RiskEvaluationHandler → subscribes PositionSnapshotUpdated
Application/EventHandlers/RiskReductionHandler  → subscribes TargetRiskReached
                                                  → enqueues ReduceRiskCloseCommand
Application/CommandHandlers/ReduceRiskHandler   → enqueues TradeRequest (NOT direct trade)
```

Risk Engine **asla trade yapmaz, broker taramaz** — event publish veya command enqueue.
