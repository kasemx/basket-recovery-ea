# 19. Event Bus Mimarisi

> **Revizyon:** v2 — Modüller arası doğrudan çağrı yasak. Tüm iletişim domain event'ler üzerinden.

## 19.1 Tasarım Prensibi

Eski modelde `BasketOrchestrator` use case'leri doğrudan çağırıyordu. Yeni model:

```
Command Handler → publish(DomainEvent)
Event Bus → dispatch to subscribed handlers
Event Handler → enqueue new Command(s) OR update read models
```

**Orchestrator ince bir event loop'a indirgenir** — command process + event dispatch.

---

## 19.2 IEventBus Port

```
IEventBus {
    publish(event) → void
    publishAll(events[]) → void
    subscribe(eventType, handler) → SubscriptionId
    unsubscribe(subscriptionId) → void
    clearAll() → void   // test only
}

IEventHandler {
    handle(event) → Result
    handledEventType() → EventType
    priority() → int    // lower = earlier
}
```

Implementation: `InMemoryEventBus` (sync dispatch, single-threaded).

---

## 19.3 Domain Event Katalogu

### Basket Lifecycle Events

| Event | Publisher | Payload |
|-------|-----------|---------|
| `BasketCreated` | CreateBasketHandler | basketId, symbol, direction, correlationKey |
| `BasketActivated` | ActivateBasketHandler | basketId, sl, tpLevels, baselineRisk |
| `BasketDetailsUpdated` | UpdateSL/TP handlers | basketId, changed fields |
| `BasketClosing` | CloseBasketHandler | basketId, reason |
| `BasketFinished` | CloseAllHandler | basketId, realizedPnL, duration |
| `BasketError` | Any handler on failure | basketId, errorCode, recoverable |

### Position Events

| Event | Publisher | Payload |
|-------|-----------|---------|
| `InitialPositionsOpened` | TradeExecutor (via snapshot) | basketId, tickets[], count |
| `RecoveryPositionOpened` | TradeExecutor | basketId, ticket, stepIndex |
| `PositionClosed` | TradeExecutor | basketId, ticket, realizedProfit |
| `PositionStopLossModified` | TradeExecutor | basketId, ticket, newSL |
| `PositionSnapshotUpdated` | SnapshotStore | basketId, snapshotVersion |

### Risk Events

| Event | Publisher | Payload |
|-------|-----------|---------|
| `RiskSnapshotCalculated` | RiskEventHandler | basketId, riskSnapshot |
| `TargetRiskReached` | RiskEventHandler | basketId, currentRisk, targetRisk |
| `MaxRiskReached` | RiskEventHandler | basketId, lockout=true |
| `RiskReduced` | ReduceRiskHandler | basketId, closedTicket, newRisk |

### Recovery Events

| Event | Publisher | Payload |
|-------|-----------|---------|
| `RecoveryStepCrossed` | PriceMonitorHandler | basketId, stepIndex, price |
| `RecoveryBlocked` | RecoveryHandler | basketId, reason, projectedRisk |
| `RecoveryPermanentlyDisabled` | BreakEvenHandler | basketId |

### Take Profit Events

| Event | Publisher | Payload |
|-------|-----------|---------|
| `TP1Reached` | PriceMonitorHandler | basketId, price, floatingProfit |
| `TP1PartialCloseCompleted` | TPHandler | basketId, realizedAmount, remainingCount |
| `TP2Reached` | PriceMonitorHandler | basketId, price |
| `TP2PartialCloseCompleted` | TPHandler | basketId, realizedAmount |
| `TP3Reached` | PriceMonitorHandler | basketId, price |

### Break-Even Events

| Event | Publisher | Payload |
|-------|-----------|---------|
| `BreakEvenEligible` | RiskEventHandler | basketId, realizedProfit, threshold |
| `BreakEvenActivated` | BEHandler | basketId, breakEvenSL, avgEntry |
| `BreakEvenStopLossSynced` | BEHandler | basketId, syncedCount |

### State Machine Events

| Event | Publisher | Payload |
|-------|-----------|---------|
| `StateTransitioned` | TransitionEngine | basketId, from, to, triggerEvent |
| `TransitionRejected` | TransitionEngine | basketId, currentState, rejectedEvent, reason |

### System Events

| Event | Publisher | Payload |
|-------|-----------|---------|
| `CommandProcessed` | CommandProcessor | commandId, type, durationMs |
| `CommandFailed` | CommandProcessor | commandId, errorCode |
| `RestartRecoveryCompleted` | RecoveryUseCase | basketsRecovered, orphans |

---

## 19.4 Event Handler Subscription Map

```
BasketCreated
    → StateTransitionHandler        (→ PENDING_OPEN)
    → PersistenceHandler            (save basket)
    → AuditSyncHandler              (remote sync)

InitialPositionsOpened
    → StateTransitionHandler        (→ WAIT_DETAILS)
    → PositionSnapshotInitHandler

BasketActivated
    → StateTransitionHandler        (→ ACTIVE)
    → RiskEvaluationHandler         (→ enqueue EvaluateRiskCommand)
    → PersistenceHandler

TargetRiskReached
    → RiskReductionEvaluationHandler  (favorable price check → maybe enqueue ReduceRisk)

RecoveryStepCrossed
    → RecoveryEvaluationHandler     (→ maybe enqueue OpenRecovery)

TP1Reached
    → TP1CommandEnqueueHandler      (→ ExecuteTPPartialCloseCommand)

BreakEvenEligible
    → BreakEvenCommandEnqueueHandler

BreakEvenActivated
    → RecoveryDisableHandler
    → StateTransitionHandler        (→ BREAK_EVEN)

PositionSnapshotUpdated
    → RiskEvaluationHandler         (re-read snapshot, publish RiskSnapshotCalculated)

BasketFinished
    → CleanupHandler
    → AuditSyncHandler
    → MetricsHandler
```

---

## 19.5 Event Processing Kuralları

1. **Sync dispatch:** Handler'lar publish çağrısı içinde sırayla çalışır (MQL5 single-thread).
2. **Handler isolation:** Bir handler fail ederse diğerleri çalışmaya devam eder; failure loglanır.
3. **No circular events:** Handler A → event → Handler B → event → Handler A **yasak**. Command queue ara katman.
4. **Reentrancy guard:** Event handler command enqueue edebilir; command processor reentrant değil (processing flag).
5. **Event ordering:** Aynı basket için event'ler timestamp + sequence number ile sıralı.

---

## 19.6 Event vs Command Ayrımı

| | Command | Event |
|---|---------|-------|
| **Yön** | Intent (ne yapılmalı) | Fact (ne oldu) |
| **Tüketim** | Single handler | Multiple subscribers |
| **Idempotency** | Zorunlu | At-least-once OK (handler idempotent olmalı) |
| **Persist** | Evet (queue) | Audit log (optional) |
| **Örnek** | CreateBasketCommand | BasketCreated |

**Akış:** Command handled → Event(s) published → Event handlers → new Command(s) (if needed)

---

## 19.7 Event Store (Audit)

Production observability için append-only event log:

```
MQL5/Files/BasketRecovery/events/
└── {date}.jsonl

{ "ts", "event_type", "basket_id", "payload", "correlation_id" }
```

Remote sync: batch POST `/api/v1/baskets/{id}/events`

Event store restart replay için **kullanılmaz** — command queue + snapshot store yeterli. Event store = audit/analytics.

---

## 19.8 Test Stratejisi

```
Test:
    bus = InMemoryEventBus()
    captured = []
    bus.subscribe(BasketCreated, e => captured.add(e))
    handler.handle(CreateBasketCommand)
    assert captured.size == 1
```

Event bus sayesinde modüller izole test edilir — mock event publish/subscribe.

---

## 19.9 Yasak Bağımlılıklar

```
❌ RecoveryHandler → RiskCalculator.doCalculate()     (direct)
✅ RecoveryHandler → publish(RecoveryStepCrossed)     (event)
✅ RiskEvaluationHandler subscribes → reads snapshot → publish(TargetRiskReached)

❌ TPHandler → TradeExecutor.close()                  (direct)
✅ TPHandler → enqueue(ExecuteTPPartialCloseCommand)
✅ CommandHandler → TradeRequestQueue → TradeExecutor
```
