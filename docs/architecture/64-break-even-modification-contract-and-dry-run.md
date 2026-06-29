# 64 — Break-Even Modification Contract and Dry-Run (Sprint 9B)

## Scope

Sprint 9B introduces a **read-only** break-even stop-loss modification contract and dry-run pipeline.

Implemented flow:

```text
BreakEvenCandidate (DUE)
→ BuildBreakEvenStopLossModificationRequest
→ ValidateBreakEvenModificationRequest
→ PrepareBreakEvenModificationDryRun
→ emit audit / event only
```

Out of scope:

- No broker mutation (`PositionModify`, `CTrade`, `OrderSend`, `OrderSendAsync`)
- No automatic break-even execution
- No registration to manual submission routes
- No `StrategyDecisionCommandMapper` wiring
- No execution queue enqueue
- No pending execution record creation

## Contract Classes

### Domain enums

- `BreakEvenModificationRequestStatus`
  - `NONE`, `DRY_RUN_READY`, `BLOCKED`, `NO_CHANGE_REQUIRED`, `INVALID`
- `BreakEvenModificationFailureReason`
  - fail-closed reasons for candidate, quote, profile, snapshot, stop validation, pending, and dry-run authorization gates
- `BreakEvenModificationExecutionIntent`
  - `DRY_RUN_ONLY`
  - apply policy is fixed to `ALL_OR_NOTHING`

### Domain value objects

- `BreakEvenStopLossModificationRequest`
  - immutable request envelope
  - contains execution identity, basket/profile binding, quote sequence, idempotency key, ticket list, per-ticket prior SL and ticket status, proposed SL, trigger metadata, spread/buffer components, recommendations, and dry-run markers
  - `broker_mutation_performed` is always `false`
- `BreakEvenModificationAudit`
  - captures the request plus gate-by-gate booleans (lifecycle, due status, quote freshness, pending execution gate, binding checks, snapshot consistency, stop validation, idempotency, dry-run authorization)

### Domain event / app buffer

- `BreakEvenModificationDomainEvent`
- `BreakEvenModificationEventBuffer`
  - dedupe by event type + break-even modification idempotency key

## Ticket-Level Safety Model

Break-even modification dry-run is ticket-bound and all-or-nothing:

- ticket source: current basket snapshot only
- each ticket must belong to the same basket, symbol, and direction
- snapshot tickets must be non-empty, unique, and open
- each ticket has explicit prior SL and planned status
  - `APPLY_REQUIRED`
  - `NO_CHANGE_REQUIRED` (existing SL already equal/better than proposed)
  - `UNSAFE` (invalid ticket state)
- any unsafe/mismatched ticket blocks the full request
- no symbol-wide fallback and no magic-only selection

## Dry-Run Gating / Status Matrix

`DRY_RUN_READY` is emitted only when all required gates pass:

- basket `ACTIVE`
- candidate `DUE`
- break-even not already activated
- quote sequence matched and fresh
- no unresolved pending execution for basket
- candidate profile hash and basket version matched
- non-empty, internally consistent ticket snapshot
- proposed SL passes stop/freeze validation
- idempotency not previously seen
- dry-run feature explicitly enabled
- account context eligible for future stop modification

Failure handling:

- blocked/invalid reasons are structured (`BreakEvenModificationFailureReason`)
- duplicate idempotency returns `NONE` (no new request/event)
- `NO_CHANGE_REQUIRED` is explicit when all bound tickets are already at equal/better SL

## Idempotency

Break-even modification key:

```text
break-even-modification:{basketId}:rule:{ruleId}:q:{quoteSequence}
```

Duplicate key:

- no second dry-run request
- no second dry-run event

## Runtime Wiring

`EvaluateBasketStrategyUseCase` read-only order:

```text
recovery planning
→ profit-level close planning
→ break-even candidate planning
→ break-even modification dry-run evaluation (new)
→ recovery risk gate / manual registration (unchanged)
```

Wiring remains isolated from execution mapping/submission.

## Candidate vs Dry-Run vs Activation

- candidate generation (`BreakEvenCandidate`): read-only planning result
- dry-run readiness (`BreakEvenStopLossModificationRequest`): execution-safe contract proving future modify feasibility
- break-even activation: **not in this sprint**; must require future broker-confirmed successful modification for all required tickets

Dry-run success must not:

- set `breakEvenActive`
- lock basket
- change lifecycle
- write pending execution
- modify broker stop-loss

## Live Execution Status

Live break-even execution remains **disabled**.
