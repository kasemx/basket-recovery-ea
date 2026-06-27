#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Market/InMemoryMarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Market/MarketContextProviderAdapter.mqh>
#include <BasketRecovery/Application/FastPath/FastEvaluationTriggerPolicy.mqh>
#include <BasketRecovery/Application/FastPath/QuoteSequenceGuard.mqh>
#include <BasketRecovery/Application/FastPath/SymbolBasketIndex.mqh>
#include <BasketRecovery/Application/FastPath/BasketFastStateRegistry.mqh>
#include <BasketRecovery/Application/FastPath/ForceReevaluationFlag.mqh>
#include <BasketRecovery/Application/FastPath/FastCommandStagingBuffer.mqh>
#include <BasketRecovery/Application/Services/TradeTransactionFastPathService.mqh>
#include <BasketRecovery/Application/Services/TimerFallbackEvaluationService.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Shared/DTOs/NormalizedTradeTransaction.mqh>

#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Infrastructure/Commands/InMemoryCommandQueue.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Market/AccountContextSnapshot.mqh>

string JsonWithFixedTpLevel(const double tpPrice)
  {
   return "{"
          "\"schema_version\":2,"
          "\"strategy_id\":\"fast-path-test\","
          "\"metadata\":{\"strategy_name\":\"Fast Path Test\"},"
          "\"execution_zone\":{\"source\":\"SIGNAL_RANGE\",\"expansion_mode\":\"SYMMETRIC\",\"above_entry_pips\":3,\"below_entry_pips\":3,\"expansion_disabled\":false},"
          "\"recovery_plan\":{\"algorithm\":\"CONSTANT\",\"constant_distance_pips\":0.2,\"constant_lot\":0.01,\"max_steps\":50,\"allow_during_profit_taking\":true,\"disable_after_break_even\":true,\"initial_position_count\":3,\"initial_lot_size\":0.01},"
          "\"risk_plan\":{\"target_risk_pct\":1.0,\"max_risk_pct\":1.2,\"risk_reduction_threshold_pct\":0.95,\"risk_reduction_mode\":\"WORST_ENTRY\",\"wait_details_timeout_minutes\":30,\"risk_eval_debounce_ms\":100},"
          "\"profit_distribution_plan\":{\"require_floating_profit_positive\":true,\"default_close_mode\":\"WORST_ENTRY_FIRST\",\"levels\":[{\"level_id\":\"L1\",\"level_index\":1,\"source\":\"SIGNAL_TP\",\"price\":"+DoubleToString(tpPrice,1)+",\"close_percent\":33,\"close_mode\":\"WORST_ENTRY_FIRST\",\"partial_close\":true,\"enabled\":true}]},"
          "\"break_even_plan\":{\"rules\":[{\"rule_id\":\"BE1\",\"enabled\":true,\"priority\":1,\"run_once\":true,\"trigger\":{\"type\":\"REALIZED_PROFIT\",\"realized_profit_usd\":10},\"actions\":[{\"type\":\"MOVE_SL_TO_AVERAGE\",\"buffer_pips\":0.5}]}]},"
          "\"execution_policy\":{\"slippage_points\":10,\"max_trade_retries\":3,\"magic_number_base\":202606000,\"command_batch_size\":10,\"trade_request_batch_size\":5,\"rest_poll_interval_ms\":3000}"
          "}";
  }

CBasketAggregate BuildActiveBasketWithTp(const string basketIdValue,const double tpPrice)
  {
   CUtcTime boundAt(1000);
   string json=JsonWithFixedTpLevel(tpPrice);
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(json,boundAt);
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,json,boundAt);
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                  CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                  CExecutionProfileConfig(),boundAt);
   CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId(basketIdValue),legacy,snapshot,
                                                                      "corr-"+basketIdValue,BRE_DIRECTION_BUY,"XAUUSD",
                                                                      CSignalId("sig-"+basketIdValue),boundAt,
                                                                      CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   return basket;
  }

void TestProfitLevelCrossTriggersEvaluation(void)
  {
   CFastEvaluationTriggerPolicy policy(CFastPathConfig::Create(3,2000,0,100,10000));
   CBasketAggregate basket=BuildActiveBasketWithTp("tp-cross",2360.0);
   CBasketFastState state;
   state.SetLastEvaluatedBid(2350.0);
   state.SetLastEvaluatedAsk(2350.2);
   CTestAssert::True(policy.ShouldEvaluate(basket,state,2361.0,2361.2,0.01,0.01,12345,1000),
                     "Profit level cross must trigger evaluation");
  }

void TestRecoveryThresholdCrossTriggersEvaluation(void)
  {
   CFastEvaluationTriggerPolicy policy(CFastPathConfig::Create(3,1000,0,100,10000));
   CBasketAggregate basket=BuildActiveBasketWithTp("recovery-cross",2360.0);
   CBasketFastState state;
   state.SetLastEvaluatedBid(2350.0);
   state.SetLastEvaluatedAsk(2350.2);
   state.SetLastEvaluatedTickTimeMsc(GetTickCount64()-5000);
   CTestAssert::True(policy.ShouldEvaluate(basket,state,2350.0,2350.2,0.01,0.01,23456,1000),
                     "Max evaluation age must trigger evaluation");
  }

void TestDuplicateQuoteSequenceSkipsEvaluation(void)
  {
   CQuoteSequenceGuard guard;
   CBasketFastState state;
   state.SetLastEvaluatedQuoteSequence(999);
   CFastEvaluationTriggerPolicy policy(CFastPathConfig::Create(3,60000,0,1,10000));
   CBasketAggregate basket=BuildActiveBasketWithTp("dup-seq",2360.0);
   CTestAssert::False(policy.ShouldEvaluate(basket,state,2350.0,2350.2,0.01,0.01,999,1000),
                      "Duplicate quote sequence must skip evaluation");
  }

void TestUnrelatedSymbolDoesNotIndexBasket(void)
  {
   CInMemoryBasketRepository repository;
   CSymbolBasketIndex index;
   CBasketAggregate basket=BuildActiveBasketWithTp("eur-only",2360.0);
   repository.Save(basket);
   index.Rebuild(&repository);

   CBasketId ids[];
   int count=index.FindActiveBasketIds("EURUSD",ids,5);
   CTestAssert::EqualInt(0,count,"Unrelated symbol must not return XAUUSD basket");
  }

void TestForceReevaluateAfterTransaction(void)
  {
   CTestClock clock;
   CInMemorySnapshotStore snapshotStore(&clock);
   CBasketFastStateRegistry registry;
   CSymbolBasketIndex index;
   CTradeTransactionFastPathService service(&snapshotStore,&registry,&index);

   CNormalizedTradeTransaction tx;
   tx.SetBasketId(CBasketId("tx-basket"));
   tx.SetOccurredAtUtc(2000);
   service.Handle(tx);

   CBasketFastState state;
   registry.TryGet(CBasketId("tx-basket"),state);
   CTestAssert::True(CForceReevaluationFlag::IsSet(state),"Transaction must set forceReevaluate");
   CTestAssert::EqualInt(2000,(int)state.LastTransactionUtc(),"Transaction must update lastTransactionUtc");
  }

void TestTimerFallbackRequiresTickSilence(void)
  {
   CInMemoryBasketRepository repository;
   CFastCommandStagingBuffer staging;
   CTimerFallbackEvaluationService fallback(&repository,NULL,NULL,&staging,NULL,
                                            CFastPathConfig::Create(1,2000,250,5,60000));
   fallback.NotifyTick();
   CTestAssert::EqualInt(0,fallback.RunIfDue(),"Recent tick must prevent fallback evaluation");
  }

void TestStaleQuoteDeferredOnFastPath(void)
  {
   CInMemoryMarketDataProvider marketData;
   CMarketQuote stale=CMarketQuote::Create("XAUUSD",2350.0,2350.2,20,0.01,2,0.01,1.0,1000,9000,
                                           BRE_TRADING_SESSION_OPEN,
                                           CSymbolTradingConstraints::Create(20,10,0.01,100.0,0.01));
   marketData.SetQuote(stale);
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
   CMarketContextProviderAdapter adapter(&marketData,CMarketSafetyConfig::Create(5000,500,30000));
   CBasketAggregate basket=BuildActiveBasketWithTp("stale-fast",2360.0);
   CMarketContext market;
   CRiskRuntimeContext risk;
   CTestAssert::False(adapter.TryBuildFromQuote(basket,stale,market,risk),"Stale quote must defer fast path");
  }

void TestPerTickBasketBudgetBounded(void)
  {
   CInMemoryBasketRepository repository;
   CSymbolBasketIndex index;
   for(int i=0;i<5;i++)
     {
      CBasketAggregate basket=BuildActiveBasketWithTp("budget-"+IntegerToString(i),2360.0);
      repository.Save(basket);
     }
   index.Rebuild(&repository);
   CBasketId ids[];
   int count=index.FindActiveBasketIds("XAUUSD",ids,2);
   CTestAssert::EqualInt(2,count,"Symbol index lookup must respect per-tick basket budget");
  }

void TestStagingBufferDoesNotPersist(void)
  {
   CFastCommandStagingBuffer staging;
   CInMemoryCommandQueue persistentQueue;
   CClosePositionsCommand *command=new CClosePositionsCommand();
   command.SetIdempotencyKey("fast-staging-key");
   staging.Enqueue(command);
   CTestAssert::EqualInt(1,staging.PendingCount(),"Staging buffer must hold command in memory");
   CTestAssert::EqualInt(0,persistentQueue.PendingCount(),"Persistent queue must remain empty until timer flush");
  }

void OnStart()
  {
   TestProfitLevelCrossTriggersEvaluation();
   TestRecoveryThresholdCrossTriggersEvaluation();
   TestDuplicateQuoteSequenceSkipsEvaluation();
   TestUnrelatedSymbolDoesNotIndexBasket();
   TestForceReevaluateAfterTransaction();
   TestTimerFallbackRequiresTickSilence();
   TestStaleQuoteDeferredOnFastPath();
   TestPerTickBasketBudgetBounded();
   TestStagingBufferDoesNotPersist();
   Print("TestFastMarketPath: all tests passed");
  }
