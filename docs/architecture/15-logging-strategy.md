# 15. Loglama Stratejisi (Logging)

## 15.1 Loglama Prensipleri

1. **Structured logging** — JSON Lines format, parse-friendly
2. **Correlation ID** — her log satırında `basket_id` (varsa)
3. **Severity levels** — TRACE, DEBUG, INFO, WARN, ERROR, CRITICAL
4. **No sensitive data** — API key, account password asla loglanmaz
5. **Performance** — log write async buffer (flush on timer/deinit)
6. **Audit trail** — state transitions, trades, signal processing ayrı kategori

---

## 15.2 Log Format

```json
{
  "ts": "2026-06-26T14:30:25.123Z",
  "level": "INFO",
  "category": "SIGNAL",
  "event": "SIGNAL_PROCESSED",
  "account_id": 12345678,
  "basket_id": "550e8400-e29b-41d4-a716-446655440000",
  "correlation_key": "XAUUSD_SELL_20260626T143022",
  "signal_id": "sig_uuid_001",
  "details": {
    "sequence": "INITIAL",
    "symbol": "XAUUSD",
    "direction": "SELL"
  },
  "mt5_instance": "terminal_abc"
}
```

---

## 15.3 Log Kategorileri

| Category | İçerik |
|----------|--------|
| `SYSTEM` | OnInit, OnDeinit, config load, recovery |
| `SIGNAL` | Poll, receive, ack, parse errors |
| `BASKET` | Create, state transition, finish |
| `TRADE` | Open, close, modify — ticket, lot, price, retcode |
| `RISK` | Risk snapshot, reduction, max lockout |
| `RECOVERY` | Trigger, open, blocked |
| `TP` | TP1/2/3 trigger, partial close plan |
| `BE` | Break-even activation, SL sync |
| `PERSIST` | Save, load, archive, errors |
| `REST` | HTTP request/response (no API key) |
| `RECONCILE` | Restart recovery details |

---

## 15.4 ILogger Port

```
interface ILogger {
    trace(category, event, basketId, details)
    debug(category, event, basketId, details)
    info(category, event, basketId, details)
    warn(category, event, basketId, details, errorCode)
    error(category, event, basketId, details, errorCode)
    critical(category, event, basketId, details, errorCode)
    
    flush()  // force write buffer
}
```

### S0.1 — Async Logging Port'ları (interface only)

Buffering henüz implement edilmedi. Sprint 15'te `CFileLogger` async adapter'a geçecek:

```
interface ILogBuffer {
    enqueue(line) → bool
    count() → int
    tryDequeue(out line) → bool
    clear()
}

interface IAsyncLogWriter {
    initialize(filePath) → bool
    submit(line) → bool
    flushPending()
    buffer() → ILogBuffer*
}
```

MVP (S0–S0.1): `CFileLogger` senkron `ILogger` implementasyonu aktif kalır.

---

## 15.5 Log Sinks

| Sink | Kullanım | MVP |
|------|----------|-----|
| `FileLogger` | Primary — rotating files | ✅ |
| `TerminalLogger` | Print (debug mode only) | ✅ optional |
| `RemoteLogSink` | POST to API / external | ❌ Phase 2 |

### File Rotation

```
MQL5/Files/BasketRecovery/logs/
├── basket_recovery_2026-06-26.log       # current day
├── basket_recovery_2026-06-25.log       # previous
└── ...
```

Rotation: daily, max 30 files, max 50 MB per file.

---

## 15.6 Log Level Configuration

```
EA Input: LogLevel = INFO (default)

Production:  INFO
Development: DEBUG
Debugging:   TRACE (performance impact — tick-level logs)
```

Category-level override (config file):
```json
{
  "log_level": "INFO",
  "category_overrides": {
    "REST": "DEBUG",
    "RISK": "TRACE"
  }
}
```

---

## 15.7 Mandatory Log Events

Her zaman loglanması gereken event'ler:

| Event | Level | Category |
|-------|-------|----------|
| EA init/deinit | INFO | SYSTEM |
| Config loaded | INFO | SYSTEM |
| Restart recovery summary | INFO | RECONCILE |
| Signal received | INFO | SIGNAL |
| Signal ack sent/failed | INFO/WARN | SIGNAL |
| Basket created | INFO | BASKET |
| State transition | INFO | BASKET |
| Trade open/close/modify | INFO | TRADE |
| Recovery triggered/blocked | INFO/WARN | RECOVERY |
| Risk max lockout | WARN | RISK |
| TP triggered | INFO | TP |
| Break-even activated | INFO | BE |
| Basket finished (P&L summary) | INFO | BASKET |
| Any ERROR/CRITICAL | ERROR/CRITICAL | (respective) |

---

## 15.8 Trade Log Detail

```json
{
  "event": "TRADE_OPEN",
  "details": {
    "ticket": 123456789,
    "symbol": "XAUUSD",
    "direction": "SELL",
    "lot": 0.01,
    "price": 4015.50,
    "sl": 4020.0,
    "tp": 0.0,
    "retcode": 10009,
    "comment": "BR:abc123:I0",
    "command_id": "cmd_uuid",
    "latency_ms": 45
  }
}
```

---

## 15.9 Performance Considerations

```
LogBuffer {
    string[] buffer
    int maxBufferSize = 100
    
    write(entry):
        IF buffer.size >= maxBufferSize: flush()
        buffer.add(entry)
    
    flush():
        write all to file
        clear buffer
}
```

Flush triggers:
- Buffer full
- OnTimer (every 1 sec)
- OnDeinit
- CRITICAL/ERROR (immediate flush)

**OnTick'te log yazma:** TRACE level hariç yasak. Tick dispatcher yalnızca event oluştuğunda log yazar.

---

## 15.10 Basket Finish Summary Log

```
{
  "event": "BASKET_FINISHED",
  "details": {
    "duration_seconds": 3600,
    "total_realized_profit_usd": 45.50,
    "initial_positions": 3,
    "recovery_count": 2,
    "partial_closes": 4,
    "break_even_activated": true,
    "max_risk_reached": false,
    "final_state": "FINISHED",
    "state_transitions": 6
  }
}
```

Bu log analytics ve strateji değerlendirme için kritik.

---

## 15.11 Log ↔ Audit Sync

Remote audit (PostgreSQL) ve local log complementer:
- Log: granular, high-volume, local
- Audit: state transitions, risk snapshots, structured for querying

Duplicate değil — log operasyonel debug, audit business analytics.

---

## 15.12 Python Service Logging

Python tarafı aynı JSON Lines format:
- `correlation_id` = correlation_key
- Signal parse, DB write, API request log
- Structured with Python `structlog` or `logging` JSON formatter

Cross-system trace: `signal_id` + `basket_id` + `correlation_key` üçlüsü.
