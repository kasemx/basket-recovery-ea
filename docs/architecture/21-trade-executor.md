# 21. Trade Executor

> **Revizyon:** v2 — Projede broker API çağıran **tek sınıf**. Tüm diğer modüller yalnızca `TradeRequest` üretir.

## 21.1 Mutlak Kural

```
╔══════════════════════════════════════════════════════════════╗
║  Yalnızca TradeExecutor şu MT5 API'lerini çağırabilir:      ║
║    • OrderSend / CTrade.Open                                 ║
║    • OrderModify / CTrade.PositionModify                     ║
║    • OrderClose / CTrade.PositionClose                       ║
║  Ba başka hiçbir sınıf, use case, handler veya adapter YOK.  ║
╚══════════════════════════════════════════════════════════════╝
```

Static analysis / code review checklist'te zorunlu madde. CI'da grep rule: `OrderSend|OrderClose|OrderModify` yalnızca `TradeExecutor.mqh` içinde.

---

## 21.2 TradeRequest vs Command

| | Command | TradeRequest |
|---|---------|--------------|
| **Katman** | Application/domain intent | Infrastructure boundary DTO |
| **Örnek** | CreateBasketCommand | OpenMarketRequest |
| **Queue** | Command Queue | Trade Request Queue |
| **Handler** | Command Handler | Trade Executor |

Command handler trade yapmaz → `TradeRequest` enqueue eder.

---

## 21.3 TradeRequest Tipleri

```
TradeRequest (abstract)
├── OpenMarketRequest       { basketId, symbol, direction, lot, comment, sl, tp }
├── ClosePositionRequest    { basketId, ticket, lot (optional partial) }
├── ModifyStopLossRequest   { basketId, ticket, newSL }
├── ModifyTakeProfitRequest { basketId, ticket, newTP }
└── CloseAllRequest         { basketId, tickets[] }
```

```
TradeRequest {
    RequestId       id
    IdempotencyKey  key
    RequestType     type
    BasketId        basketId
    datetime        createdAt
    int             retryCount
    int             priority
    RequestStatus   status   // QUEUED | EXECUTING | FILLED | REJECTED | CANCELLED
}
```

---

## 21.4 Trade Executor Tasarımı

```
TradeExecutor implements ITradeExecutor {
    -ITradeRequestQueue queue
    -IPositionSnapshotStore snapshotStore
    -IEventBus eventBus
    -ILogger logger
    -TradeExecutorConfig config    // slippage, magic, retry
    
    processNext():
        request = queue.dequeue()
        IF request == null: RETURN
        
        queue.markExecuting(request)
        
        result = SWITCH request.type:
            OpenMarketRequest    → executeOpen(request)
            ClosePositionRequest → executeClose(request)
            ModifyStopLossRequest→ executeModifySL(request)
            ...
        
        IF result.ok:
            queue.markFilled(request)
            snapshotStore.applyTransaction(result.transaction)
            eventBus.publish(mapToDomainEvent(result))
        ELSE IF retryable:
            queue.requeue(request, backoff)
        ELSE:
            queue.markRejected(request)
            eventBus.publish(TradeRequestRejected{...})
    
    processBatch(maxCount):
        FOR i = 1 to maxCount: processNext()
}
```

---

## 21.5 Execution Flow

```
Command Handler
    → TradeRequestQueue.enqueue(OpenMarketRequest)
    
OnTimer / OnTradeTransaction:
    TradeExecutor.processBatch(5)
    
OnTradeTransaction (from MT5):
    TradeTransactionNormalizer.normalize(trans)
    → PositionSnapshotStore.applyTransaction(normalized)
    → EventBus.publish(PositionSnapshotUpdated)
    → (TradeExecutor correlates pending request → markFilled)
```

---

## 21.6 Idempotency

| Request | IdempotencyKey |
|---------|----------------|
| Open (initial #0) | `open:{basketId}:initial:0` |
| Open (recovery step 3) | `open:{basketId}:recovery:3` |
| Close ticket 123 | `close:{basketId}:123` |
| Modify SL ticket 123 | `modsl:{basketId}:123:{sl_price}` |

Duplicate enqueue with FILLED status → skip, publish existing result event.

---

## 21.7 Retry ve Slippage

```
TradeExecutorConfig {
    int maxRetries           // default 3
    int slippagePoints
    int executionTimeoutMs
    bool partialCloseAllowed
    RetryPolicy retryPolicy  // from profile
}
```

Broker retcode mapping:
- `TRADE_RETCODE_REQUOTE` → retry
- `TRADE_RETCODE_REJECT` → reject, no retry
- `TRADE_RETCODE_NO_MONEY` → reject, publish MaxRisk/BasketError

---

## 21.8 Simulated Trade Executor (Backtest)

```
SimulatedTradeExecutor implements ITradeExecutor {
    -ISimulatedFillModel fillModel
    -IPositionSnapshotStore snapshotStore
    
    // OrderSend/Modify/Close YOK — fill model ile anında doldur
    processNext():
        request = queue.dequeue()
        fill = fillModel.simulate(request, currentBar)
        snapshotStore.applyTransaction(fill.transaction)
        eventBus.publish(...)
}
```

Aynı `ITradeExecutor` port — live ve backtest aynı queue + snapshot pipeline.

---

## 21.9 Trade Request Queue Persistence

Command queue ile birlikte persist (doc 12):

```
MQL5/Files/BasketRecovery/trade_requests/
├── queued.json
├── executing.json
└── completed.jsonl
```

Restart: executing → requeue; TradeExecutor + SnapshotStore reconcile with broker.

---

## 21.10 Eski ITradeGateway Kaldırıldı

v1'deki `ITradeGateway` / `Mt5TradeGateway` → **`ITradeExecutor` + `Mt5TradeExecutor`** (extends TradeExecutor).

Diğer modüller `ITradeExecutor`'a erişemez — yalnızca `ITradeRequestQueue` enqueue port'una erişir.

```
Command Handler → ITradeRequestQueue (port)
TradeExecutor   → ITradeExecutor (concrete, composition root only)
```

---

## 21.11 Event Mapping (Executor → Domain)

| Trade Result | Domain Event |
|--------------|--------------|
| Open filled | `InitialPositionsOpened` or `RecoveryPositionOpened` |
| Close filled | `PositionClosed` |
| SL modified | `PositionStopLossModified` |
| All closed | `AllPositionsClosed` |
| Rejected | `TradeRequestRejected` → may trigger `CommandFailed` |
