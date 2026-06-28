# Basket Recovery Trading Engine — Architecture Documentation

> **Status:** Active — Sprints 0 through 7E implemented; baseline `v0.7.4-pending-terminalization`
> **Authoritative project snapshot:** [../PROJECT_STATE.md](../PROJECT_STATE.md)
> **Last index update:** Sprint 8A (2026-06-28)

## Document Map

### Core Architecture (v1)

| # | Document | Summary |
|---|----------|---------|
| 01 | [01-software-architecture.md](./01-software-architecture.md) | Layers, SOLID, v2 architecture overview |
| 02 | [02-folder-structure.md](./02-folder-structure.md) | MT5 + Python repo layout |
| 03 | [03-class-diagram.md](./03-class-diagram.md) | Class diagrams (Mermaid) |
| 04 | [04-module-responsibilities.md](./04-module-responsibilities.md) | Module responsibilities |
| 05 | [05-data-flow.md](./05-data-flow.md) | Data flow |
| 06 | [06-sequence-diagrams.md](./06-sequence-diagrams.md) | Sequence diagrams |
| 07 | [07-state-machine.md](./07-state-machine.md) | Lifecycle + mode state machines |
| 08 | [08-risk-engine.md](./08-risk-engine.md) | Snapshot-based risk engine design |
| 09 | [09-recovery-engine.md](./09-recovery-engine.md) | Recovery engine design |
| 10 | [10-basket-engine.md](./10-basket-engine.md) | Basket engine |
| 11 | [11-rest-communication.md](./11-rest-communication.md) | REST → command ingestion |
| 12 | [12-persistence-strategy.md](./12-persistence-strategy.md) | Persistence strategy |
| 13 | [13-restart-recovery.md](./13-restart-recovery.md) | MT5 restart recovery |
| 14 | [14-error-handling.md](./14-error-handling.md) | Error handling |
| 15 | [15-logging-strategy.md](./15-logging-strategy.md) | Logging |
| 16 | [16-future-extensions.md](./16-future-extensions.md) | Extension points |
| 17 | [17-implementation-roadmap.md](./17-implementation-roadmap.md) | Original sprint roadmap (v2) |

### v2 Production Patterns

| # | Document | Summary |
|---|----------|---------|
| 18 | [18-command-queue.md](./18-command-queue.md) | Idempotent command queue |
| 19 | [19-event-bus.md](./19-event-bus.md) | Domain event bus |
| 20 | [20-transition-rules.md](./20-transition-rules.md) | Explicit transition rule table |
| 21 | [21-trade-executor.md](./21-trade-executor.md) | Trade executor port (broker boundary) |
| 22 | [22-position-snapshot.md](./22-position-snapshot.md) | In-memory position snapshot |
| 23 | [23-configuration-profiles.md](./23-configuration-profiles.md) | Profile-based configuration |
| 24 | [24-backtesting-adapter.md](./24-backtesting-adapter.md) | Backtest execution environment |
| 25 | [25-architecture-review-v2.md](./25-architecture-review-v2.md) | Review checklist + remaining weaknesses |
| 26 | [26-sprint-0.1-audit-fixes.md](./26-sprint-0.1-audit-fixes.md) | Sprint 0.1 audit fixes |
| 27 | [27-sprint-1-kernel-foundation.md](./27-sprint-1-kernel-foundation.md) | Application kernel foundation |
| 28 | [28-sprint-2-basket-aggregate.md](./28-sprint-2-basket-aggregate.md) | Basket aggregate + handlers |
| 29 | [29-sprint-3-persistence.md](./29-sprint-3-persistence.md) | File-backed persistence |
| 30 | [30-sprint-4-rest-ingestion.md](./30-sprint-4-rest-ingestion.md) | REST command ingestion |
| 31 | [31-sprint-5-trade-execution.md](./31-sprint-5-trade-execution.md) | Sprint 5 trade execution (historical scope) |

### Strategy Domain

| # | Document | Summary |
|---|----------|---------|
| 32 | [32-strategy-domain-refactor.md](./32-strategy-domain-refactor.md) | Strategy engine, plans, JSON schema |
| 33 | [33-sprint-r1-strategy-domain-foundation.md](./33-sprint-r1-strategy-domain-foundation.md) | Sprint R-1 strategy domain |
| 34 | [34-sprint-r2-strategy-engine.md](./34-sprint-r2-strategy-engine.md) | Sprint R-2 pure strategy evaluator |

### Strategy Integration + Compile Stabilization (35–39)

| # | Document | Summary |
|---|----------|---------|
| 35 | [35-sprint-r3-strategy-basket-integration.md](./35-sprint-r3-strategy-basket-integration.md) | Strategy profile bound to basket lifecycle and persistence v3 |
| 36 | [36-sprint-r3-1-strategy-command-wiring.md](./36-sprint-r3-1-strategy-command-wiring.md) | Strategy command/event handler wiring and migration |
| 36b | [36-compile-stabilization-root-causes.md](./36-compile-stabilization-root-causes.md) | Compile error root-cause inventory and fixes |
| 37 | [37-mql5-object-copy-ownership-policy.md](./37-mql5-object-copy-ownership-policy.md) | MQL5 object copy and ownership policy |
| 38 | [38-compile-warning-register.md](./38-compile-warning-register.md) | Known compile warnings register |
| 39 | [39-r3.1-gap-analysis.md](./39-r3.1-gap-analysis.md) | R-3.1 strategy wiring gap analysis |

### Runtime + Execution Foundation (40–44)

| # | Document | Summary |
|---|----------|---------|
| 40 | [40-live-market-context-and-reconciliation.md](./40-live-market-context-and-reconciliation.md) | Fast/slow path, OnTick/OnTimer/OnTradeTransaction flows |
| 41 | [41-sprint-5-runtime-validation.md](./41-sprint-5-runtime-validation.md) | Sprint 5 runtime validation checklist |
| 42 | [42-runtime-observability-and-object-ownership.md](./42-runtime-observability-and-object-ownership.md) | Diagnostic mode, ownership graph, shutdown order |
| 43 | [43-execution-contract-and-simulated-broker.md](./43-execution-contract-and-simulated-broker.md) | Execution contract and simulated broker executor |
| 44 | [44-execution-port-compatibility-audit.md](./44-execution-port-compatibility-audit.md) | Execution port compatibility audit (Sprint 6A.1) |

### MT5 Dry-Run + Async Correlation (45–49)

| # | Document | Summary |
|---|----------|---------|
| 45 | [45-mt5-dry-run-execution-validation.md](./45-mt5-dry-run-execution-validation.md) | MT5 request translation and OrderCheck dry-run |
| 46 | [46-sprint-6b-manual-ordercheck-validation.md](./46-sprint-6b-manual-ordercheck-validation.md) | Manual OrderCheck chart validation evidence |
| 47 | [47-async-execution-correlation-and-transaction-state-machine.md](./47-async-execution-correlation-and-transaction-state-machine.md) | Async correlation and trade transaction state machine |
| 48 | [48-submission-preparation-and-correlation-envelope.md](./48-submission-preparation-and-correlation-envelope.md) | Submission preparation and broker correlation envelope |
| 49 | [49-simulated-submission-and-acknowledgement-path.md](./49-simulated-submission-and-acknowledgement-path.md) | Simulated gateway submission and acknowledgement path |

### Live Safety + Demo Submission (50–52)

| # | Document | Summary |
|---|----------|---------|
| 50 | [50-live-submission-safety-and-demo-authorization.md](./50-live-submission-safety-and-demo-authorization.md) | Live submission safety gate and demo authorization tokens |
| 51 | [51-manual-demo-ordersendasync-submission.md](./51-manual-demo-ordersendasync-submission.md) | Manual one-shot demo OrderSendAsync submission design |
| 52 | [52-sprint-6g-real-demo-ordersendasync-validation.md](./52-sprint-6g-real-demo-ordersendasync-validation.md) | Real demo OrderSendAsync chart validation PASS evidence |

### Risk + Recovery Planning (53–56)

| # | Document | Summary |
|---|----------|---------|
| 53 | [53-live-basket-risk-and-projected-sl-risk.md](./53-live-basket-risk-and-projected-sl-risk.md) | Live basket risk engine and projected SL risk |
| 54 | [54-recovery-projected-risk-enforcement.md](./54-recovery-projected-risk-enforcement.md) | Recovery projected max-risk enforcement gate |
| 55 | [55-recovery-candidate-planning.md](./55-recovery-candidate-planning.md) | Recovery candidate planner (no auto-submit) |
| 56 | [56-manual-demo-recovery-candidate-validation.md](./56-manual-demo-recovery-candidate-validation.md) | Manual demo recovery candidate validation (7D) |

### Sprint Reports + Documentation (57–60)

| # | Document | Summary |
|---|----------|---------|
| 57 | [57-sprint-7d-validation-blocker-report.md](./57-sprint-7d-validation-blocker-report.md) | Sprint 7D validation blocker diagnostic report |
| 58 | [58-readme-gap-audit.md](./58-readme-gap-audit.md) | README gap audit (pre–Sprint 8A) |
| 59 | [59-pending-execution-terminalization.md](./59-pending-execution-terminalization.md) | Pending execution terminalization and restart reconciliation (7E) |
| 60 | [60-documentation-state-audit.md](./60-documentation-state-audit.md) | Sprint 8A documentation state audit |

## System Overview (v2)

```
Telegram → Python → PostgreSQL → REST → Command Queue → Handlers
                                              ↓
                                       Event Bus → Subscribers
                                              ↓
                          Strategy Engine (evaluate — no auto-submit)
                                              ↓
                        Position Snapshot ← Risk Engine ← Reconciliation
                                              ↓
                          Recovery Candidate Planner (plan only)
                                              ↓
              Manual demo auth → CMt5AsyncSubmissionGateway (demo only)
                                              ↓
                   OnTradeTransaction → terminalize pending → step tracker
```

## Safety (current)

- **Automatic recovery execution disabled**
- **No automatic order submission** from strategy, REST, OnTick, OnTimer, or OnTradeTransaction
- **One OrderSendAsync gateway** — `CMt5AsyncSubmissionGateway`
- **Demo manual routes only** — not live-money ready
- **TIMED_OUT** = terminal audit; **UNKNOWN_RECONCILING** = sole uncertain blocking state

See [59-pending-execution-terminalization.md](./59-pending-execution-terminalization.md) and [../PROJECT_STATE.md](../PROJECT_STATE.md).

## Historical vs Authoritative

| Type | Documents |
|------|-----------|
| **Authoritative for current behavior** | 50–56, 59, [PROJECT_STATE.md](../PROJECT_STATE.md) |
| **Historical / sprint record** | 17, 31, 57, 58 |
| **Design reference (may predate implementation)** | 01–16, 21, 25 |

When documents conflict, prefer the latest sprint doc for that area and `PROJECT_STATE.md` for overall status.

## Critical Notes

1. **Strategy profile hash** is immutable per basket binding — see doc 35.
2. **RECOVERY / TARGET_RISK** are mode flags, not lifecycle states — see doc 07.
3. **Two-phase loop:** command process and event dispatch must not nest on same stack — doc 25.
4. **Production gate checklist** in doc 25 remains relevant; demo validation docs 46/52/56/59 add execution-specific evidence.
