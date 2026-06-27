# 3. Sınıf Diyagramları

## 3.1 Domain — Core Entities

```mermaid
classDiagram
    class Basket {
        +BasketId id
        +string correlationKey
        +TradeDirection direction
        +string symbol
        +BasketLifecycleState lifecycleState
        +BasketModeFlags modes
        +RiskProfile riskProfile
        +RecoveryConfig recoveryConfig
        +SignalDetails details
        +TakeProfitLevels tpLevels
        +BreakEvenConfig breakEvenConfig
        +datetime createdAt
        +Money realizedProfit
        +Money targetRiskAmount
        +bool breakEvenActivated
        +bool recoveryPermanentlyDisabled
        +int lastRecoveryStepIndex
        +Price lastRecoveryAnchorPrice
        +list~BasketPosition~ positions
        +canOpenRecovery() bool
        +isAtMaxRisk() bool
        +getWeightedAverageEntry() Price
    }

    class BasketPosition {
        +ulong ticket
        +Price entryPrice
        +LotSize lot
        +Price stopLoss
        +Price takeProfit
        +datetime openTime
        +PositionRole role
        +bool isClosed
    }

    class TradingSignal {
        +SignalId id
        +string correlationKey
        +SignalType type
        +SignalSequence sequence
        +TradeDirection direction
        +string symbol
        +SignalDetails details
        +datetime receivedAt
        +bool isConsumed
    }

    class SignalDetails {
        +Price rangeLow
        +Price rangeHigh
        +Price stopLoss
        +Price tp1
        +Price tp2
        +Price tp3
        +Price tp4
        +bool tpOpen
    }

    class RiskProfile {
        +Percentage targetRisk
        +Percentage maxRisk
        +Money computeTargetRiskAmount(Equity) Money
        +Money computeMaxRiskAmount(Equity) Money
    }

    class RecoveryConfig {
        +Price recoveryStepPips
        +LotSize recoveryLotSize
        +int maxRecoverySteps
    }

    Basket "1" *-- "many" BasketPosition
    Basket "1" *-- "1" SignalDetails
    Basket "1" *-- "1" RiskProfile
    Basket "1" *-- "1" RecoveryConfig
    TradingSignal "1" *-- "0..1" SignalDetails
```

## 3.2 State Machine

```mermaid
classDiagram
    class BasketStateMachine {
        -IBasketState currentState
        -Basket context
        +dispatch(event) Result
        +getLifecycleState() BasketLifecycleState
        +getModes() BasketModeFlags
        +forceTransition(state) Result
    }

    class IBasketState {
        <<interface>>
        +onEnter(basket) void
        +onExit(basket) void
        +handle(event, basket) Result~IBasketState~
        +getStateId() BasketLifecycleState
    }

    class WaitDetailsState
    class ActiveState
    class TP1State
    class BreakEvenState
    class TP2State
    class TP3State
    class FinishedState
    class ErrorState

    IBasketState <|.. WaitDetailsState
    IBasketState <|.. ActiveState
    IBasketState <|.. TP1State
    IBasketState <|.. BreakEvenState
    IBasketState <|.. TP2State
    IBasketState <|.. TP3State
    IBasketState <|.. FinishedState
    IBasketState <|.. ErrorState

    BasketStateMachine o-- IBasketState
    BasketStateMachine --> Basket
```

## 3.3 Application Layer — Use Cases & Ports

```mermaid
classDiagram
    class BasketOrchestrator {
        -PollSignalsUseCase signalPoller
        -BasketStateMachine stateMachine
        -EvaluateRiskUseCase riskEvaluator
        -ExecuteRecoveryUseCase recoveryExecutor
        -EvaluateRecoveryUseCase recoveryEvaluator
        -ReduceRiskUseCase riskReducer
        -HandleTP1UseCase tp1Handler
        -ActivateBreakEvenUseCase breakEvenHandler
        -HandleTP2UseCase tp2Handler
        -HandleTP3UseCase tp3Handler
        +onTimer() void
        +onTick(symbol, bid, ask) void
        +onTradeTransaction(trans) void
        +onInit() Result
    }

    class ITradeGateway {
        <<interface>>
        +openMarket(symbol, dir, lot, comment) Result~ulong~
        +closePosition(ticket) Result
        +modifyStopLoss(ticket, sl) Result
        +closePartial(ticket, lot) Result
    }

    class ISignalRepository {
        <<interface>>
        +fetchPending(accountId, since) Result~list~SignalDto~~
        +acknowledge(signalId, basketId) Result
    }

    class IBasketStateRepository {
        <<interface>>
        +save(basket) Result
        +loadAll(accountId) Result~list~Basket~~
        +loadById(basketId) Result~Basket~
        +delete(basketId) Result
    }

    class IPositionReader {
        <<interface>>
        +getOpenPositions(magic, symbol) list~BasketPosition~
        +syncWithBroker(basket) Result
    }

    BasketOrchestrator --> PollSignalsUseCase
    BasketOrchestrator --> BasketStateMachine
    OpenInitialBasketUseCase --> ITradeGateway
    OpenInitialBasketUseCase --> IBasketStateRepository
    PollSignalsUseCase --> ISignalRepository
    ExecuteRecoveryUseCase --> ITradeGateway
    ExecuteRecoveryUseCase --> RiskCalculator
```

## 3.4 Domain Services

```mermaid
classDiagram
    class RiskCalculator {
        +calculateBasketRisk(basket, equity, symbolInfo) RiskSnapshot
        +calculatePositionRisk(position, sl, symbolInfo) Money
        +projectRiskAfterRecovery(basket, newLot, newEntry, sl) Money
        +isWithinMaxRisk(projected, maxRisk) bool
        +isAboveTargetRisk(current, target) bool
    }

    class RecoveryEvaluator {
        +shouldTriggerRecovery(basket, currentPrice) bool
        +computeNextRecoveryLevel(basket) Price
        +canOpenRecovery(basket, riskCalc) bool
    }

    class RiskReductionPlanner {
        +planReduction(basket, targetRisk) list~CloseCommand~
        +selectWorstEntriesFirst(positions) list~BasketPosition~
    }

    class TakeProfitPlanner {
        +planTP1PartialClose(basket, floatingProfit) list~CloseCommand~
        +planTP2PartialClose(basket, floatingProfit) list~CloseCommand~
        +computeRealizationTarget(floating, pct) Money
    }

    class BreakEvenCalculator {
        +shouldActivate(realizedProfit, targetRiskAmount) bool
        +computeBreakEvenStopLoss(basket, spread, buffer) Price
    }

    class WeightedAverageEntryCalculator {
        +calculate(positions) Price
    }

    class PositionRankingService {
        +rankByWorstEntry(positions, direction) list~BasketPosition~
    }

    RecoveryEvaluator --> RiskCalculator
    RiskReductionPlanner --> PositionRankingService
    TakeProfitPlanner --> PositionRankingService
    BreakEvenCalculator --> WeightedAverageEntryCalculator
```

## 3.5 Infrastructure Adapters

```mermaid
classDiagram
    class Mt5TradeGateway {
        -int magicNumber
        -int slippage
        +openMarket(...) Result
        +closePosition(ticket) Result
        +modifyStopLoss(ticket, sl) Result
    }

    class RestSignalRepository {
        -RestClient client
        -string apiKey
        +fetchPending(...) Result
        +acknowledge(...) Result
    }

    class FileBasketStateRepository {
        -string basePath
        -StateSerializer serializer
        +save(basket) Result
        +loadAll(accountId) Result
    }

    class RestClient {
        +get(url, headers) Result~string~
        +post(url, body, headers) Result~string~
    }

    ITradeGateway <|.. Mt5TradeGateway
    ISignalRepository <|.. RestSignalRepository
    IBasketStateRepository <|.. FileBasketStateRepository
    RestSignalRepository --> RestClient
```

## 3.6 Composition Root

```mermaid
classDiagram
    class BasketRecoveryEA {
        <<Expert Advisor>>
        +OnInit()
        +OnDeinit()
        +OnTick()
        +OnTimer()
        +OnTradeTransaction()
    }

    class Bootstrapper {
        +bootstrap() BasketOrchestrator
        -createTradeGateway() ITradeGateway
        -createRepositories() void
        -createUseCases() void
    }

    class EAEventHandlers {
        -BasketOrchestrator orchestrator
        +handleTick()
        +handleTimer()
        +handleTradeTransaction()
    }

    BasketRecoveryEA --> Bootstrapper
    BasketRecoveryEA --> EAEventHandlers
    EAEventHandlers --> BasketOrchestrator
    Bootstrapper ..> BasketOrchestrator : creates
```

## 3.7 BasketModeFlags (Orthogonal Regions)

```mermaid
classDiagram
    class BasketModeFlags {
        +bool recoveryActive
        +bool riskReductionActive
        +bool maxRiskLockout
        +bool breakEvenEligible
        +bool breakEvenActive
        +bool recoveryPermanentlyDisabled
    }

    note for BasketModeFlags "Lifecycle state'ten bağımsız.\nAynı anda birden fazla flag true olabilir.\nÖrnek: ACTIVE lifecycle + recoveryActive + riskReductionActive"
```

## 3.8 Command Queue (Idempotency)

```mermaid
classDiagram
    class CommandQueue {
        -map~CommandId, TradeCommand~ pending
        -map~CommandId, TradeCommand~ executed
        +enqueue(command) Result
        +processNext(gateway) Result
        +isDuplicate(commandId) bool
        +markExecuted(commandId) void
    }

    class TradeCommand {
        +CommandId id
        +CommandType type
        +BasketId basketId
        +ulong ticket
        +LotSize lot
        +Price sl
        +datetime createdAt
        +int retryCount
    }

    CommandQueue "1" *-- "many" TradeCommand
```
