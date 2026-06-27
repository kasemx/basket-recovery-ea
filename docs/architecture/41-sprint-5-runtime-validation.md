# Sprint 5 / 5.1 Runtime Validation

Validation date: 2026-06-26  
Scope: Read-only live market context (Sprint 5) and event-driven fast path (Sprint 5.1)  
Trade Execution Engine: **not started**

## Summary

| Category | Result |
|----------|--------|
| Static code path verification | **PASS** |
| Static trade API guard | **PASS** (0 violations in Sprint 5/5.1 scope) |
| Compile gate | **PASS** (0 errors EA + all tests) |
| MT5 GUI manual runtime | **NOT EXECUTED** — checklist provided below |

---

## Static Verification (automated)

These checks were performed by source inspection and unit-test compile coverage. No broker execution APIs appear in Sprint 5/5.1 hot-path or reconciliation code.

### OnTick → FastMarketEvaluationCoordinator

| Check | Method | Result |
|-------|--------|--------|
| EA delegates OnTick | `BasketRecoveryEA.mq5` → `g_applicationContext.OnTick(_Symbol)` | PASS |
| Context routes to coordinator | `ApplicationContext.mqh` → `m_kernel.FastCoordinator().OnTick(symbol)` | PASS |
| Coordinator reads quote once | `CTickQuoteReader::ReadOnce` before basket loop | PASS |
| Symbol index filters baskets | `CSymbolBasketIndex::FindActiveBasketIds(symbol, …)` | PASS |
| No REST/disk/JSON in coordinator | Grep: no `WebRequest`, `FileOpen`, `Json`, `Reconcil`, `Flush` in coordinator | PASS |
| Staging only (no persistent queue) | `ExecuteFastPath(..., m_stagingQueue, …)` | PASS |

### OnTradeTransaction → snapshot + forceReevaluate only

| Check | Method | Result |
|-------|--------|--------|
| No StrategyEngine call | `TradeTransactionFastPathService.mqh` — only snapshot + fast state | PASS |
| Sets forceReevaluate | `CForceReevaluationFlag::Set(state,true)` | PASS |
| Updates lastTransactionUtc | `state.SetLastTransactionUtc(...)` | PASS |
| No file I/O / REST | Service includes only snapshot store + fast state registry | PASS |

### OnTimer slow path

| Check | Method | Result |
|-------|--------|--------|
| Staging flush before RunCycle | `ApplicationTimerPipeline::FlushStagingQueue()` step 2 | PASS |
| Reconciliation on timer only | `ReconciliationSchedulerService.RunIfDue()` | PASS |
| Fallback after health check | `TimerFallbackEvaluationService.RunIfDue()` last | PASS |
| Fallback tick gate | `NotifyTick()` on each OnTick; fallback checks silence window | PASS (unit test) |

### Reconciliation read-only

| Check | Method | Result |
|-------|--------|--------|
| No broker mutation | `BasketPositionReconciler` — no OrderSend/PositionClose | PASS |
| Orphan policy | Suspend basket + audit only | PASS |

### Safety guards

| Check | Method | Result |
|-------|--------|--------|
| Stale quote deferred | `MarketContextProviderAdapter` + `MarketSafetyGuard` | PASS (TestLiveMarketContext) |
| Wide spread deferred | Same | PASS (TestLiveMarketContext) |
| Fast path deferral no suspend | Coordinator `RecordDeferredAudit` only | PASS |

### Unit tests (compile-time, in-memory mocks)

| Test file | Coverage | Compile |
|-----------|----------|---------|
| `TestLiveMarketContext.mq5` | Market guards, reconciliation, timer ordering | 0 errors |
| `TestFastMarketPath.mq5` | TP/recovery triggers, symbol index, forceReevaluate, staging, fallback silence | 0 errors |

---

## Manual MT5 Runtime Checklist

**Status: NOT EXECUTED** — requires MetaTrader 5 GUI attach. Agent environment cannot attach EA to a live/demo chart.

Execute manually before production use:

### Setup

- [ ] **NOT EXECUTED** — Open MT5 demo account with XAUUSD visible
- [ ] **NOT EXECUTED** — Compile `BasketRecoveryEA.mq5` in MetaEditor (verify 0 errors)
- [ ] **NOT EXECUTED** — Attach EA to XAUUSD M1 chart
- [ ] **NOT EXECUTED** — Enable **AutoTrading OFF** (execution disabled)
- [ ] **NOT EXECUTED** — Set `InpApiBaseUrl=""` to disable REST during hot-path observation
- [ ] **NOT EXECUTED** — Enable Experts log (Tools → Options → Expert Advisors → Journal)

### OnTick fast path

- [ ] **NOT EXECUTED** — Confirm journal shows `BasketRecoveryEA v0.0.3 started` with `fast_tick_budget`
- [ ] **NOT EXECUTED** — With ACTIVE basket on XAUUSD, verify tick activity (no timer-only eval lag)
- [ ] **NOT EXECUTED** — Attach second chart (e.g. EURUSD); confirm XAUUSD basket not evaluated on EURUSD ticks
- [ ] **NOT EXECUTED** — Confirm no new files written under `MQL5/Files/BasketRecovery/` during tick burst (only timer flush window)
- [ ] **NOT EXECUTED** — Confirm no WebRequest errors in journal during OnTick-only window

### OnTradeTransaction

- [ ] **NOT EXECUTED** — Manually open/close a tagged basket position (external/manual trade with BRE comment)
- [ ] **NOT EXECUTED** — Verify snapshot updates and next tick triggers evaluation (forceReevaluate)
- [ ] **NOT EXECUTED** — Confirm no strategy commands executed (AutoTrading off)

### OnTimer

- [ ] **NOT EXECUTED** — After fast-path eval, wait for timer; confirm staged commands appear in persistent queue (journal / command processor activity)
- [ ] **NOT EXECUTED** — With normal ticks flowing, confirm fallback does not enqueue eval (no duplicate timer-driven strategy runs)
- [ ] **NOT EXECUTED** — Stop tick feed (disconnect / closed market sim) for `InpTickSilenceFallbackMs`; confirm fallback eval once

### Reconciliation

- [ ] **NOT EXECUTED** — Wait for reconciliation interval; confirm read-only compare runs
- [ ] **NOT EXECUTED** — Verify no positions closed/modified by EA during mismatch scenario

### Safety

- [ ] **NOT EXECUTED** — Simulate stale quote (disconnect briefly); confirm deferred/no-action in diagnostics
- [ ] **NOT EXECUTED** — Confirm no OrderSend / OrderModify / PositionClose in Experts log

### Post-run verification

- [ ] **NOT EXECUTED** — Review `build/trade-api-guard-report.txt` (static guard PASS)
- [ ] **NOT EXECUTED** — Run `scripts/compile-all.ps1` locally after any input changes

---

## Recommendations

1. Complete the manual MT5 checklist above on demo before live deployment.
2. Keep AutoTrading disabled until Trade Execution Engine sprint is explicitly approved.
3. Monitor `InMemoryHotPathDiagnostics` counters via future observability hook if journal visibility is insufficient.

---

## References

- Architecture: `docs/architecture/40-live-market-context-and-reconciliation.md`
- Trade API guard: `build/trade-api-guard-report.txt`
- Static tests: `TestLiveMarketContext.mq5`, `TestFastMarketPath.mq5`
