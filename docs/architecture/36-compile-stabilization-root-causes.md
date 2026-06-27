# Compile Stabilization — Root Cause Inventory

Sprint gate: `BasketRecoveryEA.mq5` and all `Test*.mq5` compile with **0 errors**.

Build path: repo `mt5/` → `scripts/sync-to-mt5.ps1` → terminal `MQL5/` → `scripts/compile-all.ps1`.

---

## Summary

| Category | Primary codes | Structural / Local | Resolution pattern |
|----------|---------------|--------------------|--------------------|
| Private/default/copy ctor restrictions | 214, 199 | Structural | Public copy ctor for immutable VOs; public default ctor only where `ArrayResize`/containers require it |
| Passing temporaries to reference parameters | 200, 293 | Local | Introduce named locals; use `const T &` for object params |
| Invalid return-by-value / reference returns | 229 | Structural | Return pointers from fixtures; no `T&` from methods |
| Template / result object copying | 373, 358 | Structural | `TryGetValue(out)`; `EmptyOk` + transfer adopt; dedicated pointer result types |
| Pointer ownership in `CResult<T*>` | 358, 202, 373 | Structural | Replace with `CDomainEventResult`; never `CResult<U*>` |
| Array/reference signature incompatibility | 246 | Local | Non-const broker API wrappers; correct MQL5 struct types |
| Include / missing type | 149, 154 | Local | Explicit `#include` (e.g. `Result.mqh` in `JsonReader.mqh`) |
| `friend` unsupported in templates | 149, 154 | Structural | Public package fields / transfer helpers instead |
| Enum / API mismatch | 256, 197 | Local | Use platform constants (`TRADE_RETCODE_LIMIT_ORDERS`) |
| Const correctness | 279, 202 | Local | `const` writer params; `const` helper methods |

---

## Error patterns (detail)

### 214 — private copy/default constructor

**Root cause:** MQL5 requires accessible copy constructors when objects are stored in arrays, returned by value, or assigned through templates such as `CResult<T>`.

**Safe remediation:** Immutable VOs get explicit public copy ctor. Aggregates/DTOs with owned pointers do not — use transfer adopt pattern.

**Structural**

---

### 200 / 293 — temporary or by-value object where reference required

**Example locations:** `CommandProcessor.mqh`, `RestCommandSource.mqh`, `TestStrategyCommandWiring.mq5`

**Safe remediation:** Named locals for strings; `const CUtcTime &` for value-object parameters.

**Local**

---

### 229 — reference cannot be used (return type)

**Example locations:** `AggregateTestFixture.mqh`, `Mt5TradeExecutor.mqh`

**Safe remediation:** Return pointers via `GetPointer()` or stored handler pointers.

**Structural**

---

### 373 / 358 — `CResult<T>` copy / const pointer assignment

**Root cause:** `CResult<CDomainEvent*>` breaks on `Ok(const T &value)`. Template partial specialization is unstable in MQL5.

**Safe remediation:** `CDomainEventResult` for pointer ownership; `BreResultOkAdopting()` for heavy DTOs.

**Structural**

---

### 246 — parameter conversion not allowed

**Example:** `OrderCheck` must use `MqlTradeCheckResult`, not `MqlTradeResult`.

**Local**

---

### 149 / 154 — cascade from missing include or `friend`

**Example:** `JsonReader.mqh` missing `Result.mqh`; `friend` in `Result.mqh` caused 144 errors.

**Local / structural**

---

### 256 — undeclared identifier

**Examples:** Missing `BasketAggregate` helpers; `TRADE_RETCODE_TRADE_TOO_MANY_ORDERS`; `ICommand::SetIdempotencyKey`.

**Local**

---

### 279 / 202 — const correctness

**Example:** `CommandSerializer` const path vs non-const writer reference.

**Safe remediation:** `const CJsonWriter &` in strategy helpers; `SerializeCommandFields` marked `const`.

**Local**

---

## Before / after (final gate)

| Target | Before sprint | After |
|--------|---------------|-------|
| BasketRecoveryEA.mq5 | 144+ / ~33 best | **0** |
| All Test*.mq5 | 6–101 each | **0** |
