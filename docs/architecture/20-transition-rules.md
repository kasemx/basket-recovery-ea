# 20. Explicit Transition Rules

> **Revizyon:** v2 — State sınıflarındaki implicit geçişler kaldırıldı. Tüm geçişler deklaratif **TransitionRule** tablosunda.

## 20.1 Tasarım Prensibi

Eski modelde her `IBasketState` subclass `handle(event)` ile geçiş yapıyordu — 15k LOC'ta dağıtık guard logic. Yeni model:

```
TransitionRuleRegistry (single source of truth)
    → TransitionEngine.apply(basket, domainEvent)
    → Result<TransitionOutcome>
```

State sınıfları **yalnızca state-specific entry/exit actions** tutar; geçiş kararı registry'de.

---

## 20.2 TransitionRule Yapısı

```
TransitionRule {
    RuleId              id
    BasketLifecycleState  currentState
    DomainEventType     allowedEvent          // trigger
    BasketLifecycleState  nextState
    list<DomainEventType> rejectedEvents     // this state'te reddedilen event'ler
    list<GuardPredicate>  guards              // optional additional conditions
    string              description           // audit
}
```

### TransitionOutcome

```
TransitionOutcome {
    bool                applied
    BasketLifecycleState  previousState
    BasketLifecycleState  newState
    DomainEventType     triggerEvent
    string              rejectionReason       // if not applied
}
```

---

## 20.3 TransitionEngine

```
TransitionEngine {
    -TransitionRuleRegistry registry
    -IEventBus eventBus
    
    apply(basket, event):
        currentState = basket.lifecycleState
        
        // 1. Rejection check
        rejectedRules = registry.getRejectedEvents(currentState)
        IF event.type IN rejectedRules:
            eventBus.publish(TransitionRejected{...})
            RETURN Rejected
        
        // 2. Match rule
        rule = registry.find(currentState, event.type)
        IF rule == null:
            eventBus.publish(TransitionRejected{...})
            RETURN Rejected
        
        // 3. Evaluate guards
        FOR each guard in rule.guards:
            IF NOT guard.evaluate(basket, event):
                eventBus.publish(TransitionRejected{...})
                RETURN Rejected
        
        // 4. Execute exit action (old state)
        stateExitActions.execute(currentState, basket)
        
        // 5. Apply transition
        basket.lifecycleState = rule.nextState
        
        // 6. Execute entry action (new state)
        stateEntryActions.execute(rule.nextState, basket)
        
        // 7. Publish
        eventBus.publish(StateTransitioned{from, to, event})
        
        RETURN Applied
}
```

---

## 20.4 Complete Transition Rule Table

### From: `PENDING_OPEN`

| Allowed Event | Next State | Rejected Events |
|---------------|------------|-----------------|
| `InitialPositionsOpened` | `WAIT_DETAILS` | `TP1Reached`, `BasketActivated`, `BreakEvenActivated`, `RecoveryStepCrossed` |
| `CommandFailed` (open exhausted) | `ERROR` | all others |
| `CloseBasketCommand` received | `CLOSING` | — |

### From: `WAIT_DETAILS`

| Allowed Event | Next State | Rejected Events |
|---------------|------------|-----------------|
| `BasketActivated` | `ACTIVE` | `TP1Reached`, `RecoveryStepCrossed`, `TargetRiskReached`, `BreakEvenActivated` |
| `WaitDetailsTimeout` | `CLOSING` | `BasketActivated` (if timeout wins race — config) |
| `CloseBasketCommand` | `CLOSING` | — |
| `CommandFailed` (critical) | `ERROR` | — |

**Rejected (explicit):** `RecoveryStepCrossed`, `TP1Reached`, `TP2Reached`, `TP3Reached`, `TargetRiskReached`, `BreakEvenEligible`

### From: `ACTIVE`

| Allowed Event | Next State | Rejected Events |
|---------------|------------|-----------------|
| `TP1Reached` | `TP1` | `BasketActivated`, `InitialPositionsOpened` |
| `MaxRiskReached` + config | `SUSPENDED` | — |
| `CloseBasketCommand` | `CLOSING` | — |
| `CommandFailed` (critical) | `ERROR` | — |

**Rejected:** `BasketActivated`, `InitialPositionsOpened`, `BreakEvenActivated` (BE only from TP1+)

**Mode flags (no lifecycle change):** `RecoveryStepCrossed`, `TargetRiskReached`, `RiskReduced`

### From: `TP1`

| Allowed Event | Next State | Rejected Events |
|---------------|------------|-----------------|
| `BreakEvenActivated` | `BREAK_EVEN` | `BasketActivated` |
| `TP2Reached` | `TP2` | `BasketActivated`, `InitialPositionsOpened` |
| `CloseBasketCommand` | `CLOSING` | — |

**Rejected:** `RecoveryStepCrossed` (if recoveryPermanentlyDisabled — via guard), `BasketActivated`

**Note:** `BreakEvenActivated` and `TP2Reached` are mutually exclusive paths; whichever event fires first wins (guard: BE requires realized threshold).

### From: `BREAK_EVEN`

| Allowed Event | Next State | Rejected Events |
|---------------|------------|-----------------|
| `TP2Reached` | `TP2` | `RecoveryStepCrossed`, `BasketActivated`, `BreakEvenActivated` |
| `AllPositionsClosed` (BE SL hit) | `FINISHED` | — |
| `CloseBasketCommand` | `CLOSING` | — |

**Rejected:** `RecoveryStepCrossed`, `BreakEvenActivated`, `TP1Reached`, `BasketActivated`

### From: `TP2`

| Allowed Event | Next State | Rejected Events |
|---------------|------------|-----------------|
| `TP3Reached` | `TP3` | `RecoveryStepCrossed`, `TP1Reached`, `BasketActivated` |
| `CloseBasketCommand` | `CLOSING` | — |

### From: `TP3`

| Allowed Event | Next State | Rejected Events |
|---------------|------------|-----------------|
| `AllPositionsClosed` | `FINISHED` | all trading events |
| `BasketClosing` | `CLOSING` | — |

### From: `CLOSING`

| Allowed Event | Next State | Rejected Events |
|---------------|------------|-----------------|
| `AllPositionsClosed` | `FINISHED` | `RecoveryStepCrossed`, `TP1Reached`, all new trade events |

### From: `SUSPENDED`

| Allowed Event | Next State | Rejected Events |
|---------------|------------|-----------------|
| `RiskReduced` + guard(risk < max) | `ACTIVE` | `RecoveryStepCrossed` (while lockout) |
| `CloseBasketCommand` | `CLOSING` | — |

### From: `FINISHED` / `ERROR`

| Allowed Event | Next State | Rejected Events |
|---------------|------------|-----------------|
| *(none)* | — | **ALL events rejected** |

Terminal states — yeni event kabul edilmez.

---

## 20.5 Guard Predicates

| Guard | Koşul |
|-------|-------|
| `HasSignalDetails` | `basket.details != null` |
| `InitialPositionsComplete` | open count == config.initialCount |
| `FloatingProfitPositive` | floating > 0 (config optional) |
| `RealizedProfitThreshold` | realized >= targetRisk × profile.beFraction |
| `BreakEvenNotYetActivated` | `!basket.breakEvenActivated` |
| `RecoveryNotPermanentlyDisabled` | `!basket.recoveryPermanentlyDisabled` |
| `NoPendingTradeRequests` | trade request queue empty for basket |
| `PriceCrossedTP` | direction-aware TP level crossed |
| `RiskBelowMax` | snapshot.risk < maxRisk |

Guard'lar config profile'dan parametre alır (doc 23).

---

## 20.6 Rejected Events — Davranış

Rejected event geldiğinde:

1. `TransitionRejected` event publish
2. Structured log (DEBUG level — noisy events filter)
3. **No state change**
4. **No command re-enqueue**

Bazı rejected event'ler mode flag handler'larına yine de gidebilir (lifecycle transition olmadan) — registry'de `affectsModeOnly: true` flag.

---

## 20.7 Mode Flag Rules (Parallel to Lifecycle)

Mode transitions ayrı tablo — lifecycle'a dokunmaz:

| Current Mode | Event | Next Mode |
|--------------|-------|-----------|
| recovery idle | `RecoveryStepCrossed` + guards | recoveryActive |
| recoveryActive | `RecoveryPositionOpened` | recovery idle |
| recovery * | `BreakEvenActivated` | recoveryPermanentlyDisabled |
| riskReduction off | `TargetRiskReached` + favorable | riskReductionActive |
| riskReductionActive | `RiskReduced` + risk<=target | off |
| lockout open | `MaxRiskReached` | locked |
| lockout locked | `RiskReduced` + risk<max×release | open |

---

## 20.8 Registry Validation (Startup)

Bootstrapper startup'ta:

```
TransitionRuleRegistry.validate():
    - Every non-terminal state has at least one outbound rule OR explicit terminal
    - No orphan events without handler
    - FINISHED/ERROR reject ALL
    - No duplicate (currentState, allowedEvent) pairs
    - Guard references valid profile keys
```

Validation fail → EA INIT_FAILED.

---

## 20.9 Test Stratejisi

```
TestTransitionRules.mq5:
    FOR each rule in registry:
        setup basket in rule.currentState
        fire rule.allowedEvent
        assert basket.lifecycleState == rule.nextState
    
    FOR each rejected in rule.rejectedEvents:
        fire event
        assert TransitionRejected published
        assert state unchanged
```

Tüm geçişler table-driven test — state class unit test'e gerek kalmaz.
