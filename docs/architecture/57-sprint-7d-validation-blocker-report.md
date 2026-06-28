# Sprint 7D — Manual Demo Recovery Validation Blocker Report

**Date:** 2026-06-28  
**Terminal:** DEMO `81A933A9AFC5DE3C23B15CAB19C63850` (VantageMarkets-Demo, account `25676579`)  
**Scope:** Diagnostic only — no further trial-and-error in this session.

## Executive summary

Manual demo recovery validation reaches **sealed request creation and submission preparation** but **never invokes `OrderSendAsync`**. The primary run fails with an empty rejection (`reason=NONE`). A follow-up duplicate-trigger run in a fresh EA session fails earlier with **missing in-memory pending execution entry**, even though preparation appears to succeed again.

---

## 1. Phase status (latest orchestrator run ~21:19–21:20 UTC)

| Phase | Status | Evidence |
|-------|--------|----------|
| Basket seed | **PASS** | `SeedSprint7dManualRecoveryCandidate` logs `recovery_active=true`, basket `sprint7d-demo-btc-001` |
| Candidate generation (planner DUE) | **PASS** | Register log: `status=DUE`, `projected_max_risk_allowed=true` |
| Candidate registry admission | **PASS** | `BRE manual_recovery_candidate_available`, artifact `sprint-7d-live-candidate.txt` |
| Candidate expiry (negative) | **PASS** | 21:16:39 `detail=Manual recovery candidate expired` for `sprint7d-neg-expiry-001` |
| Risk gate (registration) | **PASS** | `projected_sl_risk=0.1911`, `max_risk=120.5315` after tick-value + equity fixes |
| Manual authorization | **PASS** | `IssueSprint7dRecoveryAuthToken` issued token for `recovery-manual:374324640-0EE7-54C4` |
| Revalidation at submit | **PASS** (latest primary) | `BRE manual_recovery_candidate_revalidation=passed` |
| Sealed request creation | **PASS** | `BRE manual_recovery_sealed_request_created \| sealed=true` |
| **OrderSendAsync route** | **FAIL — current blocker** | No `ordersend_async` log; `positions=0` after submit |
| OnTradeTransaction correlation | **NOT REACHED** | No recovery-path transaction logs |
| Recovery-step tracker | **NOT REACHED** | No `recovery_step_execution_tracker \| filled=true` |
| Duplicate trigger (negative) | **PARTIAL** | Second attach: `Pending execution entry not found` |
| Stale / pending negatives | **FAIL / incomplete** | Primary still blocked; evidence collector `manual_recovery_selected=false` |

---

## 2. Latest error (primary attempt)

**Timestamp:** 2026-06-28 21:20:12 UTC  
**Source log:** `%APPDATA%\MetaQuotes\Terminal\81A933A9AFC5DE3C23B15CAB19C63850\MQL5\Logs\20260628.log`

```
BRE manual_recovery_candidate_manually_selected | candidate_id=recovery-candidate:sprint7d-demo-btc-001:step:1:q:0 | basket_id=sprint7d-demo-btc-001 | step=1
BRE manual_recovery_candidate_revalidation=passed | candidate_id=recovery-candidate:sprint7d-demo-btc-001:step:1:q:0 | projected_sl_risk=0.1911 | max_risk=120.5315
BRE manual_recovery_sealed_request_created | candidate_id=recovery-candidate:sprint7d-demo-btc-001:step:1:q:0 | execution_request_id=recovery-manual:374324640-0EE7-54C4 | sealed=true
BRE broker_state_after | positions=0 | orders=0 | deals_history=0
Manual recovery submission rejected | reason=NONE | detail=
```

**Emitting code:** `BasketRecoveryEA.mq5` → `TryAttemptManualRecoverySubmission()` (Print at rejection branch).

**Root call chain:**

1. `CManualRecoveryCandidateSubmissionValidationService::TryProcessManualRecoverySubmission`
2. `CManualRecoveryCandidateSubmissionService::TrySubmitRecoveryCandidate` — preparation succeeds (`m_preparer.Prepare`)
3. `CDemoManualSubmissionService::TrySubmit` — returns `CDemoManualSubmissionResult::Submitted(...)` with `IsSuccess()==false`, `RejectionReason()==BRE_LIVE_SAFETY_NONE`, empty `Detail()`
4. Mapping: `DemoManualSubmissionService.mqh` L204–233 — `CSubmitPreparedExecutionUseCase::Execute` failure is **not** mapped to `Rejected()`; only `Submitted()` with non-`SUBMITTED` status

**Duplicate-trigger follow-up (21:20:24 UTC, fresh EA session):**

```
Manual recovery submission rejected | reason=REQUEST_NOT_FOUND | detail=Pending execution entry not found
```

**Emitting validation:** `CPreparedSubmissionValidator::Validate()` L36–40 (`PreparedSubmissionValidator.mqh`), called from `CDemoManualSubmissionService::TrySubmit` L156–157.

**Likely mechanism (duplicate):** `CExecutionSubmissionPreparer::Prepare` L171–180 returns a **cached reusable envelope from `IPendingExecutionStore` without upserting `CPendingExecutionRegistry`**. New EA process has empty in-memory registry → validator cannot find QUEUED entry.

**Likely mechanism (primary):** Registry entry exists (otherwise would be `REQUEST_NOT_FOUND`), but `CSubmitPreparedExecutionUseCase::Execute` fails **before** `m_gateway.Submit` (`brokerInvoked=false`). Failure reason/message is discarded by `Submitted()` mapping → opaque `reason=NONE`.

---

## 3. Expected vs actual state (latest primary run)

| Field | Expected | Actual |
|-------|----------|--------|
| Basket lifecycle | `ACTIVE` | `ACTIVE` (loaded from file repo) |
| Strategy profile hash | Matches artifact (`B2667CFA`) | Matches artifact |
| Basket version | Matches candidate binding | Bound at registration; incremented across re-seeds |
| Candidate id | `recovery-candidate:sprint7d-demo-btc-001:step:1:q:0` | Matched |
| Candidate status | `SELECTED` → `SUBMITTED` | `SELECTED` → **`REJECTED`** after failed submit |
| Quote freshness | Fresh at revalidation | Passed revalidation |
| Execution zone / step DUE | Still `DUE` at submit | Passed revalidation (after in-memory signal align workaround) |
| Projected risk result | Allowed | Allowed (`0.1911 / 120.5315`) |
| Pending execution status | `QUEUED` + prepared envelope in registry **and** store | Registry entry likely present in primary session; **not rehydrated** on second EA attach |
| Authorization status | Valid one-shot token | Token issued; consumption ambiguous on `reason=NONE` path |
| Trigger status | One-shot consumed only after broker attempt | Consumed on failed submit path (`m_triggerRegistry.Consume` in `DemoManualSubmissionService` L222) |
| OrderSendAsync | Exactly one broker call | **Not invoked** (no position/order/deal) |

---

## 4. Code changes during current debugging session

### Tracked modifications (`git diff`)

| File | Summary |
|------|---------|
| `mt5/Experts/BasketRecovery/BasketRecoveryEA.mq5` | Recovery submit on `OnInit`, broker snapshot prints, auto-shutdown timer |
| `mt5/Include/.../DemoExecutionAuthorizationConfig.mqh` | Recovery session limits |
| `mt5/Include/.../ExecutionAuthorizationRegistry.mqh` | Recovery submission counter |
| `mt5/Include/.../ApplicationContext.mqh` | Manual recovery route wiring |
| `mt5/Include/.../ApplicationKernel.mqh` | Kernel hooks for recovery services |
| `mt5/Include/.../EvaluateBasketStrategyUseCase.mqh` | Recovery candidate planner integration |
| `mt5/Include/.../BasketAggregate.mqh` | `SetSignalDetailsForManualRecoveryRevalidation` |
| `mt5/Include/.../EventType.mqh` | Recovery domain event types |
| `mt5/Include/.../Mt5ConfigurationLoader.mqh` | Recovery EA inputs |
| `mt5/Include/.../Mt5MarketDataProvider.mqh` | `ResolveTickValue()` fallback when `SYMBOL_TRADE_TICK_VALUE==0` |
| `mt5/Include/.../TickQuoteReader.mqh` | Same tick-value fallback |
| `mt5/Include/.../BasketSerializer.mqh` | Persist signal range fields |
| `mt5/Include/.../BasketSerializerReader.mqh` | Read signal range fields |
| `mt5/Include/.../Bootstrapper.mqh` | Manual recovery candidate service graph |

### Untracked Sprint 7D additions (same session)

| File | Summary |
|------|---------|
| `ManualRecoveryCandidate*.mqh` (registry, registration, submission, validation, tracker, events) | Sprint 7D domain + application layer |
| `RecoveryCandidateSubmissionValidator.mqh` | Submit-time revalidation |
| `RecoveryCandidateExecutionRequestFactory.mqh` + value objects/enums | Sealed recovery requests |
| `Seed/Register/Issue/Collect/PrepareSprint7d*.mq5` | Validation harness scripts |
| `TestManualRecoveryCandidateValidation.mq5` | Unit compile test |
| `scripts/run-sprint7d-ea-chart-validation.ps1` | Orchestrator (+ duplicate-trigger phase) |
| `docs/architecture/56-manual-demo-recovery-candidate-validation.md` | Sprint 7D spec / partial results |

---

## 5. Change classification

| Change | Classification |
|--------|----------------|
| Tick value fallback (`Mt5MarketDataProvider`, `TickQuoteReader`) | **Required production fix** (Vantage BTCUSD reports tick value 0) |
| Signal range persistence (`BasketSerializer` / reader) | **Required production fix** |
| Sprint 7D manual recovery route (untracked services + wiring) | **Required production feature** (incomplete validation) |
| `AlignBasketSignalForRecoveryRevalidation` + `SetSignalDetailsForManualRecoveryRevalidation` | **Temporary workaround** — mutates in-memory basket signal without version bump to pass DUE revalidation |
| Register script equity wait loop, 100-pip signal margin, raw `decisions` pass-through | **Test harness only** |
| Seed script wide signal range tuning | **Test harness only** |
| EA `OnInit` one-shot submit + auto-shutdown timer | **Test harness only** |
| Orchestrator duplicate-trigger phase | **Test harness only** |
| Trigger not consumed on revalidation failure (`ManualRecoveryCandidateSubmissionService`) | **Uncertain** — may weaken one-shot semantics vs doc 56; intended to allow retry after validation fail |
| `RecoveryCandidateSubmissionValidator` pipSize fix | **Required production fix** (risk math correctness) |
| Opaque `reason=NONE` on submit-use-case failure | **Bug / diagnostic gap** — should propagate `CPreparedSubmissionResult` message |

---

## 6. Smallest next fix (do not implement yet)

**Fix A (blocking):** In `CExecutionSubmissionPreparer::Prepare`, when returning a **cached reusable envelope** from `IPendingExecutionStore` (L171–180), **re-upsert a QUEUED `CPendingExecutionEntry` into `CPendingExecutionRegistry`** (reload from store or rebuild from envelope) before `CDemoManualSubmissionService::TrySubmit` runs. Mirror Sprint 6G seed behavior where registry and store stay aligned.

**Fix B (diagnostic, same PR):** In `CDemoManualSubmissionService::TrySubmit`, when `submitResult.IsSuccess()==false`, return `Rejected(...)` or populate `Detail()` from `submitResult.FailureMessage()` so the next run identifies whether failure is `Prepared envelope not found`, `Entry must be QUEUED`, gateway misconfiguration, etc.

**Fix C (after A+B verified):** Revert or replace `AlignBasketSignalForRecoveryRevalidation` — replace with persisted signal ranges that remain DUE through register→EA latency without in-memory mutation.

**Verification:** One primary chart run only; confirm `ordersend_async` log and `positions=1` before any negative tests.

---

## 7. Production safety weakening assessment

| Safety rule | Weakened? | Notes |
|-------------|-----------|-------|
| CRC validation | **No** | No changes observed |
| Profile hash validation | **No** | Still enforced at revalidation |
| Max-risk gate | **No** | Still enforced; tick fallback enables calculation only |
| Candidate expiry | **No** | Negative test passed at 21:16:39 |
| Authorization binding | **No** | Token binding fingerprint unchanged |
| One-shot trigger behavior | **Possibly** | Trigger consumed on failed submit (`DemoManualSubmissionService` L222); revalidation-failure path no longer consumes trigger — verify against doc 56 |
| Demo-only safety gate | **Concern** | In-memory signal align bypasses persisted basket/version semantics for replan DUE check — **workaround, not production-safe** |
| Automatic recovery execution | **No** | Remains disabled |

---

## 8. Earlier blockers (resolved in session, may recur)

| Symptom | Phase | Resolution applied |
|---------|-------|-------------------|
| `RISK_DATA_UNSAFE` / `quote_tick_value=0` | Risk gate at registration | Tick value fallback |
| `max_risk=0` at script start | Risk gate at registration | Account equity wait in register script |
| `Recovery step is no longer DUE` | Revalidation at submit | Signal tuning + in-memory align workaround |

---

## 9. References

- Sprint 7D spec: [56-manual-demo-recovery-candidate-validation.md](./56-manual-demo-recovery-candidate-validation.md)
- Working Sprint 6G reference (OrderSendAsync PASS): [52-sprint-6g-real-demo-ordersendasync-validation.md](./52-sprint-6g-real-demo-ordersendasync-validation.md)
- Experts journal: `...\Terminal\81A933A9AFC5DE3C23B15CAB19C63850\MQL5\Logs\20260628.log`
