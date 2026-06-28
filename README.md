# Basket Recovery Trading Engine

Production-grade MetaTrader 5 Expert Advisor — basket strategy, dynamic risk management, recovery candidate planning, and **controlled demo-only** manual execution.

> **Not ready for live-money use.** Automatic order submission and automatic recovery execution are disabled. Demo manual routes can open real demo positions when explicitly enabled.

## Project Status

| Item | Value |
|------|-------|
| Baseline tag | `v0.7.4-pending-terminalization` |
| Phase | Controlled demo execution + recovery planning (Sprints 0–7E) |
| Authoritative state | [docs/PROJECT_STATE.md](docs/PROJECT_STATE.md) |

Implemented: clean architecture, strategy profiles, REST/command ingestion, live market context, basket risk engine, projected max-risk gate, recovery candidate planner, manual demo submission, broker correlation, pending execution terminalization.

**Intentionally disabled:** automatic recovery execution, real-account support, strategy-driven order submission.

## Architecture Summary

```
Signals / REST → Command Queue → Handlers → Event Bus
                              ↓
                    Strategy Engine (evaluate only)
                              ↓
              Risk Engine ← Position Snapshot ← Broker reconcile
                              ↓
              Recovery Candidate Planner (no auto-submit)
                              ↓
         Manual demo authorization → OrderSendAsync gateway (demo only)
                              ↓
              OnTradeTransaction → pending execution terminalize → step tracker
```

Hexagonal layout: domain logic in `mt5/Include/BasketRecovery/Domain/`, application services in `Application/`, MT5 adapters in `Infrastructure/`.

Full index: [docs/architecture/README.md](docs/architecture/README.md)

## Safety Disclaimer

- **Demo account required** for any live demo execution input (`InpEnableLiveDemoExecution`).
- **One `OrderSendAsync` gateway** — `CMt5AsyncSubmissionGateway` only.
- **No automatic submission** from StrategyEngine, REST, OnTick, OnTimer, or OnTradeTransaction.
- Manual recovery route: candidate-bound, authorization-bound, one-shot, session-limited.
- Recovery step advances only after broker-confirmed **FILLED**.
- `TIMED_OUT` is terminal audit (does not block recovery); `UNKNOWN_RECONCILING` blocks recovery until read-only reconcile resolves.
- Do not attach to live-money terminals for validation or experimentation.

## Current Execution Scope

| Capability | Status |
|------------|--------|
| Strategy evaluation + recovery planning | Active (no broker submit) |
| Manual demo position submission | Validated (Sprint 6G) |
| Manual demo recovery submission | Validated (Sprint 7D) |
| Pending execution persist + restart reconcile | Sprint 7E |
| Automatic recovery execution | **Disabled** |
| Profit partial close / BE / trailing / risk-reduction exec | **Not implemented** |

## Build and Test

Sync source to the active MT5 terminal and compile:

```powershell
scripts/sync-to-mt5.ps1
scripts/compile-all.ps1
git diff --check
```

Requirements: EA errors = 0, all `Test*.mq5` errors = 0.

Run individual test scripts from MetaEditor: `mt5/Scripts/BasketRecovery/Tests/Test*.mq5`.

MT5 deployment details: [mt5/README.md](mt5/README.md)

## Documentation Navigation

| Document | Purpose |
|----------|---------|
| [docs/PROJECT_STATE.md](docs/PROJECT_STATE.md) | **Start here** — current capabilities, safety, gaps |
| [docs/architecture/README.md](docs/architecture/README.md) | Full architecture index (docs 01–60) |
| [docs/architecture/59-pending-execution-terminalization.md](docs/architecture/59-pending-execution-terminalization.md) | Latest execution lifecycle |
| [docs/architecture/56-manual-demo-recovery-candidate-validation.md](docs/architecture/56-manual-demo-recovery-candidate-validation.md) | Manual recovery validation |
| [docs/architecture/60-documentation-state-audit.md](docs/architecture/60-documentation-state-audit.md) | Sprint 8A documentation audit |

## Milestones

| Tag | Scope |
|-----|-------|
| `v0.4.0-strategy-integration` | Strategy profile basket integration (R-3) |
| `v0.5.1-fast-market-path` | Fast market path + runtime validation |
| `v0.6.1-mt5-dry-run` | MT5 OrderCheck dry-run execution |
| `v0.6.6-manual-demo-ordersendasync-submission` | Manual demo OrderSendAsync submission |
| `v0.7.0-live-basket-risk-engine` | Live basket risk engine |
| `v0.7.1-recovery-projected-risk-gate` | Recovery projected max-risk gate |
| `v0.7.2-recovery-candidate-planner` | Recovery candidate planning |
| `v0.7.3-manual-demo-recovery-validation` | Manual demo recovery candidate validation |
| `v0.7.4-pending-terminalization` | Pending execution terminalization + restart reconcile |

## v2 Architecture Pillars

| Pillar | Document |
|--------|----------|
| Command Queue (idempotent) | [18-command-queue.md](docs/architecture/18-command-queue.md) |
| Event Bus | [19-event-bus.md](docs/architecture/19-event-bus.md) |
| Transition Rules | [20-transition-rules.md](docs/architecture/20-transition-rules.md) |
| Trade Executor (broker port) | [21-trade-executor.md](docs/architecture/21-trade-executor.md) |
| Position Snapshot | [22-position-snapshot.md](docs/architecture/22-position-snapshot.md) |
| Configuration Profiles | [23-configuration-profiles.md](docs/architecture/23-configuration-profiles.md) |
| Strategy Domain | [32-strategy-domain-refactor.md](docs/architecture/32-strategy-domain-refactor.md) |
