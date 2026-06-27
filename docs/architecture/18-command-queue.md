# 18. Command Queue Mimarisi

> **Revizyon:** v2 — Polling-centric model kaldırıldı. Tüm dış girdiler ve iç operasyonlar **Command** olarak modellenir.

## 18.1 Tasarım Prensibi

Eski modelde REST polling → use case doğrudan çağrısı vardı. Yeni modelde:

```
Transport (REST poll / backtest replay / manual inject)
    → Signal-to-Command Mapper
    → Command Queue (persistent, ordered, idempotent)
    → Command Handler Registry
    → Domain logic (state change intent)
    → Trade Request Queue (ayrı — bkz. doc 21)
    → Trade Executor
```

**Polling artık bir transport detayıdır**, mimarinin merkezi değil. REST adapter periyodik olarak API'den sinyal çeker ve **Command enqueue eder**; iş mantığı Command Handler'larda çalışır.

---

## 18.2 Command Hiyerarşisi

### External Commands (Sinyal / Operatör kaynaklı)

| Command | Kaynak | Açıklama |
|---------|--------|----------|
| `CreateBasketCommand` | Signal #1 | Yeni sepet + 3 initial pozisyon intent |
| `ActivateBasketCommand` | Signal #2 | SL, TP, range uygula → ACTIVE |
| `UpdateSLCommand` | Signal / operatör | Mevcut sepet SL güncelle |
| `UpdateTPCommand` | Signal / operatör | TP seviyelerini güncelle |
| `CloseBasketCommand` | Signal / operatör / timeout | Tüm pozisyonları kapat, FINISHED |

### Internal Commands (Domain motorları tarafından üretilir)

| Command | Üreten | Açıklama |
|---------|--------|----------|
| `OpenRecoveryPositionCommand` | Recovery handler | 1 recovery pozisyon intent |
| `ReduceRiskCloseCommand` | Risk reduction handler | Worst entry kapatma intent |
| `ExecuteTPPartialCloseCommand` | TP handler | TP1/TP2 partial close plan |
| `ActivateBreakEvenCommand` | BE handler | SL sync intent |
| `CloseAllPositionsCommand` | TP3 / emergency | Toplu kapatma intent |

**Kural:** Internal command'lar da aynı queue'dan geçer — tek işlem hattı, audit trail tutarlılığı.

---

## 18.3 Command Yapısı

```
Command {
    CommandId          id              // UUID; external: derived from signal_id
    CommandType        type
    IdempotencyKey     key             // dedup anahtarı
    BasketId           basketId        // nullable for CreateBasket
    CorrelationKey     correlationKey
    datetime           enqueuedAt
    CommandStatus      status          // PENDING | PROCESSING | COMPLETED | FAILED | DEAD_LETTER
    int                retryCount
    int                priority        // external=10, internal=5, emergency=100
    string             payloadJson     // type-specific params
    string             source          // REST | BACKTEST | MANUAL | INTERNAL
}
```

### IdempotencyKey Kuralları

| Command | IdempotencyKey |
|---------|----------------|
| `CreateBasketCommand` | `create:{signal_id}` |
| `ActivateBasketCommand` | `activate:{signal_id}` |
| `UpdateSLCommand` | `update_sl:{signal_id}:{sl_price}` |
| `UpdateTPCommand` | `update_tp:{signal_id}:{tp_hash}` |
| `CloseBasketCommand` | `close:{basket_id}:{reason}` |
| `OpenRecoveryPositionCommand` | `recovery:{basket_id}:step_{n}` |
| `ReduceRiskCloseCommand` | `reduce:{basket_id}:{ticket}:{sequence}` |
| `ExecuteTPPartialCloseCommand` | `tp:{basket_id}:{tp_level}:{plan_hash}` |

**Duplicate enqueue:** Aynı `IdempotencyKey` + status COMPLETED → no-op, return success.  
**Duplicate enqueue + FAILED:** Config'e göre retry veya dead letter.

---

## 18.4 Command Queue Bileşenleri

```
ICommandQueue
    enqueue(command) → Result
    dequeueNext() → Command | null        // priority + FIFO within priority
    markCompleted(commandId) → Result
    markFailed(commandId, error) → Result
    getByIdempotencyKey(key) → Command | null

ICommandHandlerRegistry
    register(type, handler)
    dispatch(command) → Result

ICommandPersistence
    save(command) → Result               // her state change
    loadPending() → list<Command>
    loadCompleted(since) → list<Command> // audit
```

### Handler Contract

```
ICommandHandler {
    canHandle(command) → bool
    handle(command, context) → Result<list<DomainEvent>>
}
```

Handler **doğrudan trade yapmaz** — `TradeRequest` üretir ve Trade Request Queue'ya ekler (doc 21).

---

## 18.5 Signal → Command Mapping

Python REST API sinyal formatı değişmez; MT5 tarafında mapper:

```
SignalDto (sequence=INITIAL)  → CreateBasketCommand
SignalDto (sequence=DETAILS)  → ActivateBasketCommand
                               (+ UpdateSLCommand / UpdateTPCommand if partial update signal)

SignalDto (type=CLOSE)        → CloseBasketCommand       // future
SignalDto (type=UPDATE_SL)    → UpdateSLCommand          // future
```

REST Ingestion Adapter (eski "PollSignalsUseCase"):

```
OnTimer:
    signals = REST GET /commands/pending   // or /signals/pending mapped
    FOR each signal:
        commands = SignalToCommandMapper.map(signal)
        FOR each command:
            commandQueue.enqueue(command)   // idempotent
        REST POST ack(signal_id)
    
    commandProcessor.processBatch(maxBatchSize)
```

---

## 18.6 Command Processing Loop

```
CommandProcessor {
    processBatch(maxCount):
        FOR i = 1 to maxCount:
            cmd = commandQueue.dequeueNext()
            IF cmd == null: BREAK
            
            IF idempotency check fails (already completed): CONTINUE
            
            commandQueue.markProcessing(cmd)
            
            result = handlerRegistry.dispatch(cmd)
            
            IF result.ok:
                eventBus.publishAll(result.events)
                commandQueue.markCompleted(cmd)
            ELSE IF retryable:
                commandQueue.markFailed(cmd, retry=true)
            ELSE:
                commandQueue.markFailed(cmd, retry=false)
                deadLetterQueue.add(cmd)
                eventBus.publish(CommandFailedEvent)
}
```

**Single-threaded:** MQL5 kısıtı — aynı anda tek command PROCESSING.

---

## 18.7 Priority ve Ordering

| Priority | Command Types |
|----------|---------------|
| 100 | `CloseBasketCommand`, emergency |
| 50 | `ActivateBasketCommand`, `UpdateSLCommand` |
| 30 | `CreateBasketCommand` |
| 20 | TP / BE internal commands |
| 10 | Recovery, risk reduction |

Aynı basket için **serialization guarantee:** aynı `basket_id`'ye ait command'lar FIFO (priority tie-break: enqueuedAt).

---

## 18.8 Persistence

Command queue local JSON'da persist edilir (doc 12):

```
MQL5/Files/BasketRecovery/commands/
├── pending.json
├── processing.json       // crash recovery: requeue on restart
├── completed.jsonl       // append-only audit
└── dead_letter.json
```

Restart sonrası `processing.json` içindeki command'lar → `pending`'e requeue (at-least-once semantics).

---

## 18.8 REST API Evrimi (Önerilen)

Mevcut `/signals/pending` korunabilir; ideal evrim:

```
GET  /api/v1/commands/pending?account_id=X   // pre-mapped commands from Python
POST /api/v1/commands/{id}/ack
```

Python tarafında sinyal parse sonrası doğrudan command DTO üretmek mapper karmaşıklığını MT5'ten Python'a taşır — **tercih edilen production yaklaşım**.

---

## 18.9 Polling vs Command Queue — Net Ayrım

| Katman | Sorumluluk |
|--------|------------|
| REST Ingestion Adapter | Transport; timer ile fetch; command enqueue |
| Command Queue | Ordering, idempotency, persistence, retry |
| Command Handlers | Domain logic; event publish |
| Event Bus | Modüller arası iletişim (doc 19) |
| Trade Request Queue | Broker emir intent (doc 21) |

**Polling kaldırılmadı** — transport mekanizması olarak kaldı. **Mimari merkezi Command Queue'dur.**
