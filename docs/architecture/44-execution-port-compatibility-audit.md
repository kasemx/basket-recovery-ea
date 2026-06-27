# Execution Port Compatibility Audit (Sprint 6A.1)

**Baseline:** Sprint 6A execution contract (uncommitted)  
**Goal:** Single Application execution boundary before Sprint 6B.

## Audit conclusion

Sprint 6A introduced two similarly named abstractions. **Sprint 6A.1 resolves this:**

- **`ITradeExecutor`** (`Application/Execution/Ports/ITradeExecutor.mqh`) is the **sole Application execution port**.
- **`CSimulatedTradeExecutor`** is the active runtime adapter (tests + future composition root default).
- **`CMt5TradeExecutor`** is an **inactive Infrastructure placeholder** implementing `ITradeExecutor`; it performs **no** `OrderSend` / `OrderCheck` / `CTrade` calls until Sprint 6B translates validated `CTradeExecutionRequest` objects.
- **`ITradeRequestExecutor`** and Sprint 5 per-operation adapters are **relocated to Infrastructure/Legacy** and are **not** composition-root eligible.

`CMockTradeExecutor` is **removed** as a public adapter. Its role is fully superseded by `CSimulatedTradeExecutor` for contract-level simulation. Legacy per-operation mock remains as `CLegacyMockTradeRequestExecutor` for infrastructure unit tests only.

## Execution-related interfaces and implementations

| Symbol | Location | Role | Composition root? |
|--------|----------|------|-----------------|
| `ITradeExecutor` | `Application/Execution/Ports/` | **Sole Application port** — `Execute(CTradeExecutionRequest)` | Yes (Sprint 6B) |
| `IExecutionJournal` | `Application/Execution/Ports/` | Transition/receipt journal | Yes |
| `IExecutionRequestRepository` | `Application/Execution/Ports/` | Idempotency + receipt store | Yes |
| `CExecuteTradeIntentUseCase` | `Application/Execution/` | Orchestration above adapter | Yes |
| `CSimulatedTradeExecutor` | `Infrastructure/Execution/` | Deterministic broker simulation | Yes (now) |
| `CMt5TradeExecutor` | `Infrastructure/Execution/` | **Inactive placeholder** for Sprint 6B MT5 adapter | No (until 6B) |
| `ITradeRequestExecutor` | `Infrastructure/Execution/Legacy/` | **Legacy** per-operation port | **No** |
| `CLegacyMt5TradeRequestExecutor` | `Infrastructure/Execution/Legacy/` | Sprint 5 OrderSend gateway (tests only) | **No** |
| `CLegacyMockTradeRequestExecutor` | `Infrastructure/Execution/Legacy/` | Sprint 5 mock (tests only) | **No** |
| `ITradeRequestQueue` | `Application/Ports/` | Pre-6A queue DTO path (not execution port) | Separate concern |
| `CTradeRequest` | `Application/TradeRequests/` | Queue item DTO — not execution boundary | N/A |

Supporting Infrastructure (MT5 types allowed here only):

- `TradeRequestBuilder`, `TradeResultMapper`, `TradeValidationService`, `ExecutionPolicy`, `ExecutionAuditLogger`

Domain execution model (no MT5 types):

- `CTradeExecutionRequest`, `CTradeExecutionResult`, `CTradeExecutionReceipt`
- `CExecutionLifecycleRules`, `CExecutionDomainEvent`

## Caller → port → adapter dependency direction

```text
Strategy command (future Sprint 6B wiring)
        │
        ▼
CExecuteTradeIntentUseCase
  ├─ IBasketRepository (version/hash guard)
  ├─ IExecutionRequestRepository (idempotency)
  ├─ IExecutionJournal (transitions)
  ├─ CExecutionRequestFactory / Validator
  └─ ITradeExecutor.Execute(request)
           │
           ├── CSimulatedTradeExecutor     ← active now
           └── CMt5TradeExecutor           ← inactive placeholder (Sprint 6B)
```

**Not in production path:**

```text
CLegacyMt5TradeRequestExecutor : ITradeRequestExecutor
  └─ OrderSend / OrderCheck (Legacy/TestExecution.mq5 only)
```

## Ownership responsibilities

| Concern | Owner (above adapter) | Adapter may NOT own |
|---------|----------------------|---------------------|
| Lifecycle state machine | `CExecutionLifecycleRules` + use case + journal | Terminal transition rules |
| Idempotency | `IExecutionRequestRepository` + use case | Duplicate key policy |
| Request validation | `CExecutionRequestValidator` + `CBasketRuntimeGuard` | Basket version/hash checks |
| Journal / transitions | `IExecutionJournal` | Replay semantics |
| Domain events | `CExecutionResultMapper` | TP1/TP2/TP3-specific events |
| MT5 translation | **Future** `CMt5TradeExecutor` (6B) only | Validation/idempotency |

## MT5 type visibility rules

| Layer | MT5 trade types (`MqlTradeRequest`, `OrderSend`, …) |
|-------|-----------------------------------------------------|
| Domain | **Forbidden** — verified: no imports |
| Application | **Forbidden** — verified: no imports |
| Infrastructure/Execution | Allowed in Legacy + future active `CMt5TradeExecutor` |
| StrategyEngine | **Unaware** of executors |

## CMt5TradeExecutor status

| Question | Answer |
|----------|--------|
| Placeholder, legacy, or active production? | **Inactive placeholder** implementing unified `ITradeExecutor` |
| Calls broker APIs today? | **No** — returns deterministic rejected receipt |
| Sprint 5 OrderSend implementation? | **`CLegacyMt5TradeRequestExecutor`** in `Infrastructure/Execution/Legacy/` |

## CMockTradeExecutor vs CSimulatedTradeExecutor

| | `CMockTradeExecutor` (removed) | `CSimulatedTradeExecutor` |
|--|-------------------------------|---------------------------|
| Port | Legacy `ITradeRequestExecutor` | Unified `ITradeExecutor` |
| Request model | `CTradeRequest` + per-op methods | Immutable `CTradeExecutionRequest` |
| Lifecycle/journal | None | Full contract |
| Still useful? | **No** for Application path | **Yes** — sole simulation adapter |

## Direct references (post-migration)

### `ITradeExecutor` (Application port)

- `Application/Execution/ExecuteTradeIntentUseCase.mqh`
- `Application/Execution/Ports/ITradeExecutor.mqh`
- `Infrastructure/Execution/SimulatedTradeExecutor.mqh`
- `Infrastructure/Execution/Mt5TradeExecutor.mqh` (placeholder)
- `Tests/TestExecutionContract.mq5`
- `Tests/TestExecutionPortCompatibility.mq5`

### `ITradeRequestExecutor` (Legacy — Infrastructure only)

- `Infrastructure/Execution/Legacy/ITradeRequestExecutor.mqh`
- `Infrastructure/Execution/Legacy/LegacyMt5TradeRequestExecutor.mqh`
- `Infrastructure/Execution/Legacy/LegacyMockTradeRequestExecutor.mqh`
- `Tests/TestExecution.mq5` (legacy infrastructure tests)

### Removed public paths

- ~~`Application/Ports/ITradeExecutor.mqh`~~ (legacy alias — deleted)
- ~~`Application/Ports/ITradeRequestExecutor.mqh`~~ (moved to Legacy)
- ~~`Infrastructure/Execution/MockTradeExecutor.mqh`~~ (replaced by Legacy mock)

### Composition root (`Bootstrapper`, `ServiceContainer`, `ApplicationKernel`)

- **No** reference to `ITradeRequestExecutor`, `CLegacyMt5TradeRequestExecutor`, or `CLegacyMockTradeRequestExecutor`
- **No** `ITradeExecutor` registration yet (Sprint 6B)
- Guard: `CExecutionRuntimeCompositionGuard::AllowsLegacyTradeRequestExecutorInCompositionRoot() == false`

## Target architecture (confirmed)

```text
CExecuteTradeIntentUseCase
→ ITradeExecutor
→ CSimulatedTradeExecutor (now)
→ CMt5TradeExecutor (Sprint 6B — translates sealed CTradeExecutionRequest only)
```

## Chosen migration outcome

**Preferred outcome applied:**

1. Single Application port: `ITradeExecutor`
2. Legacy port moved to `Infrastructure/Execution/Legacy/` — not public Application API
3. `CMt5TradeExecutor` replaced with inactive unified-port placeholder (no broker calls)
4. `CMockTradeExecutor` removed; legacy mock renamed and isolated
5. `CExecutionRuntimeCompositionGuard` prevents accidental legacy wiring
6. Tests split: `TestExecution.mq5` (legacy infra), `TestExecutionContract.mq5` (contract), `TestExecutionPortCompatibility.mq5` (port audit)

## Old → new dependency map

```text
BEFORE (Sprint 6A)
  Application/Ports/ITradeExecutor.mqh        → alias to ITradeRequestExecutor
  Application/Ports/ITradeRequestExecutor.mqh → public legacy port
  CMt5TradeExecutor : ITradeRequestExecutor   → OrderSend gateway
  CMockTradeExecutor  : ITradeRequestExecutor
  Application/Execution/Ports/ITradeExecutor  → new unified port

AFTER (Sprint 6A.1)
  Application/Execution/Ports/ITradeExecutor  → sole Application port
  CSimulatedTradeExecutor : ITradeExecutor
  CMt5TradeExecutor : ITradeExecutor (inactive placeholder)
  Infrastructure/Execution/Legacy/ITradeRequestExecutor (private legacy)
  CLegacyMt5TradeRequestExecutor : ITradeRequestExecutor (tests only)
  CLegacyMockTradeRequestExecutor : ITradeRequestExecutor (tests only)
```
