# Basket Recovery Trading Engine — Mimari Dokümantasyon

> **Durum:** Strategy Domain Refactor (mimari) — implementasyon durduruldu  
> **Hedef:** Generic Basket Trading Engine — configuration-driven strategies  
> **Son güncelleme:** 2026-06-26 (Strategy Refactor Sprint)

## Belge Haritası

### Çekirdek Mimari (v1)

| # | Belge | İçerik |
|---|-------|--------|
| 1 | [01-software-architecture.md](./01-software-architecture.md) | Katmanlar, SOLID, v2 mimari özeti |
| 2 | [02-folder-structure.md](./02-folder-structure.md) | MT5 + Python repo yapısı |
| 3 | [03-class-diagram.md](./03-class-diagram.md) | Sınıf diyagramları (Mermaid) |
| 4 | [04-module-responsibilities.md](./04-module-responsibilities.md) | Modül sorumlulukları |
| 5 | [05-data-flow.md](./05-data-flow.md) | Veri akışı |
| 6 | [06-sequence-diagrams.md](./06-sequence-diagrams.md) | Sequence diyagramları |
| 7 | [07-state-machine.md](./07-state-machine.md) | Durum makinesi (lifecycle + modes) |
| 8 | [08-risk-engine.md](./08-risk-engine.md) | Risk motoru (snapshot-based) |
| 9 | [09-recovery-engine.md](./09-recovery-engine.md) | Recovery motoru |
| 10 | [10-basket-engine.md](./10-basket-engine.md) | Sepet motoru |
| 11 | [11-rest-communication.md](./11-rest-communication.md) | REST → Command ingestion |
| 12 | [12-persistence-strategy.md](./12-persistence-strategy.md) | Kalıcılık |
| 13 | [13-restart-recovery.md](./13-restart-recovery.md) | MT5 restart sonrası kurtarma |
| 14 | [14-error-handling.md](./14-error-handling.md) | Hata yönetimi |
| 15 | [15-logging-strategy.md](./15-logging-strategy.md) | Loglama |
| 16 | [16-future-extensions.md](./16-future-extensions.md) | Gelecek genişleme noktaları |
| 17 | [17-implementation-roadmap.md](./17-implementation-roadmap.md) | Sprint planı (v2) |

### v2 Production Patterns (Yeni)

| # | Belge | İçerik |
|---|-------|--------|
| 18 | [18-command-queue.md](./18-command-queue.md) | Command Queue modeli, idempotency |
| 19 | [19-event-bus.md](./19-event-bus.md) | Domain Event Bus |
| 20 | [20-transition-rules.md](./20-transition-rules.md) | Explicit transition rule table |
| 21 | [21-trade-executor.md](./21-trade-executor.md) | Tek broker API noktası |
| 22 | [22-position-snapshot.md](./22-position-snapshot.md) | In-memory position snapshot |
| 23 | [23-configuration-profiles.md](./23-configuration-profiles.md) | Profile-based configuration |
| 24 | [24-backtesting-adapter.md](./24-backtesting-adapter.md) | Backtest execution environment |
| 25 | [25-architecture-review-v2.md](./25-architecture-review-v2.md) | Kalan zayıflıklar + checklist |
| 26 | [26-sprint-0.1-audit-fixes.md](./26-sprint-0.1-audit-fixes.md) | Sprint 0.1 audit düzeltmeleri + bağımlılık grafiği |
| 27 | [27-sprint-1-kernel-foundation.md](./27-sprint-1-kernel-foundation.md) | Sprint 1 application kernel + test planı |
| 28 | [28-sprint-2-basket-aggregate.md](./28-sprint-2-basket-aggregate.md) | Sprint 2 basket aggregate + domain handlers |
| 29 | [29-sprint-3-persistence.md](./29-sprint-3-persistence.md) | Sprint 3 file-backed persistence |
| 30 | [30-sprint-4-rest-ingestion.md](./30-sprint-4-rest-ingestion.md) | Sprint 4 REST command ingestion |
| 31 | [31-sprint-5-trade-execution.md](./31-sprint-5-trade-execution.md) | Sprint 5 trade execution (paused) |

### Strategy Refactor (Mandatory — Before Engine Implementation)

| # | Belge | İçerik |
|---|-------|--------|
| 32 | [32-strategy-domain-refactor.md](./32-strategy-domain-refactor.md) | **Strategy Engine, Plans, JSON schema, migration** |
| 33 | [33-sprint-r1-strategy-domain-foundation.md](./33-sprint-r1-strategy-domain-foundation.md) | Sprint R-1 Strategy Domain implementation |
| 34 | [34-sprint-r2-strategy-engine.md](./34-sprint-r2-strategy-engine.md) | Sprint R-2 Strategy Engine pure evaluator |

## Sistem Özeti (v2)

```
Telegram → Python Parser → PostgreSQL → REST → Command Queue → Handlers
                                                      ↓
                                               Event Bus → Subscribers
                                                      ↓
                                          Trade Request Queue → Trade Executor → Broker
                                                      ↓
                                            Position Snapshot Store → Risk Engine
```

## v2 Mimari Pillars

1. **Command Queue** — Her sinyal/operasyon idempotent command; polling yalnızca transport
2. **Event Bus** — Modüller arası doğrudan çağrı yok; domain events
3. **Transition Rules** — Deklaratif state geçiş tablosu (current + event → next + rejected)
4. **Trade Executor** — OrderSend/Modify/Close yalnızca bu sınıfta
5. **Position Snapshot** — Risk Engine broker taramaz; snapshot okur
6. **Strategy Profile (v2)** — ExecutionZone, RecoveryPlan, ProfitDistribution, BreakEven, Risk — tek immutable profil ([doc 32](./32-strategy-domain-refactor.md))
7. **Backtesting Adapter** — IExecutionEnvironment ile live/backtest aynı logic

> **⚠️ Implementasyon durduruldu:** Trade Executor wiring, Risk/Recovery/TP engine — Strategy Refactor (R-1..R-3) tamamlanana kadar devam etmez.

## Kritik Mimari Uyarılar

1. **Sinyal eşleştirme:** Python `correlation_key` + `sequence` zorunlu
2. **RECOVERY / TARGET_RISK:** Lifecycle state değil, orthogonal mode flags
3. **SL öncesi risk:** WAIT_DETAILS timeout + lot tavanı zorunlu
4. **Two-phase loop:** Command process ve event dispatch aynı stack'te iç içe olmamalı (doc 25)
5. **Production gate:** doc 25 checklist tamamlanmadan live'a geçilmemeli
