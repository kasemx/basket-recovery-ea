# 13. MT5 Restart Sonrası Kurtarma Stratejisi

## 13.1 Problem Tanımı

MT5 terminal restart, crash, VPS reboot veya EA reload sonrasında:
- Broker'da açık pozisyonlar **hâlâ açık**
- EA memory state **sıfırlanmış**
- Pending commands **bilinmiyor**
- REST poll cursor **kaybolmuş olabilir**

Sistem deterministik şekilde önceki duruma dönmeli veya güvenli şekilde ERROR'a alınmalı.

---

## 13.2 Recovery Pipeline

```
OnInit
  │
  ▼
RecoverFromRestartUseCase
  │
  ├── 1. Load local state files (all active baskets)
  ├── 2. Load pending command queue
  ├── 3. Load signal poll cursor
  ├── 4. Query broker open positions (by magic range)
  ├── 5. ReconciliationEngine.reconcile(states, positions, commands)
  ├── 6. Rehydrate state machines
  ├── 7. Replay pending commands (with idempotency check)
  ├── 8. Resume timer (signal polling)
  └── 9. Log recovery summary
```

---

## 13.3 Reconciliation Engine

```
ReconciliationEngine.reconcile(localStates, brokerPositions, pendingCommands):
    
    FOR each localState:
        matchedPositions = filter brokerPositions by basket comment/magic
        IF matchedPositions empty AND localState has open positions:
            → ORPHAN_STATE (positions closed externally?)
            → Mark FINISHED or ERROR based on config
        IF matchedPositions not empty:
            → Sync tickets (broker is source of truth for tickets)
            → Update entry prices if drift
            → Remove closed positions from state
    
    FOR each brokerPosition NOT matched:
        → ORPHAN_POSITION
        → Flag for manual review
        → Do NOT auto-manage
    
    RETURN ReconciliationReport
```

### Reconciliation Sonuçları

| Durum | Aksiyon |
|-------|---------|
| State ↔ Positions match | Rehydrate, resume |
| State exists, no positions | → FINISHED |
| Positions exist, no state | → ORPHAN alert, don't touch |
| Ticket mismatch | Update state from broker |
| Partial close detected | Update position list, recalc risk |
| SL/TP drift from broker | Re-sync from state (state wins) or broker (config) |

---

## 13.4 State Machine Rehydration

```
FOR each reconciled basket:
    stateMachine = new BasketStateMachine()
    state = createStateInstance(basket.lifecycleState)
    stateMachine.forceState(state, basket)
    
    // Verify invariants
    IF basket.lifecycleState == BREAK_EVEN:
        ASSERT basket.recoveryPermanentlyDisabled == true
        ASSERT all open positions have SL == basket.breakEvenStopLoss
    
    add to BasketOrchestrator.activeBaskets
```

---

## 13.5 Pending Command Replay

```
FOR each pending command (ordered by created_at):
    IF command.type == OPEN and position already exists (matching comment):
        → mark executed (idempotent skip)
    IF command.type == CLOSE and position not exists:
        → mark executed (already closed)
    IF command.type == MODIFY_SL:
        → check current SL, skip if already set
    ELSE:
        → re-enqueue for execution
```

**Kural:** Replay asla duplicate pozisyon açmamalı.

---

## 13.6 Signal Poll Cursor Recovery

```
Load cursor from signal_poll_cursor.json
IF missing:
    → Use latest signal received_at from local basket states
    → Or: fetch all pending from API (safe, idempotent)
```

Duplicate signal processing:
- INITIAL for existing correlation_key → skip (idempotent)
- DETAILS for ACTIVE basket → skip if details already applied

---

## 13.7 Lifecycle-State-Specific Recovery

| State at crash | Recovery Behavior |
|----------------|-------------------|
| PENDING_OPEN | Check how many positions opened; resume or rollback |
| WAIT_DETAILS | Resume waiting for Signal #2; start timeout timer |
| ACTIVE | Full engine resume: risk, recovery, TP monitors |
| TP1 | Resume TP1+ monitoring (BE check, TP2) |
| BREAK_EVEN | Verify SL sync, resume TP2/TP3 monitor, NO recovery |
| TP2 | Resume TP3 monitor |
| CLOSING | Retry close all remaining |
| ERROR | Do NOT auto-resume; require manual reset |

---

## 13.8 PENDING_OPEN Partial Recovery

Crash during initial 3-position open:

```
expected = 3
actual = count open positions with basket comment

IF actual == 0: retry all 3
IF actual == 1 or 2: 
    option A: open remaining (config default)
    option B: close all + ERROR (safer)
IF actual == 3: → WAIT_DETAILS
IF actual > 3: → ERROR (unexpected)
```

**Öneri:** Config `partial_open_strategy: COMPLETE | ABORT`.

---

## 13.9 Post-Recovery Validation

Recovery sonrası zorunlu validation pass:

```
1. RiskCalculator recalculate all baskets
2. Verify SL/TP on all positions match state
3. Verify no pending commands stuck > 5 min
4. Log recovery report:
     - baskets recovered: N
     - orphans: N
     - errors: N
     - commands replayed: N
5. POST /baskets/recovery-report to API (optional)
```

---

## 13.10 Manual Intervention Protocol

ERROR state basket'ler için:

```
1. EA panel veya log'da basket_id göster
2. Operator seçenekleri:
     a) Force FINISH (close all)
     b) Force ACTIVE (resume)
     c) Detach (EA stops managing, manual only)
3. Operator action → persist + log audit
```

---

## 13.11 Multi-Terminal Consideration

Aynı account'ta iki MT5 terminal çalışmamalı.  
API key + account_id binding + `mt5_instance_id` ile conflict detection:

```
IF ack from different mt5_instance_id for same basket:
    → LOG CRITICAL
    → Second instance refuses to manage
```

---

## 13.12 Recovery Test Matrix

| # | Crash Point | Expected Recovery |
|---|-------------|-------------------|
| 1 | After Signal #1, 2/3 positions open | Complete or abort |
| 2 | During Signal #2 SL modify | Re-sync SL from state |
| 3 | During recovery open | Detect new position or replay |
| 4 | During TP1 partial close | Recount positions, continue |
| 5 | After BE, before SL sync | Re-apply BE SL |
| 6 | Clean restart, all idle | Normal init |
| 7 | State file corrupted | ERROR, alert, don't trade |
| 8 | Orphan broker positions | Alert, no auto-action |
