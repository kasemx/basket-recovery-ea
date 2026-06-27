# 6. Sequence Diyagramları

## 6.1 Signal #1 — İlk Sepet Oluşturma

```mermaid
sequenceDiagram
    autonumber
    participant TG as Telegram
    participant PY as Python Parser
    participant DB as PostgreSQL
    participant API as REST API
    participant EA as MT5 EA
    participant BRK as Broker

    TG->>PY: "Gold Sell Now"
    PY->>PY: Parse → INITIAL signal
    PY->>PY: Generate correlation_key
    PY->>DB: INSERT signal (PENDING)
    
    loop Every 2-5 sec
        EA->>API: GET /signals/pending
        API->>DB: SELECT pending signals
        DB-->>API: signal list
        API-->>EA: SignalDto (INITIAL)
    end

    EA->>EA: ProcessInitialSignalUseCase
    EA->>EA: Create Basket (WAIT_DETAILS)
    
    loop 3 positions
        EA->>BRK: OrderSend SELL 0.01
        BRK-->>EA: ticket
    end
    
    EA->>EA: Persist basket state (local JSON)
    EA->>API: POST /signals/{id}/ack {basket_id}
    API->>DB: UPDATE signal CONSUMED
```

## 6.2 Signal #2 — Detay Güncelleme ve Aktivasyon

```mermaid
sequenceDiagram
    autonumber
    participant TG as Telegram
    participant PY as Python Parser
    participant DB as PostgreSQL
    participant API as REST API
    participant EA as MT5 EA
    participant BRK as Broker

    TG->>PY: "Gold Sell Now\n4014-4017\nSL 4020\nTP1..."
    PY->>PY: Parse → DETAILS signal
    PY->>DB: INSERT (correlation_key match)
    
    EA->>API: GET /signals/pending
    API-->>EA: SignalDto (DETAILS)
    
    EA->>EA: Find basket by correlation_key
    EA->>EA: ProcessDetailsSignalUseCase
    
    loop Each open position
        EA->>BRK: Modify SL/TP
        BRK-->>EA: OK
    end
    
    EA->>EA: RiskCalculator → baseline snapshot
    EA->>EA: State: WAIT_DETAILS → ACTIVE
    EA->>EA: Set recovery anchor price
    EA->>EA: Persist + remote sync
    EA->>API: POST /signals/{id}/ack
```

## 6.3 Recovery Pozisyon Açma

```mermaid
sequenceDiagram
    autonumber
    participant Tick as OnTick
    participant Disp as TickEventDispatcher
    participant Rec as RecoveryEvaluator
    participant Risk as RiskCalculator
    participant UC as ExecuteRecoveryUseCase
    participant CQ as CommandQueue
    participant BRK as Broker

    Tick->>Disp: price update (adverse move)
    Disp->>Rec: shouldTriggerRecovery(basket, price)
    Rec-->>Disp: true (step crossed)
    
    Disp->>UC: execute(basket)
    UC->>Risk: projectRiskAfterRecovery(basket, newLot)
    Risk-->>UC: projected risk
    
    alt projected <= maxRisk
        UC->>CQ: enqueue OPEN_RECOVERY command
        CQ->>BRK: OrderSend (recovery lot)
        BRK-->>CQ: ticket
        CQ->>UC: update basket positions
        UC->>UC: lastRecoveryStepIndex++
        UC->>UC: persist
    else projected > maxRisk
        UC->>UC: set maxRiskLockout flag
        UC->>UC: log + alert (no trade)
    end
```

## 6.4 Risk Reduction

```mermaid
sequenceDiagram
    autonumber
    participant Tick as OnTick
    participant Risk as EvaluateRiskUseCase
    participant Red as ReduceRiskUseCase
    participant Plan as RiskReductionPlanner
    participant CQ as CommandQueue
    participant BRK as Broker

    Tick->>Risk: evaluate(basket)
    Risk-->>Tick: risk > targetRisk
    
    Note over Tick: Price moving favorably (direction check)
    
    Tick->>Red: execute(basket)
    Red->>Plan: planReduction(basket, targetRisk)
    Plan->>Plan: rankByWorstEntry()
    Plan-->>Red: [CloseCommand, ...]
    
    loop Until risk <= target
        Red->>CQ: enqueue CLOSE command (worst entry)
        CQ->>BRK: OrderClose
        BRK-->>CQ: OK
        Red->>Risk: re-evaluate
    end
    
    Red->>Red: persist
```

## 6.5 TP1 + Break-Even Akışı

```mermaid
sequenceDiagram
    autonumber
    participant Tick as OnTick
    participant TP1 as HandleTP1UseCase
    participant Plan as TakeProfitPlanner
    participant BE as ActivateBreakEvenUseCase
    participant BEcalc as BreakEvenCalculator
    participant CQ as CommandQueue
    participant BRK as Broker

    Tick->>TP1: price >= TP1
    TP1->>Plan: planTP1PartialClose(floatingProfit)
    Plan-->>TP1: close commands (33% realize)
    
    loop Partial closes
        TP1->>CQ: enqueue CLOSE (worst first)
        CQ->>BRK: OrderClose
    end
    
    TP1->>TP1: realizedProfit += closed
    TP1->>TP1: state → TP1
    
    Note over Tick: Subsequent ticks monitor realized profit
    
    Tick->>BEcalc: shouldActivate(realized, targetRisk×33%)
    BEcalc-->>Tick: true
    
    Tick->>BE: activate(basket)
    BE->>BEcalc: computeBreakEvenStopLoss(avgEntry, spread, buffer)
    BEcalc-->>BE: SL price
    
    loop All remaining positions
        BE->>CQ: enqueue MODIFY_SL
        CQ->>BRK: PositionModify SL
    end
    
    BE->>BE: recoveryPermanentlyDisabled = true
    BE->>BE: state → BREAK_EVEN
    BE->>BE: persist
```

## 6.6 TP2 → TP3 → Basket Finish

```mermaid
sequenceDiagram
    autonumber
    participant Tick as OnTick
    participant TP2 as HandleTP2UseCase
    participant TP3 as HandleTP3UseCase
    participant Fin as FinishBasketUseCase
    participant CQ as CommandQueue
    participant API as REST API

    Tick->>TP2: price >= TP2
    TP2->>TP2: partial close until 66% realized
    TP2->>TP2: state → TP2

    Tick->>TP3: price >= TP3
    TP3->>CQ: close ALL remaining
    TP3->>Fin: finish(basket)
    Fin->>Fin: state → FINISHED
    Fin->>Fin: delete local state (or archive)
    Fin->>API: POST /baskets/{id}/state {FINISHED}
```

## 6.7 MT5 Restart Recovery

```mermaid
sequenceDiagram
    autonumber
    participant EA as OnInit
    participant Rec as RecoverFromRestartUseCase
    participant File as FileStateRepository
    participant Pos as Mt5PositionReader
    participant Recon as ReconciliationEngine
    participant SM as StateMachine

    EA->>Rec: execute()
    Rec->>File: loadAll(accountId)
    File-->>Rec: basket states[]
    Rec->>Pos: getOpenPositions(magic)
    Pos-->>Rec: broker positions[]
    
    Rec->>Recon: reconcile(states, positions)
    
    loop Each basket
        alt Positions match state
            Recon->>SM: rehydrate(state)
        else Orphan positions
            Recon->>Recon: flag ERROR + alert
        else State exists, no positions
            Recon->>Recon: mark FINISHED
        end
    end
    
    Rec->>EA: resume polling timer
```

## 6.8 Hata Senaryosu — Broker Emir Reddi

```mermaid
sequenceDiagram
    autonumber
    participant UC as UseCase
    participant CQ as CommandQueue
    participant GW as Mt5TradeGateway
    participant Log as Logger
    participant SM as StateMachine

    UC->>CQ: enqueue(command)
    CQ->>GW: execute
    GW-->>CQ: REJECTED (not enough money)
    
    CQ->>CQ: retryCount++
    
    alt retryCount < maxRetries
        CQ->>CQ: schedule retry (backoff)
    else max retries exceeded
        CQ->>Log: ERROR structured log
        CQ->>SM: dispatch(ERROR_EVENT)
        SM->>SM: → ErrorState (basket frozen)
    end
```
