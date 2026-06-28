# Basket Recovery EA — Project State

Authoritative snapshot for humans and AI assistants. Read this before changing execution or strategy behavior.

**Baseline:** `v0.7.4-pending-terminalization` · commit `51c1f12317234baf230de45eb149b889d1aee43c`  
**Phase:** Controlled demo execution and recovery planning — **not live-money ready**

---

## 1. Project Purpose

Basket Recovery Trading Engine for MetaTrader 5:

- Signal ingestion (REST / command queue)
- Configuration-driven basket strategy (immutable strategy profile hash)
- Live market context and position snapshot reconciliation
- Basket risk engine and projected max-risk gate
- Recovery candidate planning (trigger, volume, zone evaluation)
- **Controlled** manual demo execution and manual demo recovery submission
- Broker transaction correlation and pending execution lifecycle persistence

Target architecture remains clean/hexagonal: domain logic isolated from MT5 broker APIs via ports and adapters.

---

## 2. Current Baseline

| Item | Value |
|------|-------|
| Git tag | `v0.7.4-pending-terminalization` |
| Commit | `51c1f12317234baf230de45eb149b889d1aee43c` |
| Development phase | Sprint 8A documentation refresh; execution sprints 0–7E complete |
| Latest validated demo scope | Manual demo position submission (6G), manual demo recovery candidate submission (7D), pending execution terminalization (7E) |

**Not validated for:** real-money accounts, automatic recovery execution, profit-level partial close, break-even/trailing/risk-reduction execution.

---

## 3. Implemented Capabilities

| Area | Status | Primary reference |
|------|--------|-------------------|
| Clean architecture / ports | Implemented | docs 01, 44 |
| Strategy profile binding + immutable hash | Implemented | docs 32, 35 |
| Signal / command ingestion | Implemented | docs 18, 30 |
| Live market context + fast path | Implemented | docs 40, 41 |
| Basket risk engine | Implemented | doc 53 |
| Projected max-risk gate | Implemented | doc 54 |
| Recovery candidate planner | Implemented | doc 55 |
| Manual demo recovery candidate submission | Validated (7D) | doc 56 |
| Broker correlation + async transaction state machine | Implemented | docs 47, 48 |
| Pending execution terminalization + restart reconcile | Implemented (7E) | doc 59 |
| Manual demo OrderSendAsync (one-shot) | Validated (6G) | doc 52 |
| MT5 OrderCheck dry-run | Validated (6B) | doc 46 |

---

## 4. Safety Boundaries

These are **hard constraints** — do not weaken without explicit sprint approval.

### Automatic execution — disabled

- **No automatic order submission** from StrategyEngine, REST handlers, OnTick, OnTimer, or OnTradeTransaction.
- **Automatic recovery execution is disabled.** Recovery candidates are planned and registered; broker submission requires manual operator route only.

### Manual demo execution only

- Manual recovery submission is **demo-only**, candidate-bound, authorization-bound, one-shot, and session-limited.
- Real-account / live-money support is **not enabled**.
- Only `CMt5AsyncSubmissionGateway` may call `OrderSendAsync`. No other `OrderSend`, `CTrade`, `PositionClose`, or `PositionModify` callers in production paths.

### Pending execution semantics (7E)

| Status | Terminal | Blocks recovery |
|--------|:--------:|:---------------:|
| FILLED, REJECTED, CANCELLED, FAILED, TIMED_OUT, RECONCILED | yes | no |
| UNKNOWN_RECONCILING (`RECONCILING` enum) | no | **yes** |
| In-flight (SUBMITTED, ACKNOWLEDGED, …) | no | yes |

- Recovery step advances **only** after broker-confirmed **FILLED** (idempotent step tracker).
- Startup and periodic reconciliation are **read-only** — no auto-submit or retry-submit on restart.

### Operator caution

Demo terminal with `InpEnableLiveDemoExecution=true` can open **real demo positions**. Use a dedicated demo account and terminal. Do not use production/live-money terminals for validation.

---

## 5. Validated Evidence

Non-sensitive validation facts only:

| Milestone | Evidence |
|-----------|----------|
| OrderCheck dry-run (6B) | Chart-attached EA; `order_check_invoked` diagnostic; compile gate green |
| Manual demo position submission (6G) | Demo `OrderSendAsync` PASS; authorization + trigger token consumption; duplicate blocked |
| Manual demo recovery submission (7D) | Candidate registration → authorization → submission → broker correlation |
| Recovery fill + step advancement (7D/7E) | Broker-confirmed FILLED; step tracker advanced once; idempotent on duplicate transaction |
| Pending terminalization (7E) | `pending_executions.dat` persists terminal state; TIMED_OUT terminal audit; UNKNOWN_RECONCILING blocks recovery |
| Compile gate | EA errors = 0; all `Test*.mq5` errors = 0 (see doc 38 for known warnings) |

Detailed run logs and artifacts live in individual sprint architecture documents — not duplicated here.

---

## 6. Known Gaps / Roadmap

### Intentionally disabled

- Automatic recovery execution (broker submit from planner/trigger)
- Real-money authorization and account support
- StrategyEngine-driven order submission

### Not implemented

- Profit-level partial close execution
- Break-even execution
- Trailing stop execution
- Risk-reduction execution (planner exists; execution path not wired)
- Extended forward demo validation beyond current sprint evidence
- Full Telegram → Python → PostgreSQL production pipeline (MT5-local demo path validated separately)

### Planned / next likely work

- Sprint 8+ documentation and operator runbooks (this sprint)
- Further demo validation hardening
- Execution features above when explicitly scoped in future sprints

---

## 7. Required Development Gate

Before claiming compile success or merging execution changes:

```powershell
scripts/sync-to-mt5.ps1
scripts/compile-all.ps1
git diff --check
```

Requirements: EA errors = 0, all `Test*.mq5` errors = 0, clean whitespace diff.

Known compile warnings (non-blocking): version format warning; `POSITION_COMMISSION` deprecation in tests — see doc 38.

---

## 8. How to Resume Work

Before changing execution or strategy behavior, read in order:

1. **This file** — `docs/PROJECT_STATE.md`
2. **Latest relevant architecture doc** — see `docs/architecture/README.md` index; for execution work start at doc 59 (terminalization) or doc 56 (manual recovery)
3. **Current Git tag/commit** — verify baseline matches table in §2

Do not infer capabilities from root README milestone table alone — architecture docs are authoritative for behavior.

---

## Quick Navigation

| Need | Document |
|------|----------|
| Full architecture index | [architecture/README.md](architecture/README.md) |
| Safety + demo authorization | [50-live-submission-safety-and-demo-authorization.md](architecture/50-live-submission-safety-and-demo-authorization.md) |
| Manual demo OrderSendAsync | [51-manual-demo-ordersendasync-submission.md](architecture/51-manual-demo-ordersendasync-submission.md) |
| Recovery candidate planning | [55-recovery-candidate-planning.md](architecture/55-recovery-candidate-planning.md) |
| Manual recovery validation | [56-manual-demo-recovery-candidate-validation.md](architecture/56-manual-demo-recovery-candidate-validation.md) |
| Pending execution lifecycle | [59-pending-execution-terminalization.md](architecture/59-pending-execution-terminalization.md) |
| MT5 deploy + compile | [../mt5/README.md](../mt5/README.md) |
| Documentation audit (8A) | [60-documentation-state-audit.md](architecture/60-documentation-state-audit.md) |
