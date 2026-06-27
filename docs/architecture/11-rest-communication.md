# 11. REST İletişim Akışı

> **Revizyon v2:** REST polling artık mimarinin merkezi değil — **Command ingestion transport adapter**. Fetch → map → enqueue. Bkz. [18-command-queue.md](./18-command-queue.md).

## 11.1 Mimari Prensipler

- MT5 **yalnızca HTTP client** (WebRequest) — server değil
- Python FastAPI **server** — PostgreSQL'e yazar/okur
- REST adapter timer ile fetch eder → **Command Queue'ya enqueue** (polling = transport)
- Command processing ayrı timer loop — REST fetch command loop'u **bloke etmemeli**
- Tüm command'lar **idempotent** (IdempotencyKey)

---

## 11.2 API Endpoints

### Commands (Tercih edilen — v2)

```
GET  /api/v1/commands/pending?account_id=X&since=cursor
POST /api/v1/commands/{command_id}/ack
```

Python sinyal parse sonrası doğrudan command DTO üretir. MT5 yalnızca validate + enqueue.

### Signals (Legacy / geçiş dönemi)

```
GET  /api/v1/signals/pending
POST /api/v1/signals/{signal_id}/ack
```

MT5 tarafında `SignalToCommandMapper` → CreateBasketCommand / ActivateBasketCommand / UpdateSLCommand / UpdateTPCommand / CloseBasketCommand.

### Baskets (Audit Sync)

```
POST /api/v1/baskets/{basket_id}/state
GET  /api/v1/baskets/{basket_id}/history
GET  /api/v1/baskets/active?account_id={id}
```

### Health

```
GET  /api/v1/health
GET  /api/v1/health/ready                   # DB connection check
```

---

## 11.3 GET /signals/pending

**Request:**
```
GET /api/v1/signals/pending?account_id=12345678&since=2026-06-26T14:00:00Z&limit=10
Headers:
  X-API-Key: {api_key}
  Accept: application/json
```

**Response 200:**
```json
{
  "signals": [
    {
      "signal_id": "sig_uuid_001",
      "correlation_key": "XAUUSD_SELL_20260626T143022",
      "sequence": "INITIAL",
      "basket_id": null,
      "symbol": "XAUUSD",
      "direction": "SELL",
      "details": null,
      "received_at": "2026-06-26T14:30:22Z",
      "raw_message_hash": "abc123"
    },
    {
      "signal_id": "sig_uuid_002",
      "correlation_key": "XAUUSD_SELL_20260626T143022",
      "sequence": "DETAILS",
      "basket_id": "basket_uuid_001",
      "symbol": "XAUUSD",
      "direction": "SELL",
      "details": {
        "range_low": 4014.0,
        "range_high": 4017.0,
        "stop_loss": 4020.0,
        "tp1": 4012.0,
        "tp2": 4010.0,
        "tp3": 4008.0,
        "tp4": 4006.0,
        "tp_open": true
      },
      "received_at": "2026-06-26T14:30:45Z"
    }
  ],
  "cursor": "2026-06-26T14:30:45Z"
}
```

---

## 11.4 POST /signals/{id}/ack

**Request:**
```json
{
  "account_id": "12345678",
  "basket_id": "basket_uuid_001",
  "status": "WAIT_DETAILS",
  "processed_at": "2026-06-26T14:30:25Z",
  "mt5_instance_id": "terminal_hash_abc"
}
```

**Response 200:**
```json
{
  "acknowledged": true,
  "signal_id": "sig_uuid_001"
}
```

**Idempotency:** Aynı signal_id için tekrar ack → 200 (no-op).

---

## 11.5 POST /baskets/{id}/state (Audit Sync)

**Request:**
```json
{
  "account_id": "12345678",
  "lifecycle_state": "ACTIVE",
  "modes": {
    "recovery_active": false,
    "max_risk_lockout": false
  },
  "risk_snapshot": {
    "current_risk_usd": 85.50,
    "current_risk_pct": 0.855,
    "target_risk_usd": 100.00,
    "max_risk_usd": 120.00
  },
  "open_positions": 3,
  "realized_profit_usd": 0.0,
  "event": "SIGNAL_DETAILS_RECEIVED",
  "timestamp": "2026-06-26T14:30:50Z"
}
```

Debounced: state değişimlerinde gönderilir, max 1/5 sn basket başına.

---

## 11.6 MT5 REST Adapter (v2)

```
RestCommandSourceAdapter implements ICommandSource {
    fetchPending():
        GET /commands/pending (or /signals/pending + mapper)
        FOR each dto: commandQueue.enqueue(mapped)  // idempotent
        POST ack per item
}

RestClient { ... }   // unchanged HTTP wrapper
RestRemoteStateSync  // audit — subscribes domain events
```

**Kaldırıldı (v1):** `RestSignalRepository` doğrudan use case çağırması. Artık yalnızca command enqueue.

---

## 11.7 Ingestion Timer (Transport — ayrı loop)

```
OnTimer(slow, 3 sec):   // AYRI — command loop'u bloke etmez
    IF restCircuitBreaker.open: SKIP
    IF fetchInFlight: SKIP
    commands = restAdapter.fetchPending()
    FOR each: commandQueue.enqueue()   // IdempotencyKey dedup
    ack to API

OnTimer(fast, 100ms):   // Command + trade processing
    commandProcessor.processBatch()
    eventBus.drainQueue()
    tradeExecutor.processBatch()
```

Interval'lar **execution profile**'dan (doc 23).

---

## 11.8 Hata Kodları ve MT5 Davranışı

| HTTP | Anlam | MT5 Aksiyonu |
|------|-------|--------------|
| 200 | OK | Process |
| 204 | No pending | Skip |
| 401 | Auth fail | Log CRITICAL, stop polling |
| 404 | Not found | Log ERROR, skip signal |
| 409 | Conflict (duplicate basket) | Log WARN, ack anyway |
| 429 | Rate limit | Backoff |
| 500 | Server error | Retry with backoff |
| Timeout | Network | Retry, local state unaffected |

---

## 11.9 Signal Ordering Guarantees

Python tarafı garantiler:
1. Aynı `correlation_key` için `INITIAL` her zaman `DETAILS`'den önce insert edilir
2. `received_at` monotonic
3. Duplicate Telegram mesajları → dedup by `raw_message_hash`

MT5 tarafı:
1. DETAILS geldi ama basket yok → queue'da tut, 30 sn bekle, sonra ERROR log
2. INITIAL geldi, basket zaten var (same correlation_key) → idempotent skip

---

## 11.10 Python Parser — Correlation Key

```
correlation_key = f"{symbol}_{direction}_{channel_id}_{date}_{message_group_id}"
```

Telegram'da ardışık mesajlar aynı group_id'ye sahip olabilir. Parser:
- Signal #1: yeni group → INITIAL
- Signal #2: aynı group + details pattern → DETAILS

**Fallback:** Metin başlığı eşleştirme ("Gold Sell Now") — yalnızca group_id yoksa.

---

## 11.11 PostgreSQL Schema (Özet)

```sql
-- signals
CREATE TABLE signals (
    signal_id UUID PRIMARY KEY,
    correlation_key VARCHAR(128) NOT NULL,
    sequence VARCHAR(16) NOT NULL,  -- INITIAL, DETAILS
    basket_id UUID,
    account_id BIGINT,
    symbol VARCHAR(32),
    direction VARCHAR(8),
    details JSONB,
    status VARCHAR(16) DEFAULT 'PENDING',  -- PENDING, CONSUMED, FAILED
    raw_message TEXT,
    raw_message_hash VARCHAR(64) UNIQUE,
    received_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    mt5_instance_id VARCHAR(64)
);

-- basket_audit
CREATE TABLE basket_audit (
    id BIGSERIAL PRIMARY KEY,
    basket_id UUID NOT NULL,
    account_id BIGINT NOT NULL,
    lifecycle_state VARCHAR(32),
    modes JSONB,
    risk_snapshot JSONB,
    event VARCHAR(64),
    payload JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 11.12 Security

| Katman | Önlem |
|--------|-------|
| Transport | HTTPS only |
| Auth | API key per account + IP whitelist (optional) |
| Rate limit | 60 req/min per account |
| Input validation | Pydantic models, symbol whitelist |
| Replay | signal_id + consumed flag |
| Audit | All state changes logged |

---

## 11.13 REST vs Direct DB

| | REST Polling | Direct DB |
|---|-------------|-----------|
| MQL5 uyumu | ✅ WebRequest | ❌ No native driver |
| Latency | 2-5 sec | Sub-sec |
| Decoupling | ✅ | ❌ |
| Testability | ✅ Mock server | ❌ |
| **Karar** | ✅ REST | ❌ |

2-5 sn latency bu strateji için kabul edilebilir — Signal #2 genelde saniyeler-dakikalar içinde gelir.
