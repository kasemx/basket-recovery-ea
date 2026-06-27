# Compile Warning Register

Baseline: `v0.4.1-compile-stable` — zero compile errors across `BasketRecoveryEA.mq5` and all `Test*.mq5`.

Last verified: compile gate via `scripts/compile-all.ps1`.

---

## Resolved in this gate

| Source | Code | Resolution |
|--------|------|------------|
| `JsonWriter.mqh` (CopyFileCommon / temp file copy) | 43 | Fixed: `ulong fileSize`, bounded `(int)` read size, `uint bytesRead` — persistence behavior unchanged; rejects files > 2 GiB explicitly |

---

## Remaining warnings

### W-001 — Market version format

| Field | Value |
|-------|-------|
| **Source file** | `mt5/Experts/BasketRecovery/BasketRecoveryEA.mq5` (line 3) |
| **Warning code** | 68 |
| **Reason** | `#property version "0.0.3"` uses three-part semver; MQL5 Market expects `xxx.yyy` (two-part numeric) |
| **Risk level** | Low — compile-time metadata only; no runtime trading impact |
| **Planned resolution / rationale** | **Accepted** until Market publication sprint. Bump to e.g. `"0.04"` or `"1.00"` when preparing MQL5 Market release |

---

### W-002 — Enum cast in tests (`long` → `int`)

| Field | Value |
|-------|-------|
| **Source files** | `TestBasketAggregate.mq5` (lines 31, 128); `TestBasketRepository.mq5` (line 36); `TestStrategyCommandWiring.mq5` (lines 181, 187, 393, 465); `TestCompileStabilization.mq5` (line 70) |
| **Warning code** | 43 |
| **Reason** | `EqualInt((long)ENUM_VALUE, (long)actual, …)` and similar — MQL5 enums compile as `long`; `CTestAssert::EqualInt` takes `int` parameters |
| **Risk level** | Low — test-only; enum ordinals are small and fit in `int` |
| **Planned resolution / rationale** | **Accepted** for compile-stable baseline. Optional follow-up: add `EqualLong` to `CTestAssert` or cast via local `int` variables with range comments |

---

## Summary counts (final gate)

| Target | Errors | Warnings |
|--------|--------|----------|
| BasketRecoveryEA.mq5 | 0 | 1 |
| TestBasketAggregate.mq5 | 0 | 2 |
| TestBasketRepository.mq5 | 0 | 2 |
| TestCompileStabilization.mq5 | 0 | 1 |
| TestStrategyCommandWiring.mq5 | 0 | 6 |
| All other Test*.mq5 | 0 | 0 |
| **Total unique warning patterns** | — | **2 (W-001, W-002)** |

---

## Related documents

- `36-compile-stabilization-root-causes.md` — error root causes
- `37-mql5-object-copy-ownership-policy.md` — ownership rules
