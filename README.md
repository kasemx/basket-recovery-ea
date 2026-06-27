# Basket Recovery Trading Engine

Production-grade MT5 Expert Advisor — Basket Recovery Trading Engine with dynamic risk management.

## Status

**Sprint 0 complete** — project skeleton compiles in MetaEditor (foundation only, no trading logic).

See [mt5/README.md](mt5/README.md) for deployment.

## Documentation

Full architecture: [docs/architecture/README.md](docs/architecture/README.md)

## v2 Architecture Pillars

| Pillar | Document |
|--------|----------|
| Command Queue (idempotent) | [18-command-queue.md](docs/architecture/18-command-queue.md) |
| Event Bus (domain events) | [19-event-bus.md](docs/architecture/19-event-bus.md) |
| Explicit Transition Rules | [20-transition-rules.md](docs/architecture/20-transition-rules.md) |
| Trade Executor (sole broker API) | [21-trade-executor.md](docs/architecture/21-trade-executor.md) |
| Position Snapshot | [22-position-snapshot.md](docs/architecture/22-position-snapshot.md) |
| Configuration Profiles | [23-configuration-profiles.md](docs/architecture/23-configuration-profiles.md) |
| Backtesting Adapter | [24-backtesting-adapter.md](docs/architecture/24-backtesting-adapter.md) |
| Review + weaknesses | [25-architecture-review-v2.md](docs/architecture/25-architecture-review-v2.md) |

## System Flow (v2)

```
Telegram → Python → PostgreSQL → REST → Command Queue
                                            ↓
                                      Event Bus
                                            ↓
                              Trade Request Queue → Trade Executor
                                            ↓
                                   Position Snapshot → Risk Engine
```

## Next Step

Pre-implementation gate (doc 17 § 17.8) → **Sprint 0**
