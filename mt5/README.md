# MT5 Deployment

Expert Advisor and MQL5 library for Basket Recovery Trading Engine.

> **Demo-only execution caution:** When `InpEnableLiveDemoExecution` is enabled, the EA can submit **real demo orders** via `OrderSendAsync`. Use a dedicated demo account. **Not for live-money terminals.** Automatic recovery execution is **disabled**.

## Sync and Compile (recommended)

From repository root:

```powershell
scripts/sync-to-mt5.ps1
scripts/compile-all.ps1
git diff --check
```

This copies `mt5/` into the active MetaTrader 5 `MQL5` folder and compiles the EA plus all `Test*.mq5` scripts.

**Gate requirements:** EA errors = 0, all test script errors = 0.

Compile logs: `build/logs/` (repo root).

## Manual Deploy (alternative)

Copy into your MetaTrader 5 data folder:

```
<MQL5>/
├── Experts/BasketRecovery/BasketRecoveryEA.mq5
├── Include/BasketRecovery/...
└── Files/BasketRecovery/...
```

Compile `Experts/BasketRecovery/BasketRecoveryEA.mq5` in MetaEditor (F7).

## Expected Compile Warnings

Non-blocking warnings documented in [docs/architecture/38-compile-warning-register.md](../docs/architecture/38-compile-warning-register.md):

| ID | Warning | Notes |
|----|---------|-------|
| W-001 | Version format | Market version string format in EA metadata |
| W-002 | `POSITION_COMMISSION` deprecation | Test scripts referencing deprecated MT5 constant |

These do not fail the compile gate.

## Execution Safety Rules

1. **Automatic execution disabled** — StrategyEngine, OnTick, OnTimer, OnTradeTransaction, and REST paths do not submit orders.
2. **One OrderSendAsync gateway** — only `CMt5AsyncSubmissionGateway` calls `OrderSendAsync`.
3. **Manual demo routes only** — position and recovery submission require explicit demo authorization + trigger tokens.
4. **Recovery step** advances only after broker-confirmed FILLED.

See [docs/PROJECT_STATE.md](../docs/PROJECT_STATE.md) for full safety boundaries.

## Tests

Run from MetaEditor: `Scripts/BasketRecovery/Tests/Test*.mq5`

Key suites: strategy integration, execution contract, simulated submission, pending execution correlation/terminalization, recovery planner, risk gate, manual demo submission.

## Current Scope (not Sprint 0)

The EA includes: application kernel, basket aggregate, persistence, REST ingestion, strategy engine, fast market path, risk engine, recovery candidate planner, manual demo submission services, async broker correlation, and pending execution lifecycle persistence.

Validation evidence: architecture docs 46 (OrderCheck), 52 (OrderSendAsync), 56 (manual recovery), 59 (terminalization).

## Project State

Authoritative capability and safety summary: [docs/PROJECT_STATE.md](../docs/PROJECT_STATE.md)
