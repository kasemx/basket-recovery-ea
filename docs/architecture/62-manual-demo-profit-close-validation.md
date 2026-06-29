# 62 — Manual Demo Profit-Level Partial-Close Validation (Sprint 8C)

## Scope

Sprint 8C adds **controlled broker validation only** for a **single-instruction**, **DUE** profit-level partial-close candidate on **DEMO** accounts. Automatic partial-close execution remains **disabled**.

| Allowed | Not allowed |
|---|---|
| One explicit manual close via existing `CDemoManualSubmissionService` → `CMt5AsyncSubmissionGateway` | StrategyEngine, REST, OnTick, automatic OnTimer, OnTradeTransaction close submission |
| Exactly one `PositionReductionInstruction` | Multi-position / multi-instruction close plans |
| Hedging account with explicit position ticket | Netting / ambiguous position model partial-close |
| Demo account | Real-money accounts |

## Account position model

`CMt5AccountPositionModelProvider` reads `ACCOUNT_MARGIN_MODE`:

| Model | Manual profit-close route |
|---|---|
| `RETAIL_HEDGING` | Allowed when candidate binds an explicit position ticket |
| `RETAIL_NETTING` | Rejected — symbol-level partial-close semantics not proven |
| `EXCHANGE` / `UNKNOWN` | Rejected before broker submission |

Rule: never close a different position merely because symbol and side match.

## Manual close flow

1. **Planning (read-only, Sprint 8B):** `CProfitLevelCloseCandidatePlanningService` emits audit/events; does not submit orders.
2. **Registration:** `CManualProfitCloseCandidateRegistrationService` accepts only `DUE` candidates with `ReductionCount()==1` on hedging accounts; writes `CManualProfitCloseCandidateEntry` to `CManualProfitCloseCandidateRegistry` (default TTL `InpManualProfitCloseCandidateExpirySeconds = 30`).
3. **Operator selection:** EA inputs:
   - `InpExecutionMode = DEMO_MANUAL_SUBMISSION`
   - `InpEnableLiveDemoExecution = true`
   - `InpRequireManualDemoAuthorization = true`
   - `InpManualProfitCloseCandidateId`
   - `InpManualDemoAuthorizationToken`
   - `InpManualProfitCloseSubmissionTriggerToken`
4. **Revalidation:** `CProfitCloseCandidateSubmissionValidator` immediately before submission.
5. **Sealed request:** `CProfitCloseCandidateExecutionRequestFactory` → `intent=CLOSE_POSITION`, `reason=PROFIT_LEVEL_CLOSE`, fields immutable from candidate.
6. **Submission:** `CManualProfitCloseSubmissionService` → `CDemoManualSubmissionService` (existing gateway only).
7. **Completion ordering:** broker transaction correlation → pending terminalization + persistence → confirmed close-fill validation → profit-level progress completion → audit/event.

## Revalidation matrix

| Check | Reject without broker call | Consumes trigger |
|---|---|---|
| Candidate expired | Yes | No |
| Candidate not `DUE` / not eligible registry status | Yes | No |
| Basket not ACTIVE | Yes | No |
| Basket version / strategy hash mismatch | Yes | No |
| Unresolved pending execution | Yes | No |
| Profit level already completed | Yes | No |
| Stale quote | Yes | No |
| Non-DEMO account | Yes | No |
| Unsupported position model | Yes | No |
| Selected position missing / symbol-direction mismatch | Yes | No |
| Close direction not opposite position | Yes | No |
| Invalid / excessive close volume | Yes | No |
| Replanned candidate no longer DUE or volume/ticket changed | Yes | No |
| Preparation failure | Yes | No |
| `OrderSendAsync` attempt (success or broker reject) | No | **Yes** |
| Authorization token | — | After broker attempt (existing demo auth policy) |

## Sealed request rules

`CProfitCloseCandidateExecutionRequestFactory::CreateCloseRequest` binds only from `CManualProfitCloseCandidateEntry`:

- `symbol`, `positionTicket`, `closeDirection`, `proposedCloseVolume`, `basketId`, `basketVersion`, `strategyProfileHash`
- Operator/UI cannot override these fields on submission.
- Request is sealed (`IsSealed()==true`).

## Profit-level completion rules

- Submission acceptance does **not** complete the profit level.
- Broker reject/timeout does **not** complete the level.
- Only **confirmed close fill** (pending entry `FILLED` → `OnBrokerFillConfirmed`) may:
  1. Mark `CProfitLevelCloseExecutionTracker` filled once
  2. Apply `ApplyProfitLevelCloseCompleted` on basket aggregate
  3. Emit `ProfitLevelCloseConfirmed` and `ProfitLevelMarkedCompleted`
- Duplicate fill notifications do not complete twice (`TryMarkFilled` idempotency).

## Events (generic names only)

- `ProfitLevelCloseCandidateAvailable` (planning + manual registry)
- `ProfitLevelCloseCandidateManuallySelected`
- `ProfitLevelCloseSubmissionRejected`
- `ProfitLevelCloseSubmissionSubmitted`
- `ProfitLevelCloseConfirmed`
- `ProfitLevelMarkedCompleted`

No TP1/TP2/TP3 event names.

## Session policy

- Maximum **one successful** profit-close submission per demo session (`MaxProfitCloseSubmissionsPerSession = 1`).
- One-shot trigger token consumed only after actual `OrderSendAsync` attempt.

## Explicit non-goals (unchanged)

- No automatic partial-close execution.
- No `PositionClose` / `CTrade` shortcuts.
- No new `OrderSendAsync` caller (only existing `CMt5AsyncSubmissionGateway`).
- Domain/Application remain free of direct MT5 APIs except infrastructure adapters.

## Key types

| Type | Role |
|---|---|
| `CManualProfitCloseCandidateRegistry` | Manual close candidate registry |
| `CManualProfitCloseCandidateEntry` | Registry entry with ticket, volumes, trigger metadata |
| `CProfitCloseManualAuthorizationContext` | Candidate-bound authorization fingerprint |
| `CProfitCloseCandidateSubmissionValidator` | Pre-submit revalidation |
| `CProfitCloseCandidateExecutionRequestFactory` | Sealed close request |
| `CManualProfitCloseSubmissionService` | Manual submit + fill completion hook |

## Tests

`TestManualProfitCloseCandidateValidation.mq5` covers registration, revalidation, sealed binding, trigger policy, fill completion idempotency, pending lifecycle, wiring guards, and gateway call path.

## Validation tooling isolation (Sprint 8C)

Sprint 8C broker-validation assets are **tooling-only** and live outside production execution paths:

| Location | Contents |
|---|---|
| `mt5/Scripts/BasketRecovery/Validation/Sprint8C/` | Chart/seed/register/preflight MQL5 scripts |
| `mt5/Include/BasketRecovery/Validation/Sprint8C/` | `ManualProfitCloseCandidateValidationArtifact.mqh` (validation I/O only) |
| `scripts/validation/` | `run-sprint8c-preflight.ps1`, `run-sprint8c-ea-chart-validation.ps1` |

These paths are **not** referenced from `Bootstrapper.mqh`, normal EA startup, `CManualProfitCloseCandidateRegistrationService`, or `CManualProfitCloseSubmissionService`. Generated proof files, tokens, terminal hashes, and account IDs must not be committed.

### Terminal selection (preflight runner)

`scripts/validation/run-sprint8c-preflight.ps1` must target exactly one intended DEMO terminal. It no longer defaults to a hardcoded FTMO data folder.

**Explicit selection (recommended):**

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validation/run-sprint8c-preflight.ps1 `
  -TerminalDataId <32-char-terminal-data-id>
```

The runner validates that the terminal data folder and `config` / `origin.txt` exist, prints the selected ID and path, then runs `PreflightSprint8cDemoProfitClose.mq5` only against that install.

**Auto-selection (optional):**

When `-TerminalDataId` is omitted:

1. Discover running `terminal64.exe` instances.
2. Map the running instance to a terminal data path from recent terminal logs (`Terminal <data-path>` line).
3. Proceed only when exactly one unambiguous candidate is found.
4. Require discoverable **DEMO** server classification from the latest log (`*Demo*` in server name).
5. Abort on zero candidates, multiple running terminals, multiple data-path matches, or non-DEMO classification.

The runner never silently falls back to an unrelated historical terminal (for example the old FTMO data folder).

Before MQL preflight launch, the runner prints:

- selected `TerminalDataId` and data path;
- whether `terminal64.exe` is currently running;
- discoverable server/login/classification hints from the latest log.

Preflight safety gates are unchanged: `RETAIL_HEDGING` mandatory, `RETAIL_NETTING` blocked, unresolved pending records blocked, no broker mutation.

## Real demo validation (Sprint 8C chart run)

Controlled chart validation uses `scripts/validation/run-sprint8c-preflight.ps1` and `scripts/validation/run-sprint8c-ea-chart-validation.ps1` against a configured **DEMO** terminal only. The runners do not change login, commit artifacts, or enable automatic partial-close execution.

### Preconditions checked at preflight / seed

| Check | Required | Observed (latest run) |
|---|---|---|
| Account mode | DEMO | DEMO |
| Position model | RETAIL_HEDGING | RETAIL_NETTING |
| Algo Trading | enabled | enabled |
| Chart trading | enabled | enabled |
| Unresolved pending executions | zero after read-only reconciliation | blocked (non-zero before hedging gate) |
| Symbol positions (primary seed) | none unrelated | none before seed |
| Partial-close volume feasible | yes | yes (0.02 seed → 0.01 close) |

### Outcome

Broker validation was **intentionally not attempted** on the latest run. The seed/preflight phase stopped before any basket seed, candidate registration, or manual profit-close submission because the configured demo terminal reported `RETAIL_NETTING`.

Sprint 8C manual profit-close route requires explicit ticket binding on **RETAIL_HEDGING** only; netting rejection is **expected safety behavior**, not a defect to bypass.

- **`OrderSendAsync` call count:** zero
- **Profit level completion via broker fill:** none
- **Automatic partial-close execution:** remains disabled

Successful broker validation remains **pending** a separate **DEMO + RETAIL_HEDGING** account.

### Evidence chain status (blocked run)

| Step | Status |
|---|---|
| `ProfitLevelCloseCandidateAvailable` | Not reached (register/submit not run) |
| DUE + single instruction | Not reached |
| Manual selection + revalidation | Not reached |
| Sealed `CLOSE_POSITION` request | Not reached |
| `OrderSendAsync` (exactly once) | **Not invoked** |
| Pending terminalization + fill | Not reached |
| `ProfitLevelCloseConfirmed` / `ProfitLevelMarkedCompleted` | Not reached |

### Negative tests (blocked run)

| Test | Expected | Result |
|---|---|---|
| Duplicate trigger | reject, no second async | Not executed |
| Expired candidate | reject pre-broker | Not executed |
| Stale/invalid volume | reject pre-broker | Not executed |
| Terminal pending + read-only evaluate | planning continues | Not executed |

### To complete real demo validation

1. Prepare a **DEMO + RETAIL_HEDGING** account on the validation terminal.
2. Run preflight with explicit terminal selection and confirm `hedging_demo_ready=true` and `unresolved_after_reconcile=0`:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validation/run-sprint8c-preflight.ps1 `
  -TerminalDataId <your-demo-terminal-data-id>
```

3. Resolve any `blocking_execution_ids` via normal EA startup reconciliation or supported broker lifecycle completion — do not delete pending records manually.
4. Ensure no unrelated open positions on the validation symbol.
5. Run: `powershell -ExecutionPolicy Bypass -File scripts/validation/run-sprint8c-ea-chart-validation.ps1 -Reseed`
6. Confirm `sprint-8c-ea-chart-result.txt` reports `chart_validation_passed=true` and `ordersend_async_call_count=1`.

Unit/integration coverage for the manual route remains in `TestManualProfitCloseCandidateValidation.mq5` (compile gate).
