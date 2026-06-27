# Sprint 6B — MT5 Request Translation and OrderCheck Dry-Run

**Baseline:** `ce3ef6b` / `v0.6.0-execution-contract`

**This sprint still has no broker submission.** No `OrderSend`, `OrderSendAsync`, `CTrade`, `PositionClose`, or `PositionModify`. The only MT5 trade API used in the active executor path is `OrderCheck`, and only inside `CMt5TradeExecutor` when mode is `MT5_DRY_RUN` and the dry-run gate is open.

## Translation flow

```text
CTradeExecutionRequest (sealed)
        │
        ▼
CMt5RequestValidationPolicy
  ├─ basket lifecycle / version / profile hash
  ├─ symbol selected + session open
  ├─ quote freshness + spread guard (MarketSafetyConfig)
  ├─ account trade permission
  ├─ volume / stops / freeze (open intents)
  └─ ticket ownership in basket snapshot (close/modify/reduce)
        │
        ▼
CMt5TradeRequestTranslator → CMt5RequestTranslationResult (MqlTradeRequest + summary)
        │
        ▼
IMt5OrderCheckGateway.Check(request)   ← CMt5OrderCheckGateway (production) / CMockMt5OrderCheckGateway (tests)
        │
        ▼
CMt5TradeCheckResultMapper → CTradeExecutionResult / receipt (isDryRun=true on dry-run path)
        │
        ▼
Journal + CExecutionDomainEvent (manual test route only in EA runtime today)
```

## Intent → MqlTradeRequest mapping

| Intent | MT5 action | Required fields | Notes |
|--------|------------|-----------------|-------|
| `OPEN_POSITION` | `TRADE_ACTION_DEAL` | direction, volume, symbol | price = ask (buy) / bid (sell) unless explicit requested price |
| `CLOSE_POSITION` | `TRADE_ACTION_DEAL` | ticket, symbol | opposite side, volume = snapshot volume |
| `REDUCE_POSITION` | `TRADE_ACTION_DEAL` | ticket, volume, symbol | partial close semantics |
| `MODIFY_STOP_LOSS` | `TRADE_ACTION_SLTP` | ticket, SL | preserves existing TP from snapshot |
| `MODIFY_TAKE_PROFIT` | `TRADE_ACTION_SLTP` | ticket, TP | preserves existing SL from snapshot |
| `CANCEL_PENDING_REQUEST` | `TRADE_ACTION_REMOVE` | order ticket, symbol | pending order cancel only |
| unsupported / ambiguous | — | — | deterministic `REJECTED` (`unsupported_intent` or validation reason); never guesses broker fields |

## Runtime modes (`CMt5TradeExecutor`)

| Mode | Default | OrderCheck | OrderSend | Notes |
|------|---------|------------|-----------|-------|
| `DISABLED` | **yes** | no | no | deterministic `execution_disabled` rejection |
| `MT5_DRY_RUN` | no | yes (when gate open) | no | sole active broker-validation path |
| `SIMULATED` | no | no | no | delegates to in-executor `CSimulatedTradeExecutor`; test-only unless wired later |

`IsActive()` is true only for `MT5_DRY_RUN`.

## OrderCheck result mapping

| Outcome | Execution status | isDryRun | Stored diagnostics |
|---------|------------------|----------|--------------------|
| local validation fail (pre-check) | `REJECTED` | true | message, no retcode |
| `OrderCheck` success + done/placed retcodes | `ACCEPTED` | true | retcode, summary, checked price/volume/SL/TP, timestamp |
| broker validation retcodes (invalid volume/stops/price/fill/reject) | `REJECTED` | true | retcode + comment |
| timeout retcode | `TIMED_OUT` | true | retcode |
| connection/market closed/off retcodes | `FAILED` | true | retcode |
| ambiguous retcode | `UNKNOWN` | true | retcode + comment |

No broker tickets are created and basket positions are not mutated on the dry-run path.

## Dry-run safety gates

1. **Default runtime:** `InpExecutionMode = DISABLED` (0).
2. **Manual EA route only** (OnTimer, not OnTick / not OnTradeTransaction / not REST):
   - requires `InpExecutionMode = MT5_DRY_RUN` (1)
   - requires `InpEnableExecutionDryRun = true`
   - optional one-shot trigger: `InpManualExecutionDryRunTriggerToken` + `InpManualExecutionDryRunBasketId`
3. **Composition guard:** `CExecutionRuntimeCompositionGuard::AllowsMt5ExecutorInTimerOrFastPathPipeline() == false`
4. **Diagnostics:** `InpEnableExecutionDiagnostics` (default false), bounded per session, never logs secrets/API keys.
5. **Forbidden in this sprint:** `OrderSend`, `OrderSendAsync`, `CTrade`, live position mutation, automatic strategy execution.

## Required conditions before OrderSendAsync can be introduced

- Separate sprint with explicit safety review and feature flag
- Dedicated submission gateway seam (distinct from `IMt5OrderCheckGateway`)
- Idempotent submit + reconciliation for unknown results
- Live execution preconditions (`CExecutionSafetyPreconditions`) activated deliberately
- Runtime mode `LIVE` (not implemented in 6B) with independent kill switch
- End-to-end tests using broker sandbox, not production composition root
- OnTick / strategy / REST paths remain blocked until each is individually approved

## Manual demo dry-run checklist

1. Attach EA on chart with symbol matching an **ACTIVE** basket (e.g. `EURUSD`).
2. Set `InpExecutionMode = 1` (`MT5_DRY_RUN`).
3. Set `InpEnableExecutionDryRun = true`.
4. Optionally set `InpEnableExecutionDiagnostics = true` for bounded logs.
5. Set `InpManualExecutionDryRunBasketId` to an active basket id.
6. Set a new `InpManualExecutionDryRunTriggerToken` value (one-shot).
7. Wait for application timer tick; verify log line `Manual dry-run completed` or rejection reason.
8. Confirm **no** live orders appear in Terminal → Trade tab.
9. Reset token or change value for another probe.

## Tests

`TestMt5DryRunExecution.mq5` covers translation, validation guards, disabled mode, dry-run gate, mocked OrderCheck accept/reject, and composition guard. Legacy `OrderSend` remains isolated under `Infrastructure/Execution/Legacy/` for historical tests only.
