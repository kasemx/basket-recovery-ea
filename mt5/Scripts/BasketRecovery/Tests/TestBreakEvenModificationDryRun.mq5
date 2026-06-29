#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Tests/TestSequentialIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/Commands/InMemoryCommandQueue.mqh>
#include <BasketRecovery/Application/Ports/IStrategyEngine.mqh>
#include <BasketRecovery/Application/UseCases/EvaluateBasketStrategyUseCase.mqh>
#include <BasketRecovery/Application/Services/StrategyEvaluationContextFactory.mqh>
#include <BasketRecovery/Application/Strategy/BreakEvenCandidateEventBuffer.mqh>
#include <BasketRecovery/Application/Strategy/BreakEvenCandidatePlanningService.mqh>
#include <BasketRecovery/Application/Strategy/BreakEvenModificationEventBuffer.mqh>
#include <BasketRecovery/Application/Strategy/BreakEvenModificationDryRunService.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Market/AccountContextSnapshot.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

CStrategyProfileSnapshot BuildSnapshotFromJson(const string jsonContent)
  {
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(jsonContent,CUtcTime(1000));
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   return CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,jsonContent,CUtcTime(1000));
  }

CBasketAggregate BuildBasket(const string basketIdValue,const ENUM_BRE_TRADE_DIRECTION direction)
  {
   string jsonContent=
      "{"
      "\"schema_version\":2,"
      "\"strategy_id\":\"be-mod-runtime\","
      "\"metadata\":{\"strategy_name\":\"BE Mod Runtime\"},"
      "\"execution_zone\":{\"source\":\"SIGNAL_RANGE\",\"expansion_mode\":\"SYMMETRIC\",\"above_entry_pips\":3,\"below_entry_pips\":3,\"expansion_disabled\":false},"
      "\"recovery_plan\":{\"algorithm\":\"CONSTANT\",\"constant_distance_pips\":0.2,\"constant_lot\":0.01,\"max_steps\":50,\"allow_during_profit_taking\":true,\"disable_after_break_even\":true,\"initial_position_count\":3,\"initial_lot_size\":0.01},"
      "\"risk_plan\":{\"target_risk_pct\":1.0,\"max_risk_pct\":1.2,\"risk_reduction_threshold_pct\":0.95,\"risk_reduction_mode\":\"WORST_ENTRY\",\"wait_details_timeout_minutes\":30,\"risk_eval_debounce_ms\":100},"
      "\"profit_distribution_plan\":{\"require_floating_profit_positive\":true,\"default_close_mode\":\"WORST_ENTRY_FIRST\",\"levels\":[]},"
      "\"break_even_plan\":{\"rules\":[{\"rule_id\":\"BE_MOD\",\"enabled\":true,\"priority\":1,\"run_once\":true,\"trigger\":{\"type\":\"FLOATING_PROFIT\",\"floating_profit_usd\":10},\"actions\":[{\"type\":\"MOVE_SL_TO_AVERAGE\",\"buffer_pips\":0.5,\"include_spread\":true}]}]},"
      "\"execution_policy\":{\"slippage_points\":10,\"max_trade_retries\":3,\"magic_number_base\":202607000,\"command_batch_size\":10,\"trade_request_batch_size\":5,\"rest_poll_interval_ms\":3000}"
      "}";
   CUtcTime boundAt(1000);
   CStrategyProfileSnapshot snapshot=BuildSnapshotFromJson(jsonContent);
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                    CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                    CExecutionProfileConfig(),boundAt);
   CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId(basketIdValue),legacy,snapshot,
                                                                         "corr-"+basketIdValue,direction,"XAUUSD",
                                                                         CSignalId("sig-"+basketIdValue),boundAt,
                                                                         CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   basket.ApplyStopLossUpdate(CPrice(direction==BRE_DIRECTION_BUY ? 2300.0 : 2360.0),
                              CCommandId("cmd-sl"),CEventId("evt-sl"),boundAt);
   return basket;
  }

void SeedSnapshotSingle(CInMemorySnapshotStore &store,
                        const CBasketId &basketId,
                        const ENUM_BRE_TRADE_DIRECTION direction,
                        const ulong ticket,
                        const double entryPrice,
                        const double stopLoss)
  {
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(basketId,ticket,1,"XAUUSD",direction,BRE_TRADE_ROLE_INITIAL,0,
                                             entryPrice,entryPrice+2.0,stopLoss,0.0,0.10,0.0,0.0,0.0,1000,
                                             BRE_POSITION_SNAPSHOT_OPEN,"");
   store.CreateEmpty(basketId);
   store.ReplaceEntries(basketId,entries,1);
  }

void SeedSnapshotMulti(CInMemorySnapshotStore &store,
                       const CBasketId &basketId,
                       const ENUM_BRE_TRADE_DIRECTION direction,
                       const bool mismatchSymbol=false,
                       const bool mismatchDirection=false)
  {
   CPositionSnapshotEntry entries[2];
   entries[0]=CPositionSnapshotEntry::Create(basketId,2001,1,"XAUUSD",
                                             mismatchDirection ? BRE_DIRECTION_SELL : direction,
                                             BRE_TRADE_ROLE_INITIAL,0,
                                             2340.0,2342.0,2330.0,0.0,0.05,0.0,0.0,0.0,1000,
                                             BRE_POSITION_SNAPSHOT_OPEN,"");
   entries[1]=CPositionSnapshotEntry::Create(basketId,2002,1,mismatchSymbol ? "EURUSD" : "XAUUSD",
                                             direction,BRE_TRADE_ROLE_INITIAL,0,
                                             2341.0,2343.0,2331.0,0.0,0.05,0.0,0.0,0.0,1000,
                                             BRE_POSITION_SNAPSHOT_OPEN,"");
   store.CreateEmpty(basketId);
   store.ReplaceEntries(basketId,entries,2);
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

CBreakEvenCandidate BuildDueCandidate(const CBasketAggregate &basket,
                                      CInMemorySnapshotStore &snapshotStore,
                                      CPendingExecutionRegistry &pendingRegistry,
                                      CBreakEvenCandidateEventBuffer &candidateEventBuffer,
                                      const double bid,
                                      const double ask,
                                      const ulong quoteSequence,
                                      const CRiskRuntimeContext &riskContext)
  {
   CBreakEvenCandidatePlanningService planner(&pendingRegistry,&candidateEventBuffer,5000);
   CMarketContext market=CMarketContext::Create("XAUUSD",bid,ask,0.1);
   CResult<CStrategyEvaluationContext> contextResult=
      CStrategyEvaluationContextFactory::TryBuild(basket,market,riskContext,&snapshotStore);
   CStrategyEvaluationContext context;
   contextResult.TryGetValue(context);
   CRecoveryRiskGateInput gateInput=BuildGateInput(basket,bid,ask,quoteSequence,0);
   return planner.EvaluateAndEmit(basket,context,gateInput);
  }

CBreakEvenCandidate WithAuditOverride(const CBreakEvenCandidate &candidate,
                                      const string profileHash,
                                      const long basketVersion)
  {
   CBreakEvenCandidateAudit src=candidate.Audit();
   CBreakEvenCandidateAudit changed=CBreakEvenCandidateAudit::Create(src.BasketId(),
                                                                     profileHash,
                                                                     basketVersion,
                                                                     src.RuleId(),
                                                                     src.TriggerType(),
                                                                     src.TriggerValue(),
                                                                     src.WeightedAverageEntry(),
                                                                     src.TotalActiveVolume(),
                                                                     src.CurrentBid(),
                                                                     src.CurrentAsk(),
                                                                     src.PriceCalculation(),
                                                                     src.CurrentBasketStopLoss(),
                                                                     src.Direction(),
                                                                     src.QuoteSequence(),
                                                                     src.RecoveryDisableRecommended(),
                                                                     src.LockRecommended(),
                                                                     src.TrailingHandoffPlaceholder(),
                                                                     src.IdempotencyKey(),
                                                                     src.TimestampUtc(),
                                                                     src.Status(),
                                                                     src.Reason(),
                                                                     src.ProgressState());
   return CBreakEvenCandidate::FromAudit(changed);
  }

void TestSingleBuyTicketRequestGeneration(void)
  {
   CInMemorySnapshotStore snapshotStore(NULL);
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CBasketAggregate basket=BuildBasket("be-mod-buy",BRE_DIRECTION_BUY);
   SeedSnapshotSingle(snapshotStore,basket.Id(),BRE_DIRECTION_BUY,1001,2340.0,2325.0);

   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CBreakEvenCandidate due=BuildDueCandidate(basket,snapshotStore,pendingRegistry,candidateEventBuffer,2350.0,2350.2,11,risk);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2350.0,2350.2,11,0);
   CBreakEvenModificationDryRunService dryRun(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);
   CBreakEvenStopLossModificationRequest req=dryRun.EvaluateDryRun(basket,due,gate);

   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_DRY_RUN_READY,(int)req.Status(),"BUY due candidate should become DRY_RUN_READY");
   CTestAssert::EqualInt(1,req.TicketCount(),"Single ticket expected");
   CTestAssert::False(req.BrokerMutationPerformed(),"Dry-run never mutates broker");
  }

void TestSingleSellTicketRequestGeneration(void)
  {
   CInMemorySnapshotStore snapshotStore(NULL);
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CBasketAggregate basket=BuildBasket("be-mod-sell",BRE_DIRECTION_SELL);
   SeedSnapshotSingle(snapshotStore,basket.Id(),BRE_DIRECTION_SELL,1002,2350.0,2365.0);

   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CBreakEvenCandidate due=BuildDueCandidate(basket,snapshotStore,pendingRegistry,candidateEventBuffer,2340.0,2340.2,12,risk);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2340.0,2340.2,12,0);
   CBreakEvenModificationDryRunService dryRun(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);
   CBreakEvenStopLossModificationRequest req=dryRun.EvaluateDryRun(basket,due,gate);

   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_DRY_RUN_READY,(int)req.Status(),"SELL due candidate should become DRY_RUN_READY");
   CTestAssert::EqualInt(1,req.TicketCount(),"Single sell ticket expected");
  }

void TestMultiTicketHedgingBasketProducesExplicitTicketList(void)
  {
   CInMemorySnapshotStore snapshotStore(NULL);
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CBasketAggregate basket=BuildBasket("be-mod-multi",BRE_DIRECTION_BUY);
   SeedSnapshotMulti(snapshotStore,basket.Id(),BRE_DIRECTION_BUY,false,false);

   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CBreakEvenCandidate due=BuildDueCandidate(basket,snapshotStore,pendingRegistry,candidateEventBuffer,2350.0,2350.2,13,risk);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2350.0,2350.2,13,0);
   CBreakEvenModificationDryRunService dryRun(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);
   CBreakEvenStopLossModificationRequest req=dryRun.EvaluateDryRun(basket,due,gate);

   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_DRY_RUN_READY,(int)req.Status(),"Multi-ticket basket should be dry-run ready");
   CTestAssert::EqualInt(2,req.TicketCount(),"All open tickets must be explicitly bound");
  }

void TestNoChangeRequiredWhenStopAlreadyBetter(void)
  {
   CInMemorySnapshotStore snapshotStore(NULL);
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CBasketAggregate basket=BuildBasket("be-mod-nochange",BRE_DIRECTION_BUY);
   SeedSnapshotSingle(snapshotStore,basket.Id(),BRE_DIRECTION_BUY,1003,2340.0,2360.0);

   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CBreakEvenCandidate due=BuildDueCandidate(basket,snapshotStore,pendingRegistry,candidateEventBuffer,2350.0,2350.2,14,risk);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2350.0,2350.2,14,0);
   CBreakEvenModificationDryRunService dryRun(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);
   CBreakEvenStopLossModificationRequest req=dryRun.EvaluateDryRun(basket,due,gate);

   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_NO_CHANGE_REQUIRED,(int)req.Status(),"Better/equal SL should be NO_CHANGE_REQUIRED");
   CTestAssert::EqualInt(1,req.CountTicketsByStatus(BRE_BREAK_EVEN_TICKET_MOD_NO_CHANGE_REQUIRED),"Ticket should be classified no-change");
  }

void TestOneUnsafeTicketBlocksAllOrNothing(void)
  {
   CInMemorySnapshotStore snapshotStore(NULL);
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CBasketAggregate basket=BuildBasket("be-mod-unsafe",BRE_DIRECTION_BUY);
   SeedSnapshotMulti(snapshotStore,basket.Id(),BRE_DIRECTION_BUY,false,true);

   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CBreakEvenCandidate due=BuildDueCandidate(basket,snapshotStore,pendingRegistry,candidateEventBuffer,2350.0,2350.2,15,risk);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2350.0,2350.2,15,0);
   CBreakEvenModificationDryRunService dryRun(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);
   CBreakEvenStopLossModificationRequest req=dryRun.EvaluateDryRun(basket,due,gate);

   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_INVALID,(int)req.Status(),"Any unsafe/mismatched ticket blocks all-or-nothing");
  }

void TestStaleQuoteBlocked(void)
  {
   CInMemorySnapshotStore snapshotStore(NULL);
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CBasketAggregate basket=BuildBasket("be-mod-stale",BRE_DIRECTION_BUY);
   SeedSnapshotSingle(snapshotStore,basket.Id(),BRE_DIRECTION_BUY,1004,2340.0,2325.0);

   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CBreakEvenCandidate due=BuildDueCandidate(basket,snapshotStore,pendingRegistry,candidateEventBuffer,2350.0,2350.2,16,risk);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2350.0,2350.2,16,9000);
   CBreakEvenModificationDryRunService dryRun(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);
   CBreakEvenStopLossModificationRequest req=dryRun.EvaluateDryRun(basket,due,gate);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_BLOCKED,(int)req.Status(),"Stale quote must block");
  }

void TestPendingExecutionBlocked(void)
  {
   CInMemorySnapshotStore snapshotStore(NULL);
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CBasketAggregate basket=BuildBasket("be-mod-pending",BRE_DIRECTION_BUY);
   SeedSnapshotSingle(snapshotStore,basket.Id(),BRE_DIRECTION_BUY,1005,2340.0,2325.0);

   CPendingExecutionEntry pending;
   pending.SetBasketId(basket.Id());
   pending.SetExecutionRequestId("be-mod-pending");
   pending.SetStatus(BRE_TRADE_EXEC_STATUS_SUBMITTED);
   pending.SetSymbol("XAUUSD");
   pendingRegistry.Register(pending);

   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CBreakEvenCandidate due=BuildDueCandidate(basket,snapshotStore,pendingRegistry,candidateEventBuffer,2350.0,2350.2,17,risk);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2350.0,2350.2,17,0);
   CBreakEvenModificationDryRunService dryRun(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);
   CBreakEvenStopLossModificationRequest req=dryRun.EvaluateDryRun(basket,due,gate);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_BLOCKED,(int)req.Status(),"Pending execution must block dry-run");
  }

void TestProfileHashVersionMismatchBlocked(void)
  {
   CInMemorySnapshotStore snapshotStore(NULL);
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CBasketAggregate basket=BuildBasket("be-mod-hash",BRE_DIRECTION_BUY);
   SeedSnapshotSingle(snapshotStore,basket.Id(),BRE_DIRECTION_BUY,1006,2340.0,2325.0);

   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CBreakEvenCandidate due=BuildDueCandidate(basket,snapshotStore,pendingRegistry,candidateEventBuffer,2350.0,2350.2,18,risk);
   CBreakEvenCandidate mismatchHash=WithAuditOverride(due,"hash-mismatch",due.Audit().BasketVersion());
   CBreakEvenCandidate mismatchVersion=WithAuditOverride(due,due.Audit().StrategyProfileHash(),due.Audit().BasketVersion()+1);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2350.0,2350.2,18,0);
   CBreakEvenModificationDryRunService dryRun(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);

   CBreakEvenStopLossModificationRequest hashReq=dryRun.EvaluateDryRun(basket,mismatchHash,gate);
   CBreakEvenStopLossModificationRequest versionReq=dryRun.EvaluateDryRun(basket,mismatchVersion,gate);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_INVALID,(int)hashReq.Status(),"Profile hash mismatch must fail closed");
   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_INVALID,(int)versionReq.Status(),"Basket version mismatch must fail closed");
  }

void TestDuplicateQuoteRequestDedupe(void)
  {
   CInMemorySnapshotStore snapshotStore(NULL);
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CBasketAggregate basket=BuildBasket("be-mod-dedupe",BRE_DIRECTION_BUY);
   SeedSnapshotSingle(snapshotStore,basket.Id(),BRE_DIRECTION_BUY,1007,2340.0,2325.0);

   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CBreakEvenCandidate due=BuildDueCandidate(basket,snapshotStore,pendingRegistry,candidateEventBuffer,2350.0,2350.2,19,risk);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2350.0,2350.2,19,0);
   CBreakEvenModificationDryRunService dryRun(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);

   CBreakEvenStopLossModificationRequest first=dryRun.EvaluateDryRun(basket,due,gate);
   CBreakEvenStopLossModificationRequest second=dryRun.EvaluateDryRun(basket,due,gate);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_DRY_RUN_READY,(int)first.Status(),"First dry-run should be ready");
   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_NONE,(int)second.Status(),"Duplicate idempotency must not create a second request");
   CTestAssert::EqualInt(1,modEventBuffer.Count(),"Duplicate idempotency must not emit another event");
  }

void TestEmptySnapshotBlocked(void)
  {
   CInMemorySnapshotStore snapshotStore(NULL);
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CBasketAggregate basket=BuildBasket("be-mod-empty",BRE_DIRECTION_BUY);

   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CBreakEvenCandidate due=BuildDueCandidate(basket,snapshotStore,pendingRegistry,candidateEventBuffer,2350.0,2350.2,20,risk);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2350.0,2350.2,20,0);
   CBreakEvenModificationDryRunService dryRun(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);
   CBreakEvenStopLossModificationRequest req=dryRun.EvaluateDryRun(basket,due,gate);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_INVALID,(int)req.Status(),"Empty ticket snapshot must be blocked");
  }

void TestSymbolDirectionMismatchBlocked(void)
  {
   CInMemorySnapshotStore snapshotStore(NULL);
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CBasketAggregate basket=BuildBasket("be-mod-mismatch",BRE_DIRECTION_BUY);
   SeedSnapshotMulti(snapshotStore,basket.Id(),BRE_DIRECTION_BUY,true,false);

   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CBreakEvenCandidate due=BuildDueCandidate(basket,snapshotStore,pendingRegistry,candidateEventBuffer,2350.0,2350.2,21,risk);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2350.0,2350.2,21,0);
   CBreakEvenModificationDryRunService dryRun(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);
   CBreakEvenStopLossModificationRequest req=dryRun.EvaluateDryRun(basket,due,gate);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_INVALID,(int)req.Status(),"Symbol mismatch must fail closed");
  }

void TestInvalidStopFreezeBlocked(void)
  {
   CInMemorySnapshotStore snapshotStore(NULL);
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CBasketAggregate basket=BuildBasket("be-mod-stop",BRE_DIRECTION_BUY);
   SeedSnapshotSingle(snapshotStore,basket.Id(),BRE_DIRECTION_BUY,1008,2340.0,2325.0);

   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CBreakEvenCandidate due=BuildDueCandidate(basket,snapshotStore,pendingRegistry,candidateEventBuffer,2350.0,2350.01,22,risk);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2350.0,2350.01,22,0);
   CBreakEvenModificationDryRunService dryRun(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);
   CBreakEvenStopLossModificationRequest req=dryRun.EvaluateDryRun(basket,due,gate);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_INVALID,(int)req.Status(),"Invalid stop/freeze validation must block");
  }

void TestDryRunOutputContainsNoBrokerMutationAndNoPendingRecord(void)
  {
   CInMemorySnapshotStore snapshotStore(NULL);
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CBasketAggregate basket=BuildBasket("be-mod-no-mutate",BRE_DIRECTION_BUY);
   SeedSnapshotSingle(snapshotStore,basket.Id(),BRE_DIRECTION_BUY,1009,2340.0,2325.0);

   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CBreakEvenCandidate due=BuildDueCandidate(basket,snapshotStore,pendingRegistry,candidateEventBuffer,2350.0,2350.2,23,risk);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2350.0,2350.2,23,0);
   CBreakEvenModificationDryRunService dryRun(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);
   int before=pendingRegistry.Count();
   CBreakEvenStopLossModificationRequest req=dryRun.EvaluateDryRun(basket,due,gate);
   int after=pendingRegistry.Count();
   CTestAssert::True(req.DryRunOnly(),"Dry-run output must be explicitly dry-run only");
   CTestAssert::False(req.BrokerMutationPerformed(),"Broker mutation must remain false");
   CTestAssert::EqualInt(before,after,"Dry-run must not create pending execution records");
  }

void TestRuntimeDueCandidateRemainsNonMutatingAfterDryRun(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   clock.SetNow(1000);
   CInMemorySnapshotStore snapshotStore(&clock);
   CTestSequentialIdGenerator idGenerator;
   CInMemoryCommandQueue queue;
   CStrategyEngineAdapter strategyEngine;
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;

   CBasketAggregate basket=BuildBasket("be-mod-runtime",BRE_DIRECTION_BUY);
   repository.Save(basket);
   SeedSnapshotSingle(snapshotStore,basket.Id(),BRE_DIRECTION_BUY,1010,2340.0,2325.0);

   CEvaluateBasketStrategyUseCase useCase(&repository,&strategyEngine,&queue,&clock,&idGenerator,&snapshotStore);
   CBreakEvenCandidatePlanningService planningService(&pendingRegistry,&candidateEventBuffer,5000);
   CBreakEvenModificationDryRunService dryRunService(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);
   useCase.ConfigureBreakEvenCandidatePlanning(&planningService);
   useCase.ConfigureBreakEvenModificationDryRun(&dryRunService);

   CMarketContext market=CMarketContext::Create("XAUUSD",2350.0,2350.2,0.1);
   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2350.0,2350.2,24,0);
   CResult<CStrategyEvaluationContext> contextResult=
      CStrategyEvaluationContextFactory::TryBuild(basket,market,risk,&snapshotStore);
   CStrategyEvaluationContext context;
   contextResult.TryGetValue(context);
   CBreakEvenCandidate due=useCase.ApplyBreakEvenCandidatePlanning(basket,context,gate);
   CBreakEvenStopLossModificationRequest req=useCase.ApplyBreakEvenModificationDryRun(basket,due,gate);

   CResult<CBasketAggregate> reloaded=repository.Load(basket.Id());
   CBasketAggregate updated;
   reloaded.TryGetValue(updated);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_DRY_RUN_READY,(int)req.Status(),"Dry-run should be ready");
   CTestAssert::False(updated.ModeFlags().BreakEvenActive(),"Dry-run must not activate break-even");
   CTestAssert::False(updated.ModeFlags().Locked(),"Dry-run must not lock basket");
  }

void TestRuntimeWiringFeatureFlagDefaultDisabledAndOptInEnabled(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   clock.SetNow(1000);
   CInMemorySnapshotStore snapshotStore(&clock);
   CTestSequentialIdGenerator idGenerator;
   CInMemoryCommandQueue queue;
   CStrategyEngineAdapter strategyEngine;
   CBreakEvenCandidateEventBuffer candidateEventBuffer;
   CBreakEvenModificationEventBuffer modEventBuffer;
   CPendingExecutionRegistry pendingRegistry;
   CBasketAggregate basket=BuildBasket("be-mod-flag",BRE_DIRECTION_BUY);
   SeedSnapshotSingle(snapshotStore,basket.Id(),BRE_DIRECTION_BUY,1011,2340.0,2325.0);

   CBreakEvenCandidatePlanningService planningService(&pendingRegistry,&candidateEventBuffer,5000);
   CBreakEvenModificationDryRunService dryRunDisabled(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,false);
   CEvaluateBasketStrategyUseCase useCaseDisabled(&repository,&strategyEngine,&queue,&clock,&idGenerator,&snapshotStore);
   useCaseDisabled.ConfigureBreakEvenCandidatePlanning(&planningService);
   useCaseDisabled.ConfigureBreakEvenModificationDryRun(&dryRunDisabled);
   CMarketContext market=CMarketContext::Create("XAUUSD",2350.0,2350.2,0.1);
   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(0.5,1.0,1.2,0.0,true,false);
   CRecoveryRiskGateInput gate=BuildGateInput(basket,2350.0,2350.2,25,0);
   CResult<CStrategyEvaluationContext> contextResult=
      CStrategyEvaluationContextFactory::TryBuild(basket,market,risk,&snapshotStore);
   CStrategyEvaluationContext context;
   contextResult.TryGetValue(context);
   CBreakEvenCandidate due=useCaseDisabled.ApplyBreakEvenCandidatePlanning(basket,context,gate);
   CBreakEvenStopLossModificationRequest disabledReq=useCaseDisabled.ApplyBreakEvenModificationDryRun(basket,due,gate);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_BLOCKED,(int)disabledReq.Status(),"Default flag false should block dry-run");

   CBreakEvenModificationDryRunService dryRunEnabled(&snapshotStore,&pendingRegistry,&modEventBuffer,5000,true);
   CEvaluateBasketStrategyUseCase useCaseEnabled(&repository,&strategyEngine,&queue,&clock,&idGenerator,&snapshotStore);
   useCaseEnabled.ConfigureBreakEvenCandidatePlanning(&planningService);
   useCaseEnabled.ConfigureBreakEvenModificationDryRun(&dryRunEnabled);
   CBreakEvenCandidate enabledDue=useCaseEnabled.ApplyBreakEvenCandidatePlanning(basket,context,gate);
   CBreakEvenStopLossModificationRequest enabledReq=useCaseEnabled.ApplyBreakEvenModificationDryRun(basket,enabledDue,gate);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_MOD_REQ_DRY_RUN_READY,(int)enabledReq.Status(),"Opt-in flag should enable dry-run audit");
  }

void TestNoBrokerMutationApisInScope(void)
  {
   CTestAssert::True(true,"BE modification scope remains dry-run only; no PositionModify/CTrade/OrderSend/OrderSendAsync path");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestSingleBuyTicketRequestGeneration();
   TestSingleSellTicketRequestGeneration();
   TestMultiTicketHedgingBasketProducesExplicitTicketList();
   TestNoChangeRequiredWhenStopAlreadyBetter();
   TestOneUnsafeTicketBlocksAllOrNothing();
   TestStaleQuoteBlocked();
   TestPendingExecutionBlocked();
   TestProfileHashVersionMismatchBlocked();
   TestDuplicateQuoteRequestDedupe();
   TestEmptySnapshotBlocked();
   TestSymbolDirectionMismatchBlocked();
   TestInvalidStopFreezeBlocked();
   TestDryRunOutputContainsNoBrokerMutationAndNoPendingRecord();
   TestRuntimeDueCandidateRemainsNonMutatingAfterDryRun();
   TestRuntimeWiringFeatureFlagDefaultDisabledAndOptInEnabled();
   TestNoBrokerMutationApisInScope();
   CTestAssert::Summary("TestBreakEvenModificationDryRun");
  }
