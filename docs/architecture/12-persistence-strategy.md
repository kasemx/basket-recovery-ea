# 12. Kalıcılık Stratejisi (Persistence)

## 12.1 Dual-Layer Persistence

```
Layer 1: Local File (Primary — restart recovery)
    → Hızlı, MT5 native, network bağımsız
    
Layer 2: Remote REST → PostgreSQL (Secondary — audit/observability)
    → Async, debounced, failure tolerant
```

**Source of Truth:**
- **Açık pozisyonlar:** Broker (MT5 terminal)
- **Basket runtime state:** Local JSON files
- **Signal history:** PostgreSQL
- **Audit trail:** PostgreSQL

---

## 12.2 Local State Storage

### Dosya Konumu

```
MQL5/Files/BasketRecovery/
├── state/
│   ├── account_{accountId}_basket_{basketId}.json    # active baskets
│   └── ...
├── archive/
│   └── account_{accountId}_basket_{basketId}_{date}.json  # finished
├── commands/
│   └── pending_commands.json                          # idempotent command queue
└── cursor/
    └── signal_poll_cursor.json                        # last poll timestamp
```

### Atomic Write Pattern

```
AtomicFileWriter.write(path, content):
    1. tempPath = path + ".tmp"
    2. write content to tempPath
    3. flush
    4. FileMove(tempPath → path)   // atomic on same volume
    5. on failure: temp file remains, retry
```

---

## 12.3 Basket State JSON Schema

```json
{
  "schema_version": 1,
  "basket_id": "550e8400-e29b-41d4-a716-446655440000",
  "correlation_key": "XAUUSD_SELL_20260626T143022",
  "account_id": 12345678,
  "symbol": "XAUUSD",
  "direction": "SELL",
  "magic_number": 202606001,
  
  "lifecycle_state": "ACTIVE",
  "modes": {
    "recovery_active": false,
    "risk_reduction_active": false,
    "max_risk_lockout": false,
    "recovery_permanently_disabled": false
  },
  
  "risk_profile": {
    "target_risk_pct": 1.0,
    "max_risk_pct": 1.2
  },
  "recovery_config": {
    "step_pips": 0.2,
    "lot_size": 0.01,
    "max_steps": 50
  },
  
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
  
  "positions": [
    {
      "ticket": 123456789,
      "entry_price": 4015.50,
      "lot": 0.01,
      "stop_loss": 4020.0,
      "role": "INITIAL",
      "recovery_step": null,
      "is_closed": false
    }
  ],
  
  "runtime": {
    "realized_profit_usd": 0.0,
    "last_recovery_step_index": 0,
    "last_recovery_anchor_price": 4015.50,
    "break_even_stop_loss": null,
    "break_even_activated": false,
    "tp_triggered": { "tp1": false, "tp2": false, "tp3": false },
    "initial_position_count": 3
  },
  
  "state_history": [
    {
      "from": "WAIT_DETAILS",
      "to": "ACTIVE",
      "at": "2026-06-26T14:30:50Z",
      "trigger": "SIGNAL_DETAILS_RECEIVED"
    }
  ],
  
  "created_at": "2026-06-26T14:30:25Z",
  "updated_at": "2026-06-26T14:30:50Z"
}
```

---

## 12.4 Persist Trigger Points

| Event | Local | Remote |
|-------|-------|--------|
| Basket created | ✅ sync | ✅ async |
| State transition | ✅ sync | ✅ async |
| Recovery opened | ✅ sync | ✅ async |
| Partial close | ✅ sync | ✅ async |
| Break-even activated | ✅ sync | ✅ async |
| Command enqueued | ✅ sync | ❌ |
| Timer heartbeat (30s) | ❌ | ✅ async (metrics) |
| Basket finished | ✅ archive + delete active | ✅ async |

### Debounce

Remote sync debounce: basket başına max 1 request / 5 saniye.  
Local persist: state değişiminde anında (debounce yok).

---

## 12.5 Command Queue Persistence

Idempotency için pending commands persist edilir:

```json
{
  "pending": [
    {
      "command_id": "cmd_uuid",
      "basket_id": "basket_uuid",
      "type": "OPEN_RECOVERY",
      "lot": 0.01,
      "created_at": "...",
      "retry_count": 0
    }
  ],
  "executed": {
    "cmd_uuid": { "executed_at": "...", "result_ticket": 123456 }
  }
}
```

Restart sonrası pending commands replay edilir (broker state ile reconcile).

---

## 12.6 Schema Versioning

```
schema_version field in every JSON file
Migration on load:
    v1 → v2: add field X with default
    unsupported version: log ERROR, attempt best-effort load
```

---

## 12.7 IBasketStateRepository Interface

```
interface IBasketStateRepository {
    save(basket) → Result
    loadById(basketId) → Result<Basket>
    loadAll(accountId) → Result<list<Basket>>
    delete(basketId) → Result
    archive(basket) → Result
    exists(basketId) → bool
}
```

---

## 12.8 Remote Sync Failure Handling

Remote sync başarısız olursa:
- Local state **her zaman** güncel
- Remote sync retry queue (in-memory + periodic retry)
- 3 başarısız deneme → log WARN, devam et
- Remote sync asla trade kararlarını **bloke etmez**

---

## 12.9 Data Retention

| Veri | Retention |
|------|-----------|
| Active state files | Basket life + 0 |
| Archive files | 90 gün local |
| PostgreSQL signals | 1 yıl |
| PostgreSQL audit | 1 yıl |
| Log files | 30 gün rotating |

---

## 12.10 Backup Strategy

- Local state: MT5 Files klasörü terminal backup'a dahil
- PostgreSQL: daily pg_dump
- Critical: basket state + broker positions cross-validation on restart
