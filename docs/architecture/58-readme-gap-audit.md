# README Gap Audit — Repository vs Published Documentation

**Date:** 2026-06-28  
**Scope:** Compare current repository capabilities against root `README.md`, `mt5/README.md`, and `docs/architecture/README.md`. **No README edits in this task.**

---

## 1. Root `README.md` gaps

| Gap | Current README says | Repository reality |
|-----|---------------------|-------------------|
| Project status | **"Sprint 0 complete"** — foundation only, no trading logic | Sprints 0–7D implemented: persistence, REST ingestion, strategy engine (R-1/R-2/R-3), trade execution ports, simulated + async submission, live submission safety, demo authorization, OrderSendAsync validation (6G PASS), recovery candidate planner (7C), projected risk (7B), manual recovery candidate route (7D in progress) |
| Next step | Pre-implementation gate → Sprint 0 | Sprint 0–6G largely complete; active work is Sprint 7D validation |
| Demo-only execution warning | **Missing** | Real `OrderSendAsync` demo path exists (`DEMO_MANUAL_SUBMISSION`, authorization tokens, trigger tokens). No warning that execution sends real demo orders. |
| Terminal / account safety | **Missing** | Validation scripts target specific demo terminal hash; live terminal must not be used. Not documented at root. |
| Compile / test instructions | **Missing** | `scripts/compile-all.ps1`, MetaEditor F7, `Scripts/BasketRecovery/Tests/*.mq5`, validation orchestrators (`run-sprint6g-*`, `run-sprint7d-*`) |
| Version tags / milestones | **Missing** | Tags referenced in architecture docs: e.g. `v0.6.5-live-submission-safety-and-demo-authorization`, `v0.7.2-recovery-candidate-planner` |
| Architecture doc index | Lists pillars 18–25 only | Docs now span **01–56+** including execution sprints 35–56 |
| System flow diagram | Telegram → Python → REST → Command Queue | Accurate for target architecture; **does not reflect MT5-only demo execution path** now implemented and validated |

---

## 2. `mt5/README.md` gaps

| Gap | Current README says | Repository reality |
|-----|---------------------|-------------------|
| Sprint coverage | Sprint 0 / 0.1 / 1 / 2 only | Through Sprint 7D EA inputs, execution services, validation scripts |
| Trading / execution | "no trading logic, broker ops" | Trade executor port, simulated gateway, `CMt5AsyncSubmissionGateway`, demo manual submission, recovery manual submission |
| Test count | "6 scripts" in Tests | Many more test and validation scripts (6B, 6G, 7D, etc.) |
| Deployment | Copy to MQL5 folder, compile EA | Also requires `Files/BasketRecovery/` validation artifacts, demo authorization workflow, chart-attached EA with specific inputs |
| Demo-only warning | **Missing** | Same as root — no explicit "demo account only" banner |

---

## 3. `docs/architecture/README.md` gaps

| Gap | Current README says | Repository reality |
|-----|---------------------|-------------------|
| Status banner | **"Implementasyon durduruldu"** (stopped for Strategy Refactor) | Implementation continued through R-1/R-2/R-3, Sprints 5–7D |
| Last update | 2026-06-26 Strategy Refactor Sprint | Execution + recovery sprints through 2026-06-28 |
| Document map ends at | Doc **34** (Sprint R-2) | Docs **35–56** exist (compile stabilization, R-3 wiring, runtime validation, execution contract, dry-run, 6B OrderCheck, async correlation, submission prep, live safety, 6G OrderSendAsync, live basket risk, recovery projected risk, recovery planning, manual recovery validation) |
| Sprint 5 status | "paused" in doc 31 link text | Sprint 5+ execution work substantially advanced (docs 41–52) |
| Missing milestones table | No tag/commit baseline list | Multiple sprint docs reference git tags and validation PASS/FAIL status |
| Safety disclaimers | Production gate checklist (doc 25) | Missing explicit **demo-only OrderSendAsync** disclaimer and **manual recovery one-shot** operator warnings in index |
| Setup instructions | None in architecture README | Validation requires: demo terminal, symbol positions cleared, orchestrator scripts, EA input bundle — documented only inside individual sprint docs (46, 52, 56) |

---

## 4. Outdated architecture statements

1. **"Trade Executor wiring … Strategy Refactor tamamlanana kadar devam etmez"** (`docs/architecture/README.md` L80) — obsolete; trade execution and async demo submission are implemented and partially validated.
2. **"Sprint 0 complete / no trading logic"** (root README) — contradicts execution kernel, gateways, and demo submission services in `mt5/Include/BasketRecovery/Application/Execution/`.
3. **"no broker ops"** (`mt5/README.md`) — contradicts Sprint 6G PASS evidence (real demo `OrderSendAsync`).
4. **System flow implies REST/Telegram as prerequisite for execution** — demo validation path operates MT5-local without REST for 6G/7D.

---

## 5. Missing safety disclaimers (all README surfaces)

- Demo account / demo server **required** for any `InpEnableLiveDemoExecution=true` run.
- Live terminal hash must **not** be used for validation orchestrators.
- Manual demo submission consumes authorization + trigger tokens; can open real demo positions.
- Automatic recovery execution is **disabled**; manual recovery route is operator-triggered only.
- One recovery submission per session cap (`MaxRecoverySubmissionsPerSession`).
- `InpMaxManualDemoOpenVolume` hard cap still applies.

---

## 6. Missing setup / operator instructions

| Topic | Where documented today | Missing from README |
|-------|------------------------|---------------------|
| `scripts/compile-all.ps1` | Sprint docs, CI implied | Root + mt5 README |
| Copy/sync MT5 tree | `mt5/README.md` (minimal) | Validation sync from repo to terminal data folder |
| Demo terminal data folder hash | Sprint 52, 56 only | Root quick-start |
| EA input bundle for 6G/7D | Docs 52, 56 | README operator checklist |
| Validation orchestrators | `scripts/run-sprint*.ps1` | Root "how to validate" section |
| Artifact paths (`Files/BasketRecovery/validation/`) | Sprint scripts | README |
| Chart attach + Algo Trading enable | Sprint 46/52 | README |

---

## 7. Missing test / compile instructions

- No mention of `compile-all.ps1` gate (required before chart validation).
- No index of `Scripts/BasketRecovery/Tests/Test*.mq5` vs `Validation/*` scripts.
- No guidance on `git diff --check` / whitespace gate referenced in sprint validation docs.
- No note that validation scripts use `FILE_COMMON` paths under terminal `MQL5/Files/`.

---

## 8. Obsolete roadmap items

| Item in doc 17 / README | Status |
|-------------------------|--------|
| "Next: Sprint 0" | Done — multiple sprints later |
| Strategy Refactor blocks all engine work | R-1/R-2/R-3 done; engine wiring ongoing |
| Sprint 5 trade execution "paused" | Superseded by docs 43–52 |
| REST → Command Queue as next integration step | Partially done (Sprint 4); not blocking demo execution validation |
| Pre-implementation gate (doc 17 § 17.8) as current gate | Should point to production checklist (doc 25) + demo validation gates |

---

## 9. Recommended README update scope (future task, not done here)

1. Replace Sprint 0 status with current milestone (7D blocked / 6G passed).
2. Add **demo-only execution warning** prominently at root and `mt5/README.md`.
3. Extend `docs/architecture/README.md` index through doc **58** and remove "implementasyon durduruldu" banner.
4. Add compile + validation quick-start (`compile-all.ps1`, orchestrator names).
5. Add tag/changelog table linking validation PASS/FAIL docs.
6. Clarify automatic recovery disabled vs manual recovery demo route.

---

## 10. Files audited

- `/README.md`
- `/mt5/README.md`
- `/docs/architecture/README.md`
- `/docs/architecture/17-implementation-roadmap.md` (roadmap drift reference)
- `/docs/architecture/52-sprint-6g-real-demo-ordersendasync-validation.md` (latest PASS baseline)
- `/docs/architecture/56-manual-demo-recovery-candidate-validation.md` (current BLOCKED sprint)
