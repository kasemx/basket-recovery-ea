# MT5 Deployment

Copy the contents of this directory into your MetaTrader 5 data folder:

```
<MQL5>/
├── Experts/BasketRecovery/BasketRecoveryEA.mq5
├── Include/BasketRecovery/...
└── Files/BasketRecovery/...
```

Compile `BasketRecoveryEA.mq5` in MetaEditor (F7).

## Sprint 0 / 0.1 / 1 / 2

- Foundation EA compiles; bootstrap validates full transition rule table (24 rules)
- Application kernel: TransitionEngine, CommandProcessor, dispatchers, idempotency store
- Basket aggregate: sole mutator for basket state; production command/event handlers
- In-memory `IBasketRepository`; no trading logic, broker ops, or REST
- Run tests from `Scripts/BasketRecovery/Tests/` in MetaEditor (6 scripts)
