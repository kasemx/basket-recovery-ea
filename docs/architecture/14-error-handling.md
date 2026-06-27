# 14. Hata Yönetimi (Error Handling)

## 14.1 Hata Sınıflandırması

| Seviye | Kod Prefix | Açıklama | Basket Etkisi | Sistem Etkisi |
|--------|-----------|----------|---------------|---------------|
| **INFO** | `I` | Normal operasyonel bilgi | Yok | Yok |
| **WARN** | `W` | Recoverable anomaly | Devam | Log + metric |
| **ERROR** | `E` | Operation failed, retry possible | Basket devam veya freeze | Log + alert |
| **CRITICAL** | `C` | System-level failure | ERROR state | Polling dur, alert |
| **FATAL** | `F` | Unrecoverable | EA stop | Remove EA |

---

## 14.2 Error Code Katalogu

```
// Signal Errors (Sxxx)
S001  SIGNAL_PARSE_FAILED          Python parser (Python-side)
S002  SIGNAL_ORPHAN_DETAILS        DETAILS without matching basket
S003  SIGNAL_DUPLICATE             Duplicate correlation_key INITIAL
S004  SIGNAL_ACK_FAILED            Ack POST failed after processing
S005  SIGNAL_POLL_FAILED           GET pending failed

// Trade Errors (Txxx)
T001  TRADE_OPEN_REJECTED          Broker rejected order
T002  TRADE_CLOSE_FAILED           Close failed
T003  TRADE_MODIFY_SL_FAILED       SL modify failed
T004  TRADE_PARTIAL_FILL           Partial fill (rare in MT5 market)
T005  TRADE_TIMEOUT                No response within timeout
T006  TRADE_INSUFFICIENT_MARGIN    Not enough margin

// Basket Errors (Bxxx)
B001  BASKET_INVARIANT_VIOLATION   Domain rule broken
B002  BASKET_RECONCILE_FAILED      Restart mismatch
B003  BASKET_ORPHAN_POSITION       Unknown broker position
B004  BASKET_STATE_CORRUPT         JSON parse failed
B005  BASKET_WAIT_DETAILS_TIMEOUT  Signal #2 never arrived

// Risk Errors (Rxxx)
R001  RISK_UNDEFINED               SL not set (WAIT_DETAILS)
R002  RISK_MAX_BREACH              Max risk exceeded
R003  RISK_CALC_FAILED             Symbol info unavailable

// System Errors (Xxxx)
X001  REST_AUTH_FAILED             API key invalid
X002  REST_NETWORK_ERROR           Connection failed
X003  PERSIST_WRITE_FAILED         Local file write failed
X004  CONFIG_INVALID               EA input validation failed
```

---

## 14.3 Result<T, E> Pattern

MQL5'te exception sınırlı — **Result monad** kullan:

```
template<typename T>
class Result {
    bool success
    T value
    ErrorCode errorCode
    string errorMessage
    
    static Result Ok(T value)
    static Result Fail(ErrorCode code, string message)
    
    bool IsOk()
    bool IsFail()
    bool HasValue()
    bool TryGetValue(T &out)   // S0.1: güvenli erişim — başarısız Result'ta false
    T ValueOr(T default)       // S0.1: UnwrapOr yerine
}
```

**Kural (S0.1):** `Value()` / `Unwrap()` kullanılmaz — invalid access önlenir. Tüm çağrı noktaları `TryGetValue` veya `ValueOr` kullanır.

---

## 14.4 Retry Stratejisi

| Operasyon | Max Retry | Backoff | Failure Action |
|-----------|-----------|---------|----------------|
| REST GET pending | 3 | 1s, 2s, 4s | Skip cycle |
| REST POST ack | 5 | 1s, 2s, 4s, 8s, 16s | Queue for retry |
| Trade open | 3 | 500ms, 1s, 2s | Basket ERROR or skip recovery |
| Trade close | 5 | 500ms × n | Retry until closed |
| Trade modify SL | 3 | 500ms × n | Log WARN, retry next tick |
| File persist | 3 | immediate | CRITICAL if all fail |

---

## 14.5 Circuit Breaker (REST)

```
RestCircuitBreaker {
    int failureCount
    datetime lastFailure
    bool isOpen
    
    recordFailure():
        failureCount++
        IF failureCount >= 5 in 60 sec: isOpen = true
    
    recordSuccess():
        failureCount = 0
        isOpen = false
    
    allowRequest():
        IF isOpen AND (now - lastFailure) > 60 sec:
            isOpen = false  // half-open
        RETURN NOT isOpen
}
```

Circuit open → signal polling paused, existing baskets continue managing.

---

## 14.6 Basket-Level Error Isolation

**Kritik prensip:** Bir basket'in hatası diğerlerini etkilememeli.

```
BasketOrchestrator.onTick():
    FOR each basket:
        TRY (via Result pattern):
            process basket
        ON failure:
            LOG error with basket_id
            IF critical: basket → ERROR state
            CONTINUE to next basket
```

---

## 14.7 ERROR State Davranışı

```
ERROR state basket:
    - NO new trades
    - NO recovery
    - NO TP processing
    - Existing positions REMAIN OPEN (not auto-closed)
    - Operator must intervene
    - Periodic alert log (every 5 min)
```

Configurable: `error_state_action: FREEZE | CLOSE_ALL | NOTIFY_ONLY`

---

## 14.8 Trade Failure Handling Detail

### Open Failed

```
IF initial position open fails (Signal #1):
    retry up to 3
    IF still failing:
        basket → ERROR
        DO NOT ack signal (will retry next poll — idempotent)

IF recovery open fails:
    log WARN
    set recoveryInFlight = false
    retry next step crossing (NOT same step)
```

### Close Failed

```
Partial close for TP:
    retry 5 times
    IF fail: skip this position, try next worst entry
    IF all fail: log CRITICAL, basket → ERROR
```

### SL Modify Failed

```
Break-even SL sync:
    retry each position independently
    IF any fail after retries:
        log ERROR
        schedule retry on next timer (1 sec)
        DO NOT transition to BREAK_EVEN until all synced (or config override)
```

---

## 14.9 Validation Errors (Fail-Fast at Boundaries)

```
Configuration load (OnInit):
    target_risk > 0 AND max_risk >= target_risk
    recovery_step > 0
    default_lot >= min_lot
    api_url not empty
    IF invalid: INIT_FAILED, EA does not start

Signal validation:
    symbol in allowed list
    direction IN (BUY, SELL)
    IF DETAILS: sl, tp1 required
    prices positive and direction-consistent (SL above entry for SELL)
```

---

## 14.10 Dead Letter Queue

Ack'lenemeyen veya işlenemeyen sinyaller:

```
Local dead letter file: MQL5/Files/BasketRecovery/dead_letter/signals.json
Entry: { signal_id, error_code, timestamp, raw_payload }
Periodic retry: 1/hour
After 24h: log CRITICAL, notify operator
```

---

## 14.11 Error Handling Anti-Patterns (Yasak)

```
❌ Silent catch — her hata loglanmalı
❌ Infinite retry — max retry zorunlu
❌ Global EA stop on single basket error
❌ Auto-close all on any error (unless configured)
❌ Ignore persist failure
❌ Continue recovery after BE activated exchanges
```

---

## 14.12 Alerting Integration (Future)

Error severity >= CRITICAL:
- REST webhook to notification service
- Telegram bot alert (separate from signal channel)
- Email (optional)

MVP: structured log file + CRITICAL prefix for external log shippers.
