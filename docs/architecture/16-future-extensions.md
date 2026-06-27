# 16. Gelecek Genişleme Noktaları (Future Extensions)

## 16.1 Extension Architecture Prensibi

> **Not (v2):** Backtesting artık "future extension" değil — birinci sınıf. Bkz. [24-backtesting-adapter.md](./24-backtesting-adapter.md).

Tüm extension noktaları **Open/Closed** prensibine uygun tasarlanır.
- Yeni davranış → yeni sınıf/handler
- Mevcut domain logic değişmez
- Feature flags ile gradual rollout

---

## 16.2 Planlanmış Extension Points

### 16.2.1 Command Source Abstraction (v2)

```
interface ICommandSource  (replaces ISignalRepository)
    ├── RestCommandSourceAdapter    (live)
    ├── HistoricalCommandSource     (backtest)
    └── ManualCommandSource         (operator panel)
```

Yeni sinyal kaynağı eklemek için yalnızca yeni adapter + config.

### 16.2.2 Recovery Strategy Plugin

```
interface IRecoveryStrategy {
    shouldTrigger(basket, price) → bool
    computeLotSize(basket, riskSnapshot) → LotSize
}

Implementations:
    ├── FixedStepRecoveryStrategy     (MVP — spec)
    ├── MartingaleRecoveryStrategy    (future)
    ├── EquityScaledRecoveryStrategy  (future)
    └── TimeBasedRecoveryStrategy     (future)
```

### 16.2.3 Take Profit Strategy Plugin

```
interface ITakeProfitStrategy {
    planPartialClose(basket, tpLevel, floatingProfit) → list<CloseCommand>
}

Implementations:
    ├── PercentageRealizationStrategy  (MVP — 33%, 66%)
    ├── FixedLotCloseStrategy          (future)
    └── TrailingTPStrategy             (future — TP OPEN support)
```

### 16.2.4 Risk Model Plugin

```
interface IRiskModel {
    calculateBasketRisk(basket, equity, symbolInfo) → RiskSnapshot
}

Implementations:
    ├── StopLossRiskModel           (MVP)
    ├── VaRRiskModel                (future)
    └── MarginBasedRiskModel        (future)
```

### 16.2.5 Position Selection Strategy

```
interface IPositionRankingStrategy {
    rank(positions, direction) → sorted list
}

Implementations:
    ├── WorstEntryFirstStrategy     (MVP)
    ├── SmallestLotFirstStrategy    (future)
    └── HighestLossFirstStrategy    (future)
```

---

## 16.3 Multi-Symbol / Multi-Account

| Extension | Açıklama |
|-----------|----------|
| Multi-symbol baskets | Cross-symbol hedging — complex, not MVP |
| Multi-account | Single EA instance per account (MVP); future: account router |
| Account-level risk cap | Aggregate risk across all baskets ≤ X% |

### Account-Level Risk Cap (Future)

```
AccountRiskAggregator {
    calculateTotalRisk(allBaskets) → Money
    canOpenNewBasket() → bool
    canOpenRecovery(basket) → bool  // considers account total
}
```

---

## 16.4 TP4 / Trailing / TP OPEN

Spec'te TP4 ve "TP OPEN" var:

```
TakeProfitLevels {
    tp4: optional
    tpOpen: bool  // no fixed TP3, trailing instead
}
```

Future extension:
- `TrailingTakeProfitStrategy` — TP OPEN=true ise TP3 yerine trailing
- TP4 as intermediate level between TP3 and trail

MVP: TP4 stored but not acted upon; TP3 closes all.

---

## 16.5 Notification System

```
interface INotificationService {
    send(alert) → Result
}

Channels:
    ├── TelegramAlertBot     (future)
    ├── WebhookNotifier      (future)
    ├── EmailNotifier        (future)
    └── DesktopPopup         (MT5 native — future)
```

Alert triggers: CRITICAL error, max risk lockout, basket finished P&L.

---

## 16.6 Dashboard & Analytics

```
POST /api/v1/metrics           (future)
GET  /api/v1/dashboard/summary  (future)
```

Metrics:
- Win rate, avg P&L per basket
- Recovery frequency distribution
- Time in state histogram
- Risk utilization

Frontend: Grafana / custom React dashboard reading PostgreSQL.

---

## 16.7 Backtesting Support

**v2'de birinci sınıf.** Bkz. doc 24. `IExecutionEnvironment` ile live/backtest aynı kernel.

---

## 16.8 Configuration Hot-Reload

```
OnTimer: check config file mtime
IF changed: reload non-critical config
    - recovery step, lot size, log level
    - NOT: target_risk for active baskets (immutable per basket)
```

Active basket config snapshot at creation — runtime EA input change active basket'leri etkilemez.

---

## 16.9 Machine Learning Signal Scoring (Far Future)

```
interface ISignalFilter {
    shouldProcess(signal) → bool
    confidenceScore(signal) → float
}
```

Pre-filter low quality signals before basket creation. Requires historical data from PostgreSQL.

---

## 16.10 Feature Flag System

```
FeatureFlags {
    bool ENABLE_RECOVERY_ENGINE
    bool ENABLE_RISK_REDUCTION
    bool ENABLE_BREAK_EVEN
    bool ENABLE_TP2_TP3
    bool ENABLE_REMOTE_SYNC
    bool ENABLE_TRAILING_TP      // future
}
```

Sprint bazlı flag açma — her sprint derlenebilir kalır.

---

## 16.11 Extension Point Registration

```
ExtensionRegistry {
    registerRecoveryStrategy(name, strategy)
    registerTakeProfitStrategy(name, strategy)
    getActive(name, config) → strategy
}
```

Bootstrapper config'den active strategy seçer.

---

## 16.12 API Versioning

```
/api/v1/...  (MVP)
/api/v2/...  (future breaking changes)
```

MT5 client `Accept-Version: v1` header. Backward compatible additions only in v1.

---

## 16.13 Öncelik Matrisi

| Extension | Değer | Karmaşıklık | Öncelik |
|-----------|-------|-------------|---------|
| Trailing TP (TP OPEN) | Yüksek | Orta | P2 |
| Account-level risk cap | Yüksek | Orta | P2 |
| Dashboard/analytics | Orta | Düşük | P2 |
| Notification system | Yüksek | Düşük | P1 (post-MVP) |
| Backtesting adapter | Yüksek | Yüksek | P2 |
| Recovery strategy plugins | Orta | Orta | P3 |
| ML signal filter | Düşük | Yüksek | P4 |
