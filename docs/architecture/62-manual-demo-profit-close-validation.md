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
