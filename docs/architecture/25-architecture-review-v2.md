# 25. Mimari İnceleme v2 — Kalan Zayıflıklar ve İyileştirmeler

> **Revizyon:** Architecture review phase tamamlandı. v1 → v2 iyileştirmeleri uygulandı. Bu belge kalan riskleri ve önerilen iyileştirmeleri listeler.

## 25.1 v1 → v2 Uygulanan İyileştirmeler (Özet)

| # | İyileştirme | Durum |
|---|-------------|-------|
| 1 | Command Queue modeli (polling → command-centric) | ✅ doc 18 |
| 2 | Event Bus (modüller arası domain events) | ✅ doc 19 |
| 3 | Explicit Transition Rules | ✅ doc 20 |
| 4 | Trade Executor (tek broker API noktası) | ✅ doc 21 |
| 5 | Position Snapshot (Risk Engine broker scan yok) | ✅ doc 22 |
| 6 | Configuration Profiles | ✅ doc 23 |
| 7 | Backtesting Adapter (first-class) | ✅ doc 24 |

---

## 25.2 Kalan Zayıflık #1: At-Least-Once Semantics

**Problem:** Command queue + trade request queue restart sonrası duplicate execution riski.

**Etki:** Duplicate recovery pozisyonu, double partial close.

**Öneri:**
- IdempotencyKey zorunlu (uygulandı)
- Trade request FILLED check before re-execute
- Snapshot version monotonic — stale transaction reject
- **IdempotencyStore** append-only: `processed_keys.jsonl` — handler başında check

**Öncelik:** P0 — Sprint 4-5

---

## 25.3 Kalan Zayıflık #2: Event Handler Ordering

**Problem:** Sync event bus'ta handler sırası kritik. Yanlış sıra → race (ör. persistence before state transition).

**Etki:** Restart'ta inconsistent state.

**Öneri:**
- Handler **priority** sistemi (doc 19'da tanımlandı)
- Documented global order:
  1. TransitionEngine (state first)
  2. Snapshot-derived handlers
  3. PersistenceHandler
  4. AuditSyncHandler
  5. MetricsHandler
- Startup'ta priority conflict validation

**Öncelik:** P0 — Sprint 3

---

## 25.4 Kalan Zayıflık #3: Command vs Event Loop Reentrancy

**Problem:** Event handler command enqueue eder → command processor event publish eder → nested dispatch.

**Etki:** Stack overflow (MQL5), inconsistent intermediate state.

**Öneri:**
- **Two-phase processing loop:**
  ```
  Phase 1: Process all pending commands (no event dispatch mid-command)
  Phase 2: Drain event queue (handlers may enqueue commands for NEXT cycle)
  ```
- `ProcessingContext.inCommandPhase` flag — event handler command enqueue OK, immediate process NO

**Öncelik:** P0 — Sprint 3

---

## 25.5 Kalan Zayıflık #4: Floating Profit Staleness

**Problem:** Snapshot floating profit tick cache'den güncellenir; debounce ile risk eval gecikebilir.

**Etki:** TP1 trigger gecikmesi, recovery step miss.

**Öneri:**
- Price threshold crossings **debounce dışı** — anında eval
- Risk eval debounced; TP/recovery threshold **immediate**
- Ayrı `PriceThresholdMonitor` (immediate) vs `RiskDebouncedEvaluator` (100ms)

**Öncelik:** P1 — Sprint 8-9

---

## 25.6 Kalan Zayıflık #5: Multi-Basket Account Risk

**Problem:** Her basket bağımsız profile kullanır; account-level aggregate risk yok.

**Etki:** 5 basket × 1.2% max = 6% total exposure.

**Öneri:**
- `AccountRiskAggregator` read model — tüm snapshot'ları toplar
- `AccountRiskCapBreached` event → block new CreateBasketCommand
- Profile: `account_risk_cap_pct` (doc 23'te nullable — implement et)
- Recovery gate: account headroom check

**Öncelik:** P1 — Sprint 10

---

## 25.7 Kalan Zayıflık #6: Python Command Pre-Mapping

**Problem:** MT5'te Signal→Command mapper duplicate logic riski (Python + MT5).

**Etki:** Parser değişikliğinde iki yerde güncelleme.

**Öneri:**
- Python API `/commands/pending` endpoint — command DTO doğrudan döner
- MT5 mapper yalnızca validation + enqueue
- Shared JSON schema: `schemas/command.schema.json` in repo

**Öncelik:** P1 — Sprint 16 (Python)

---

## 25.8 Kalan Zayıflık #7: SL Sync Partial Failure (Break-Even)

**Problem:** BE activation 5 pozisyondan 3'ün SL'ini sync eder, 2 fail.

**Etki:** Unprotected exposure.

**Öneri:**
- `require_all_sl_synced_before_transition: true` (profile default)
- TransitionEngine guard: all SL synced
- Failed sync → `BreakEvenSyncPending` mode flag → retry timer
- **Do NOT** transition to BREAK_EVEN until 100% synced (or operator override command)

**Öncelik:** P0 — Sprint 12

---

## 25.9 Kalan Zayıflık #8: Dead Letter Queue Operator Workflow

**Problem:** Failed commands dead letter'a gider ama operatör müdahale workflow'u tanımsız.

**Etki:** Sessiz basket stuck.

**Öneri:**
- `RequeueCommand` operatör command'ı
- `AbandonBasketCommand` operatör command'ı
- Dead letter alert: CRITICAL log + optional webhook
- Dashboard: dead letter count metric

**Öncelik:** P1 — Sprint 15

---

## 25.10 Kalan Zayıflık #9: MQL5 OOP / Test Infrastructure

**Problem:** MQL5 unit test framework zayıf; 15k LOC test coverage riski.

**Etki:** Regression bugs.

**Öneri:**
- Domain katmanını mümkün olduğunca pure function
- `#ifdef UNIT_TEST` ile test harness
- Critical path: TransitionRule table tests, RiskCalculator tests, Idempotency tests
- Long-term: domain logic Python port for CI (same spec, cross-validation) — optional

**Öncelik:** P1 — ongoing

---

## 25.11 Kalan Zayıflık #10: WebRequest Blocking

**Problem:** REST ingestion timer'da blocking WebRequest — command processing durur.

**Etki:** TP trigger gecikmesi during API call.

**Öneri:**
- REST fetch **ayrı timer** (3s) vs command/trade processing timer (100ms)
- Fetch sadece enqueue; process ayrı loop
- Circuit breaker open → skip fetch, continue processing
- Future: non-blocking request queue (MQL5 limitation — accept or move ingestion to external proxy)

**Öncelik:** P1 — Sprint 5

---

## 25.12 Kalan Zayıflık #11: Schema Migration on Restart

**Problem:** Profile/basket/command JSON schema_version upgrade mid-deployment.

**Etki:** EA restart after upgrade → parse fail → ERROR.

**Öneri:**
- `MigrationRunner` on OnInit — migrate all persisted files
- Backward compatible reads (missing fields → defaults)
- Migration unit tests per version bump
- Deployment runbook: stop EA → migrate files → deploy → start

**Öncelik:** P1 — Sprint 14

---

## 25.13 Kalan Zayıflık #12: Time Synchronization

**Problem:** Python `received_at`, MT5 `TimeCurrent()`, broker server time — üç farklı clock.

**Etki:** Command ordering, timeout guards yanlış.

**Öneri:**
- `IClock` port everywhere (uygulandı)
- REST API timestamps UTC zorunlu
- Command ordering by `sequence_number` (server-assigned), not client timestamp
- Python: monotonic `sequence_number` per account

**Öncelik:** P1 — Sprint 16

---

## 25.14 Önerilen Yeni Bileşenler (v2.1 Backlog)

| Bileşen | Açıklama | Öncelik |
|---------|----------|---------|
| `IdempotencyStore` | Processed key dedup | P0 |
| `TwoPhaseProcessingLoop` | Command/event reentrancy fix | P0 |
| `PriceThresholdMonitor` | Immediate TP/recovery crossing | P1 |
| `AccountRiskAggregator` | Cross-basket risk cap | P1 |
| `DeadLetterOperatorCommands` | Requeue/Abandon | P1 |
| `MigrationRunner` | Schema upgrade on init | P1 |
| `HealthCheckPublisher` | EA heartbeat to API | P2 |
| `CommandSchemaValidator` | Shared JSON schema validation | P1 |

---

## 25.15 Production Readiness Checklist (Pre-Live)

```
□ Transition rule table 100% test coverage
□ Idempotency verified: duplicate command → no duplicate trade
□ Restart test: kill during ACTIVE, RECOVERY, TP1, BE, CLOSING
□ Dead letter workflow documented
□ Profile validation on startup
□ TradeExecutor grep rule in CI
□ Risk Engine snapshot-only verified (no PositionsTotal in domain)
□ Account risk cap configured (if multi-basket)
□ WAIT_DETAILS timeout tested
□ Circuit breaker tested (API down 30 min)
□ Backtest replay matches live on sample period
□ Operator runbook: ERROR state, orphan positions, dead letter
□ Secrets not in profile files or repo
```

---

## 25.16 Mimari Metrik Hedefleri (v2)

| Metrik | v1 Hedef | v2 Hedef |
|--------|----------|----------|
| OnTick latency | < 1ms | < 0.5ms (snapshot read only) |
| Command process cycle | — | < 10ms (ex trade) |
| Broker API call sites | Many | **1 class** |
| Domain → MT5 dependency | Partial | **Zero** |
| Config change deploy | EA recompile | **Profile file edit** |
| Backtest without MT5 | No | **Yes** |

---

## 25.17 Sonuç

v2 mimarisi production için önemli ölçüde daha sağlam:
- **Command Queue** → deterministik, idempotent, auditable iş hattı
- **Event Bus** → loose coupling, testable modüller
- **Transition Rules** → explicit, table-driven, testable state machine
- **Trade Executor** → single broker boundary
- **Position Snapshot** → consistent risk reads, backtest-ready
- **Configuration Profiles** → operasyonel esneklik
- **Backtesting Adapter** → strategy validation before live

Kalan 12 zayıflık dokümante edildi; P0 item'lar Sprint 3-5'te ele alınmalı. Implementation'a geçmeden önce **Transition Rule table** ve **Command schema** finalize edilmeli.
