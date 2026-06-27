# MQL5 Object Copy and Ownership Policy

Compile-safe ownership rules for BasketRecovery EA.

---

## 1. Immutable value objects

- May provide explicit **public copy constructor** when used in arrays or `CResult<T>`.
- May provide **public default constructor** only when `ArrayResize`/containers require it.
- Must not own raw heap pointers or expose mutable shared state.

---

## 2. Aggregates / services / queues

- Must not become freely copyable when owning pointer graphs.
- Use transfer (`TransferCommandsTo`, `TransferEventsTo`) or explicit documented `Clone()`.

---

## 3. `CResult<T>`

**Value types:** `Ok(const T &value)`, `TryGetValue(T &outValue)`, `Fail`, `EmptyOk`.

**Heavy DTOs:** `BreResultOkAdopting()` / `BreResultTryAdoptValue()` in `ResultValueTransfer.mqh`.

**Pointer ownership:** Use `CDomainEventResult` — **never** `CResult<T*>`.

| Field | Rule |
|-------|------|
| Owner | Use case allocates `new CDomainEvent()` |
| Transfer | `Ok(event)` stores pointer once |
| Deletion | Consumer deletes after `TryGetEvent` |
| Copy | Shallow pointer copy — treat as non-copyable in practice |

---

## 4. Reference parameters

Never pass temporaries to reference parameters. Use named `string` locals and `const T &` for class parameters.

---

## 5. Return types

Do not return `T&` from methods. Return pointers (`GetPointer(m_member)`).

---

## 6. MQL5 prohibitions

| Feature | Status |
|---------|--------|
| `friend` in templates | Unsupported |
| `CResult<U*>` specialization | Unstable — use concrete types |
| `T& ValueRef()` in templates | Error 229 |
| `ValueOr()` on pointer results | Removed |

---

## 7. Regression coverage

`TestCompileStabilization.mq5` validates Result extraction, VO copy, adopt transfer, pointer result, and temp-to-ref patterns. Included in `compile-all.ps1`.
