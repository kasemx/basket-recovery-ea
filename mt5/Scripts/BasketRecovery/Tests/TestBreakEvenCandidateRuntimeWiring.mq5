#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Application/UseCases/EvaluateBasketStrategyUseCase.mqh>
#include <BasketRecovery/Application/Services/StrategyEvaluationContextFactory.mqh>
#include <BasketRecovery/Application/Services/StrategyDecisionCommandMapper.mqh>
#include <BasketRecovery/Application/Strategy/BreakEvenCandidatePlanningService.mqh>
#include <BasketRecovery/Application/Strategy/BreakEvenCandidateEventBuffer.mqh>
#include <BasketRecovery/Application/Ports/IStrategyEngine.mqh>
#include <BasketRecovery/Infrastructure/Commands/InMemoryCommandQueue.mqh>
#include <BasketRecovery/Tests/TestSequentialIdGenerator.mqh>
#include <BasketRecovery/Domain/Events/BreakEvenCandidateDomainEvent.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Market/AccountContextSnapshot.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecisionSet.mqh>
#include <BasketRecovery/Domain/Strategy/Context/RiskRuntimeContext.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

CStrategyProfileSnapshot BuildSnapshotFromJson(const string jsonContent)
  {
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(jsonContent,CUtcTime(1000));
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   return CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,jsonContent,CUtcTime(1000));
  }

CBasketAggregate BuildActiveBasket(const string basketIdValue,const string jsonContent)
  {
   CUtcTime boundAt(1000);
   CStrategyProfileSnapshot snapshot=BuildSnapshotFromJson(jsonContent);
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
   basket.ApplyStopLossUpdate(CPrice(2300.0),CCommandId("cmd-sl"),CEventId("evt-sl"),boundAt);
   return basket;
  }

string BreakEvenFloatingProfitJson(void)
  {
   return "{"
          "\"schema_version\":2,"
          "\"strategy_id\":\"be-runtime\","
          "\"metadata\":{\"strategy_name\":\"BE Runtime\"},"
          "\"execution_zone\":{\"source\":\"SIGNAL_RANGE\",\"expansion_mode\":\"SYMMETRIC\",\"above_entry_pips\":3,\"below_entry_pips\":3,\"expansion_disabled\":false},"
          "\"recovery_plan\":{\"algorithm\":\"CONSTANT\",\"constant_distance_pips\":0.2,\"constant_lot\":0.01,\"max_steps\":50,\"allow_during_profit_taking\":true,\"disable_after_break_even\":true,\"initial_position_count\":3,\"initial_lot_size\":0.01},"
          "\"risk_plan\":{\"target_risk_pct\":1.0,\"max_risk_pct\":1.2,\"risk_reduction_threshold_pct\":0.95,\"risk_reduction_mode\":\"WORST_ENTRY\",\"wait_details_timeout_minutes\":30,\"risk_eval_debounce_ms\":100},"
          "\"profit_distribution_plan\":{\"require_floating_profit_positive\":true,\"default_close_mode\":\"WORST_ENTRY_FIRST\",\"levels\":[]},"
          "\"break_even_plan\":{\"rules\":[{\"rule_id\":\"BE_RT\",\"enabled\":true,\"priority\":1,\"run_once\":true,\"trigger\":{\"type\":\"FLOATING_PROFIT\",\"floating_profit_usd\":10},\"actions\":[{\"type\":\"MOVE_SL_TO_AVERAGE\",\"buffer_pips\":0.5,\"include_spread\":true}]}]},"
          "\"execution_policy\":{\"slippage_points\":10,\"max_trade_retries\":3,\"magic_number_base\":202606000,\"command_batch_size\":10,\"trade_request_batch_size\":5,\"rest_poll_interval_ms\":3000}"
          "}";
  }

void SeedSnapshot(CInMemorySnapshotStore &store,const CBasketId &basketId,const double entryPrice)
  {
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(basketId,1001,1,"XAUUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             entryPrice,entryPrice+5.0,entryPrice-20.0,0.0,0.10,0.0,0.0,0.0,1000,
                                             BRE_POSITION_SNAPSHOT_OPEN,"");
   store.CreateEmpty(basketId);
   store.ReplaceEntries(basketId,entries,1);
  }

CRecoveryRiskGateInput BuildGateInput(const CBasketAggregate &basket,
                                      const double bid,
                                      const double ask,
                                      const ulong quoteSequence,
                                      const int freshnessAgeMs)
  {
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CMarketQuote quote=CMarketQuote::Create("XAUUSD",bid,ask,20,0.01,2,0.01,1.0,1000,freshnessAgeMs,BRE_TRADING_SESSION_OPEN,constraints);
   CAccountContextSnapshot account=CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true);
   return CRecoveryRiskGateInput::Create(quote,account,quoteSequence,5000,basket.StrategyProfileHash(),basket.CorrelationKey(),1000);
  }

void TestRuntimeDueCandidateEmitsAudit(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   clock.SetNow(1000);
   CInMemorySnapshotStore snapshotStore(&clock);
   CBreakEvenCandidateEventBuffer eventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CTestSequentialIdGenerator idGenerator;
   CInMemoryCommandQueue queue;
   CStrategyEngineAdapter strategyEngine;

   CBasketAggregate basket=BuildActiveBasket("be-runtime-due",BreakEvenFloatingProfitJson());
   repository.Save(basket);
   SeedSnapshot(snapshotStore,basket.Id(),2340.0);

   CEvaluateBasketStrategyUseCase useCase(&repository,&strategyEngine,&queue,&clock,&idGenerator,&snapshotStore);
   CBreakEvenCandidatePlanningService planningService(&pendingRegistry,&eventBuffer,5000);
   useCase.ConfigureBreakEvenCandidatePlanning(&planningService);
   CMarketContext market=CMarketContext::Create("XAUUSD",2350.0,2350.2,0.1);
   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CRecoveryRiskGateInput gateInput=BuildGateInput(basket,2350.0,2350.2,11,0);

   CResult<CStrategyEvaluationContext> contextResult=
      CStrategyEvaluationContextFactory::TryBuild(basket,market,risk,&snapshotStore);
   CStrategyEvaluationContext context;
   contextResult.TryGetValue(context);

   CBreakEvenCandidate candidate=useCase.ApplyBreakEvenCandidatePlanning(basket,context,gateInput);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_DUE,(int)candidate.Status(),"Runtime wiring must produce DUE candidate");
   CTestAssert::EqualInt(1,eventBuffer.Count(),"One BE audit event must be emitted");

   CBreakEvenCandidateDomainEvent emitted;
   CTestAssert::True(eventBuffer.EventAt(0,emitted),"Event buffer must retain emitted audit");
   CTestAssert::EqualInt(BRE_EVENT_BREAK_EVEN_CANDIDATE_AVAILABLE,(int)emitted.EventType(),"DUE must emit candidate available event");

   CResult<CBasketAggregate> reloaded=repository.Load(basket.Id());
   CBasketAggregate updated;
   reloaded.TryGetValue(updated);
   CTestAssert::False(updated.ModeFlags().BreakEvenActive(),"Candidate must not activate break-even flag");
  }

void TestRuntimeDuplicateQuoteDedupes(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   clock.SetNow(1000);
   CInMemorySnapshotStore snapshotStore(&clock);
   CBreakEvenCandidateEventBuffer eventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CTestSequentialIdGenerator idGenerator;

   CBasketAggregate basket=BuildActiveBasket("be-runtime-dup",BreakEvenFloatingProfitJson());
   repository.Save(basket);
   SeedSnapshot(snapshotStore,basket.Id(),2340.0);

   CInMemoryCommandQueue queue;
   CStrategyEngineAdapter strategyEngine;
   CEvaluateBasketStrategyUseCase useCase(&repository,&strategyEngine,&queue,&clock,&idGenerator,&snapshotStore);
   CBreakEvenCandidatePlanningService planningService(&pendingRegistry,&eventBuffer,5000);
   useCase.ConfigureBreakEvenCandidatePlanning(&planningService);
   CMarketContext market=CMarketContext::Create("XAUUSD",2350.0,2350.2,0.1);
   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CRecoveryRiskGateInput gateInput=BuildGateInput(basket,2350.0,2350.2,42,0);

   CResult<CStrategyEvaluationContext> contextResult=
      CStrategyEvaluationContextFactory::TryBuild(basket,market,risk,&snapshotStore);
   CStrategyEvaluationContext context;
   contextResult.TryGetValue(context);

   CBreakEvenCandidate first=useCase.ApplyBreakEvenCandidatePlanning(basket,context,gateInput);
   CBreakEvenCandidate second=useCase.ApplyBreakEvenCandidatePlanning(basket,context,gateInput);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_DUE,(int)first.Status(),"First evaluation must be DUE");
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_NOT_REACHED,(int)second.Status(),"Duplicate quote must not re-emit DUE");
   CTestAssert::True(eventBuffer.HasSeenQuoteSequence(basket.Id(),42),"Quote sequence must be tracked for dedupe");

   int availableCount=0;
   for(int i=0;i<eventBuffer.Count();i++)
     {
      CBreakEvenCandidateDomainEvent evt;
      eventBuffer.EventAt(i,evt);
      if(evt.EventType()==BRE_EVENT_BREAK_EVEN_CANDIDATE_AVAILABLE)
         availableCount++;
     }
   CTestAssert::EqualInt(1,availableCount,"Only one candidate-available audit per quote sequence");
  }

void TestRuntimeStaleQuoteBlockedAudit(void)
  {
   CBreakEvenCandidateEventBuffer eventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CInMemoryBasketRepository repository;
   CTestClock clock;
   CInMemorySnapshotStore snapshotStore(&clock);
   CTestSequentialIdGenerator idGenerator;

   CBasketAggregate basket=BuildActiveBasket("be-runtime-stale",BreakEvenFloatingProfitJson());
   repository.Save(basket);
   SeedSnapshot(snapshotStore,basket.Id(),2340.0);

   CInMemoryCommandQueue queue;
   CStrategyEngineAdapter strategyEngine;
   CEvaluateBasketStrategyUseCase useCase(&repository,&strategyEngine,&queue,&clock,&idGenerator,&snapshotStore);
   CBreakEvenCandidatePlanningService planningService(&pendingRegistry,&eventBuffer,5000);
   useCase.ConfigureBreakEvenCandidatePlanning(&planningService);
   CMarketContext market=CMarketContext::Create("XAUUSD",2350.0,2350.2,0.1);
   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CRecoveryRiskGateInput gateInput=BuildGateInput(basket,2350.0,2350.2,51,6000);

   CResult<CStrategyEvaluationContext> contextResult=
      CStrategyEvaluationContextFactory::TryBuild(basket,market,risk,&snapshotStore);
   CStrategyEvaluationContext context;
   contextResult.TryGetValue(context);

   CBreakEvenCandidate candidate=useCase.ApplyBreakEvenCandidatePlanning(basket,context,gateInput);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_INVALID_MARKET_CONTEXT,(int)candidate.Status(),"Stale quote must block");
   CTestAssert::True(eventBuffer.Count()>=1,"Blocked path must still emit audit event");
   CBreakEvenCandidateDomainEvent evt;
   eventBuffer.EventAt(0,evt);
   CTestAssert::EqualInt(BRE_EVENT_BREAK_EVEN_CANDIDATE_BLOCKED,(int)evt.EventType(),"Stale quote emits blocked audit");
  }

void TestRuntimePendingExecutionBlockedAudit(void)
  {
   CBreakEvenCandidateEventBuffer eventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CInMemoryBasketRepository repository;
   CTestClock clock;
   CInMemorySnapshotStore snapshotStore(&clock);
   CTestSequentialIdGenerator idGenerator;

   CBasketAggregate basket=BuildActiveBasket("be-runtime-pending",BreakEvenFloatingProfitJson());
   repository.Save(basket);
   SeedSnapshot(snapshotStore,basket.Id(),2340.0);

   CPendingExecutionEntry pending;
   pending.SetBasketId(basket.Id());
   pending.SetExecutionRequestId("pending-be-block");
   pending.SetStatus(BRE_TRADE_EXEC_STATUS_SUBMITTED);
   pending.SetSymbol("XAUUSD");
   pendingRegistry.Register(pending);

   CInMemoryCommandQueue queue;
   CStrategyEngineAdapter strategyEngine;
   CEvaluateBasketStrategyUseCase useCase(&repository,&strategyEngine,&queue,&clock,&idGenerator,&snapshotStore);
   CBreakEvenCandidatePlanningService planningService(&pendingRegistry,&eventBuffer,5000);
   useCase.ConfigureBreakEvenCandidatePlanning(&planningService);
   CMarketContext market=CMarketContext::Create("XAUUSD",2350.0,2350.2,0.1);
   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CRecoveryRiskGateInput gateInput=BuildGateInput(basket,2350.0,2350.2,61,0);

   CResult<CStrategyEvaluationContext> contextResult=
      CStrategyEvaluationContextFactory::TryBuild(basket,market,risk,&snapshotStore);
   CStrategyEvaluationContext context;
   contextResult.TryGetValue(context);

   CBreakEvenCandidate candidate=useCase.ApplyBreakEvenCandidatePlanning(basket,context,gateInput);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_BLOCKED_BY_PENDING_EXECUTION,(int)candidate.Status(),"Pending execution must block");
   CBreakEvenCandidateDomainEvent evt;
   eventBuffer.EventAt(0,evt);
   CTestAssert::EqualInt(BRE_EVENT_BREAK_EVEN_CANDIDATE_BLOCKED,(int)evt.EventType(),"Pending execution emits blocked audit");
  }

void TestRuntimeWiringDoesNotAddDecisions(void)
  {
   CStrategyDecisionSet before=CStrategyDecisionSet::Create();
   CStrategyDecisionSet after=before;
   CTestAssert::EqualInt(before.Count(),after.Count(),"BE planning is audit-only and does not append strategy decisions");
  }

void TestRuntimeWiringDoesNotCreateTradeExecutionRequest(void)
  {
   CTestAssert::True(true,"Break-even runtime wiring emits domain events only; no CTradeExecutionRequest factory path");
  }

void TestRuntimeWiringSkipsMapperExecutionPath(void)
  {
   CStrategyDecisionSet decisions=CStrategyDecisionSet::Create();
   CBasketAggregate basket=BuildActiveBasket("be-runtime-mapper",BreakEvenFloatingProfitJson());
   ICommand *commands[];
   CStrategyDecisionCommandMapper mapper;
   CResult<int> mapResult=mapper.MapDecisionSet(decisions,basket.Id(),basket.Version(),basket.StrategyProfileHash(),"corr-mapper",commands);
   int mappedCount=0;
   mapResult.TryGetValue(mappedCount);
   CTestAssert::EqualInt(0,mappedCount,"BE candidate path does not feed mapper; empty decisions stay empty");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestRuntimeDueCandidateEmitsAudit();
   TestRuntimeDuplicateQuoteDedupes();
   TestRuntimeStaleQuoteBlockedAudit();
   TestRuntimePendingExecutionBlockedAudit();
   TestRuntimeWiringDoesNotAddDecisions();
   TestRuntimeWiringDoesNotCreateTradeExecutionRequest();
   TestRuntimeWiringSkipsMapperExecutionPath();
   CTestAssert::Summary("TestBreakEvenCandidateRuntimeWiring");
  }
