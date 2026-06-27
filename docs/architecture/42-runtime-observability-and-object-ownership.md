# Runtime Observability and Object Ownership (Sprint 5.2)

## Diagnostic mode behavior

Fast-path diagnostics are **opt-in** via EA inputs:

| Input | Default | Purpose |
|-------|---------|---------|
| `InpEnableFastPathDiagnostics` | `false` | Master switch for bounded fast-path `Print` output |
| `InpFastPathDiagnosticIntervalMs` | `1000` | Minimum milliseconds between tick diagnostic lines per symbol |
| `InpEnableFastPathNoBasketHeartbeat` | `false` | When `false`, suppress repeated `no_matching_basket` tick lines |

When diagnostics are **disabled** (production default):

- OnTick hot path performs **no `Print` calls**
- No string formatting for diagnostic output on the tick path
- In-memory counters (`CInMemoryHotPathDiagnostics`) still update with integer increments only

When diagnostics are **enabled**:

- At most **one tick diagnostic line per symbol per interval**
- Startup emits one configuration line (always, once per attach)
- Deinit emits one cumulative summary line (always, once per detach)

### Tick diagnostic fields

```
BRE fast-path tick | symbol=... | seq=... | bid=... | ask=... | active=... | evaluated=... | skipped=... | deferred=... | reason=... | elapsed_ms=...
```

Skip reasons (`reason=`):

| Reason | Meaning |
|--------|---------|
| `no_matching_basket` | Symbol index has zero ACTIVE baskets for chart symbol |
| `duplicate_quote_sequence` | Basket skipped because quote sequence unchanged |
| `min_interval_gate` | Basket inside per-basket minimum evaluation interval |
| `stale_quote` | Quote read failed or market adapter rejected quote |
| `budget_exhausted` | More ACTIVE baskets exist than `MaxBasketsPerTick` budget |
| `trigger_policy` | Basket skipped by material-change / threshold policy |
| `none` | At least one basket evaluated this tick |

## Rate limiting behavior

`CFastPathDiagnosticReporter` enforces per-symbol rate limiting:

1. If diagnostics disabled → never emit tick lines
2. If primary reason is `no_matching_basket` and heartbeat flag is `false` → never emit
3. If same symbol emitted within `FastPathDiagnosticIntervalMs` → suppress

Production ticks never call `Print`; reporter checks `IsEnabled()` before formatting.

## Ownership graph

```
Bootstrapper
  └── CServiceContainer (owns=true)
        └── CBrokerReconciliationService
              ├── owns IBrokerPositionReader*  (CMt5BrokerPositionReader)
              └── owns CBasketPositionReconciler*
  └── CReconciliationSchedulerService (non-owning pointer to reconciler via service.Reconciler())
  └── CApplicationKernel (owns)
        ├── CFastPathDiagnosticReporter
        ├── CInMemoryHotPathDiagnostics
        ├── CFastMarketEvaluationCoordinator (non-owning refs)
        └── ...
  └── CApplicationContext
        └── deletes kernel, then container.Shutdown()
```

### Root cause of MT5 leak warnings (Sprint 5.2)

Prior to Sprint 5.2:

- `Bootstrapper` allocated `CMt5BrokerPositionReader` and `CBasketPositionReconciler` with `new`
- Only `CBrokerReconciliationService` was registered with `CServiceContainer` for ownership
- `CBrokerReconciliationService` stored the reconciler pointer but **did not delete** reader or reconciler in its destructor
- Failure paths manually deleted reader/reconciler while container also owned the service → **double-delete risk**
- Success path never deleted reader/reconciler → **leaked memory** on EA unload

### Fix

`CBrokerReconciliationService` now **owns** both `IBrokerPositionReader*` and `CBasketPositionReconciler*` when constructed with `takeOwnership=true`. Bootstrapper:

- Passes both pointers into the service constructor
- Obtains non-owning reconciler reference via `Reconciler()` for `CReconciliationSchedulerService`
- Removes all manual `delete brokerPositionReader` / `delete positionReconciler` calls

## Shutdown cleanup order

Deterministic teardown when EA is removed:

1. `OnDeinit` → `EventKillTimer()`
2. `g_applicationContext.LogFastPathDeinitSummary()` (reads in-memory counters; no broker I/O)
3. `g_applicationContext.LogShutdown(reason)`
4. `delete g_applicationContext`
   - `~CApplicationContext` → `Shutdown()`
   - `delete m_kernel` (`~CApplicationKernel` deletes fast-path graph, handlers, persistence manager, etc.)
   - `m_container.Shutdown()` then `delete m_container`
   - `CServiceContainer` deletes owned services including `CBrokerReconciliationService`
   - `~CBrokerReconciliationService` deletes reconciler, then reader

**Rule:** Each `new` has exactly one owning parent. Non-owning consumers (scheduler, coordinator) must never `delete` shared dependencies.

## Known MT5 object-lifetime constraints

- MQL5 reports `leaked memory` / `undeleted dynamic objects` at script/EA unload when `new` allocations survive without matching `delete`
- Destructors are invoked when `delete` is called on the owning pointer; virtual destructors on service interfaces ensure polymorphic cleanup
- Avoid disabling pointer checks (`#property` / runtime) — fix ownership instead
- `Print` in hot paths allocates/format strings; keep diagnostics behind explicit flags and rate limits

## Runtime validation (BTCUSD)

1. Attach EA to BTCUSD M1
2. Set `InpEnableFastPathDiagnostics=true`
3. Set `InpEnableFastPathNoBasketHeartbeat=true`
4. AutoTrading on or off — no broker execution must occur
5. Wait 10–20 seconds
6. Experts tab: ~1 diagnostic line per second with `reason=no_matching_basket` (when no ACTIVE basket)
7. Remove EA from chart
8. Confirm **zero** `leaked memory` / `undeleted dynamic objects` warnings

## Tests

`TestFastPathDiagnostics.mq5` covers:

- Diagnostics disabled → `WantsOutput()==false`
- No-basket heartbeat flag gating
- Heartbeat rate limiting
- Duplicate quote skip reason mapping
- Stale quote counter
- Reconciliation service owned-graph delete
- Deinit summary without broker calls
