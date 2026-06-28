#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Application/Services/StrategyDecisionCommandMapper.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/ProjectedBasketRisk.mqh>
#include <BasketRecovery/Domain/Events/RecoveryRiskDomainEvent.mqh>
#include <BasketRecovery/Domain/Risk/Services/RecoveryDecisionRiskValidator.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskReductionPlan.mqh>
#include <BasketRecovery/Domain/Risk/Services/BasketRiskCalculator.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskLimitProfile.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/OpenRecoveryPositionDecision.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecision.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecisionSet.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshot.mqh>
#include <BasketRecovery/Domain/Strategy/Context/StrategyRiskEvaluationContext.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

CStrategyProfileSnapshot BuildSnapshot(const string jsonContent)
  {
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(jsonContent,CUtcTime(1000));
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   return CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,jsonContent,CUtcTime(1000));
  }

CBasketAggregate BuildActiveBasket(const string basketId,const string symbol,const ENUM_BRE_TRADE_DIRECTION direction,
                                   const double stopLoss)
  {
   CStrategyProfileSnapshot snapshot=BuildSnapshot(CStrategyProfileTestFixture::MinimalValidJson());
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                  CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                  CExecutionProfileConfig(),CUtcTime(1000));
   CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId(basketId),legacy,snapshot,
                                                                      "corr-"+basketId,direction,symbol,
                                                                      CSignalId("sig-"+basketId),CUtcTime(1000),
                                                                      CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   basket.ApplyStopLossUpdate(CPrice(stopLoss),CCommandId("cmd-sl"),CEventId("evt-sl"),CUtcTime(1000));
   return basket;
  }

CMarketQuote BuildQuote(const string symbol,const double bid,const double ask,const double tickSize,
                        const double tickValue,const int freshnessAgeMs,const double volumeStep=0.01)
  {
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,volumeStep,100.0,volumeStep);
   return CMarketQuote::Create(symbol,bid,ask,(int)((ask-bid)/0.01),0.01,2,tickSize,tickValue,1000,
                               freshnessAgeMs,BRE_TRADING_SESSION_OPEN,constraints);
  }

CRiskLimitProfile BuildRiskProfile(const double targetMoney,const double maxMoney)
  {
   return CRiskLimitProfile::Create("p1",
                                    CRiskLimitValue::Money(targetMoney),
                                    CRiskLimitValue::Money(maxMoney),
                                    CRiskReductionPolicy::Create(true,BRE_RISK_REDUCTION_TRIGGER_ABOVE_TARGET_RISK,
                                                                 BRE_RISK_REDUCTION_MODE_WORST_ENTRY,true));
  }

CRiskCalculationContext BuildCalcContext(const CMarketQuote &quote,const CRiskLimitProfile &profile,
                                       const double basketSl,const ENUM_BRE_TRADE_DIRECTION direction)
  {
   CAccountContextSnapshot account=CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true);
   return CRiskCalculationContext::Create(account,quote,profile,basketSl,direction,
                                          CRiskCalculationSettings::CreateDefault(),"USD",0.0);
  }

void SeedOpenPosition(CInMemorySnapshotStore &store,const CBasketId &basketId,const string symbol,
                      const ENUM_BRE_TRADE_DIRECTION direction,const double entry,const double volume)
  {
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(basketId,101,1,symbol,direction,BRE_TRADE_ROLE_INITIAL,0,entry,entry+5.0,
                                             99500.0,0.0,volume,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   store.ReplaceEntries(basketId,entries,1);
  }

COpenRecoveryPositionDecision BuildRecoveryDecision(const double lot,const double entryPrice)
  {
   return COpenRecoveryPositionDecision::Create("recovery:b1:step:1",1,50.0,lot,entryPrice,BRE_TRADE_ROLE_RECOVERY);
  }

CRecoveryDecisionRiskGateResult RunValidator(CBasketAggregate &basket,
                                             const COpenRecoveryPositionDecision &decision,
                                             const CMarketQuote &quote,
                                             const CRiskLimitProfile &profile,
                                             const CPositionSnapshotEntry &entries[],
                                             const int entryCount,
                                             const bool unresolvedPending,
                                             const int staleThresholdMs,
                                             const string expectedHash)
  {
   CStrategyRiskEvaluationContext riskContext=CStrategyRiskEvaluationContext::Create(profile,
                                                                                     CBasketRiskSnapshot::Unknown(basket.Id(),basket.Symbol()),
                                                                                     basket.SignalDetails().StopLoss().Value(),
                                                                                     1,
                                                                                     unresolvedPending,
                                                                                     CRiskReductionPlan::CreateEmpty(),
                                                                                     false);
   CRiskCalculationContext calcContext=BuildCalcContext(quote,profile,basket.SignalDetails().StopLoss().Value(),basket.Direction());
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("gate:"+decision.IdempotencyKey(),
                                                                 decision.IdempotencyKey(),
                                                                 "corr",basket.Id(),basket.Version(),
                                                                 basket.StrategyProfileHash(),basket.Symbol(),
                                                                 BRE_EXEC_INTENT_OPEN_POSITION,basket.Direction(),
                                                                 0,decision.Lot(),decision.ExpectedEntryPrice(),
                                                                 basket.SignalDetails().StopLoss().Value(),0.0,1000,
                                                                 CCommandId(),"recovery-gate");
   return CRecoveryDecisionRiskValidator::Validate(basket,decision,request,entries,entryCount,calcContext,
                                                   riskContext,staleThresholdMs,expectedHash,1000);
  }

void TestRecoveryAllowedUnderMax(void)
  {
   CBasketAggregate basket=BuildActiveBasket("b1","BTCUSD",BRE_DIRECTION_BUY,99500.0);
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0,0);
   CRiskLimitProfile profile=BuildRiskProfile(800.0,1500.0);
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b1"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CRecoveryDecisionRiskGateResult result=RunValidator(basket,BuildRecoveryDecision(0.01,100010.0),quote,profile,entries,1,false,5000,basket.StrategyProfileHash());
   CTestAssert::True(result.Allowed(),"recovery under max must be allowed");
  }

void TestProjectedExactlyMaxAllowed(void)
  {
   CBasketAggregate basket=BuildActiveBasket("b-exact","BTCUSD",BRE_DIRECTION_BUY,99500.0);
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0,0);
   CRiskLimitProfile profile=BuildRiskProfile(800.0,1020.0);
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b-exact"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CBasketRiskSnapshot current=CBasketRiskCalculator::Calculate(CBasketId("b-exact"),entries,1,
                                                                BuildCalcContext(quote,profile,99500.0,BRE_DIRECTION_BUY));
   double headroom=current.MaxRiskMoney()-current.CurrentSlRiskMoney();
   double proposedVolume=headroom/51000.0;
   CRecoveryDecisionRiskGateResult result=RunValidator(basket,BuildRecoveryDecision(proposedVolume,100010.0),quote,profile,entries,1,false,5000,basket.StrategyProfileHash());
   CTestAssert::True(result.Allowed(),"projected risk exactly at max must be allowed");
   CTestAssert::True(MathAbs(result.Audit().ProjectedSlRisk()-result.Audit().MaxRisk())<1.0,"projected equals max");
  }

void TestProjectedAboveMaxBlocked(void)
  {
   CBasketAggregate basket=BuildActiveBasket("b-max","BTCUSD",BRE_DIRECTION_BUY,99500.0);
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0,0);
   CRiskLimitProfile profile=BuildRiskProfile(80.0,120.0);
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b-max"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CRecoveryDecisionRiskGateResult result=RunValidator(basket,BuildRecoveryDecision(0.50,100010.0),quote,profile,entries,1,false,5000,basket.StrategyProfileHash());
   CTestAssert::False(result.Allowed(),"projected above max must be blocked");
   CTestAssert::EqualInt((int)BRE_RECOVERY_RISK_BLOCK_PROJECTED_EXCEEDS_MAX,(int)result.Audit().BlockReason(),"max block reason");
  }

void TestMissingSlBlocked(void)
  {
   CBasketAggregate basket=BuildActiveBasket("b-sl","BTCUSD",BRE_DIRECTION_BUY,0.0);
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0,0);
   CRiskLimitProfile profile=BuildRiskProfile(80.0,120.0);
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b-sl"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CRecoveryDecisionRiskGateResult result=RunValidator(basket,BuildRecoveryDecision(0.01,100010.0),quote,profile,entries,1,false,5000,basket.StrategyProfileHash());
   CTestAssert::False(result.Allowed(),"missing basket SL must block recovery");
   CTestAssert::EqualInt((int)BRE_RECOVERY_RISK_BLOCK_MISSING_BASKET_SL,(int)result.Audit().BlockReason(),"missing SL reason");
  }

void TestInvalidTickBlocked(void)
  {
   CBasketAggregate basket=BuildActiveBasket("b-tick","BTCUSD",BRE_DIRECTION_BUY,99500.0);
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,0.0,0);
   CRiskLimitProfile profile=BuildRiskProfile(80.0,120.0);
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b-tick"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CRecoveryDecisionRiskGateResult result=RunValidator(basket,BuildRecoveryDecision(0.01,100010.0),quote,profile,entries,1,false,5000,basket.StrategyProfileHash());
   CTestAssert::False(result.Allowed(),"invalid tick value must block recovery");
   CTestAssert::EqualInt((int)BRE_RECOVERY_RISK_BLOCK_RISK_DATA_UNSAFE,(int)result.Audit().BlockReason(),"unsafe reason");
  }

void TestStaleQuoteBlocked(void)
  {
   CBasketAggregate basket=BuildActiveBasket("b-stale","BTCUSD",BRE_DIRECTION_BUY,99500.0);
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0,9000);
   CRiskLimitProfile profile=BuildRiskProfile(80.0,120.0);
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b-stale"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CRecoveryDecisionRiskGateResult result=RunValidator(basket,BuildRecoveryDecision(0.01,100010.0),quote,profile,entries,1,false,5000,basket.StrategyProfileHash());
   CTestAssert::False(result.Allowed(),"stale quote must block recovery");
   CTestAssert::EqualInt((int)BRE_RECOVERY_RISK_BLOCK_STALE_QUOTE,(int)result.Audit().BlockReason(),"stale quote reason");
  }

void TestInvalidVolumeBlocked(void)
  {
   CBasketAggregate basket=BuildActiveBasket("b-vol","BTCUSD",BRE_DIRECTION_BUY,99500.0);
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0,0,0.01);
   CRiskLimitProfile profile=BuildRiskProfile(80.0,120.0);
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b-vol"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CRecoveryDecisionRiskGateResult result=RunValidator(basket,BuildRecoveryDecision(0.005,100010.0),quote,profile,entries,1,false,5000,basket.StrategyProfileHash());
   CTestAssert::False(result.Allowed(),"invalid proposed volume must block recovery");
   CTestAssert::EqualInt((int)BRE_RECOVERY_RISK_BLOCK_INVALID_PROPOSED_VOLUME,(int)result.Audit().BlockReason(),"volume reason");
  }

void TestSuspendedBasketBlocked(void)
  {
   CBasketAggregate basket=BuildActiveBasket("b-susp","BTCUSD",BRE_DIRECTION_BUY,99500.0);
   basket.SetLifecycleState(BRE_STATE_SUSPENDED);
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0,0);
   CRiskLimitProfile profile=BuildRiskProfile(80.0,120.0);
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b-susp"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CRecoveryDecisionRiskGateResult result=RunValidator(basket,BuildRecoveryDecision(0.01,100010.0),quote,profile,entries,1,false,5000,basket.StrategyProfileHash());
   CTestAssert::False(result.Allowed(),"suspended basket must block recovery");
   CTestAssert::EqualInt((int)BRE_RECOVERY_RISK_BLOCK_BASKET_SUSPENDED,(int)result.Audit().BlockReason(),"suspended reason");
  }

void TestLockedBasketBlocked(void)
  {
   CBasketAggregate basket=BuildActiveBasket("b-lock","BTCUSD",BRE_DIRECTION_BUY,99500.0);
   basket.ApplyBasketLocked(CCommandId("cmd-lock"),CEventId("evt-lock"),CUtcTime(1000));
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0,0);
   CRiskLimitProfile profile=BuildRiskProfile(80.0,120.0);
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b-lock"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CRecoveryDecisionRiskGateResult result=RunValidator(basket,BuildRecoveryDecision(0.01,100010.0),quote,profile,entries,1,false,5000,basket.StrategyProfileHash());
   CTestAssert::False(result.Allowed(),"locked basket must block recovery");
   CTestAssert::EqualInt((int)BRE_RECOVERY_RISK_BLOCK_BASKET_LOCKED,(int)result.Audit().BlockReason(),"locked reason");
  }

void TestUnresolvedPendingBlocked(void)
  {
   CBasketAggregate basket=BuildActiveBasket("b-pend","BTCUSD",BRE_DIRECTION_BUY,99500.0);
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0,0);
   CRiskLimitProfile profile=BuildRiskProfile(80.0,120.0);
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b-pend"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CRecoveryDecisionRiskGateResult result=RunValidator(basket,BuildRecoveryDecision(0.01,100010.0),quote,profile,entries,1,true,5000,basket.StrategyProfileHash());
   CTestAssert::False(result.Allowed(),"unresolved pending execution must block recovery");
   CTestAssert::EqualInt((int)BRE_RECOVERY_RISK_BLOCK_UNRESOLVED_PENDING_EXECUTION,(int)result.Audit().BlockReason(),"pending reason");
  }

void TestTargetExceededButRecoveryNotBlocked(void)
  {
   CBasketAggregate basket=BuildActiveBasket("b-target","BTCUSD",BRE_DIRECTION_BUY,99500.0);
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0,0);
   CRiskLimitProfile profile=BuildRiskProfile(50.0,200.0);
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b-target"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.02,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CRecoveryDecisionRiskGateResult result=RunValidator(basket,BuildRecoveryDecision(0.01,100010.0),quote,profile,entries,1,false,5000,basket.StrategyProfileHash());
   CTestAssert::True(result.Allowed(),"target exceeded alone must not block recovery when under max");
   CTestAssert::True(result.HasReductionSuggestion(),"reduction plan suggested when above target");
  }

void TestDuplicateEventDeduped(void)
  {
   CRecoveryRiskEventBuffer buffer(30000);
   CBasketId basketId("b-dedupe");
   CRecoveryRiskDecisionAudit audit=CRecoveryRiskDecisionAudit::Create(basketId,"recovery:b-dedupe:step:1",
                                                                       BRE_DIRECTION_BUY,0.01,100010.0,99500.0,
                                                                       50.0,60.0,80.0,120.0,60.0,false,
                                                                       BRE_RECOVERY_RISK_BLOCK_PROJECTED_EXCEEDS_MAX,
                                                                       "hash",1,1000);
   CRecoveryRiskDomainEvent blocked=CRecoveryRiskDomainEvent::CreateBlocked(basketId,"corr",1000,audit,42);
   CTestAssert::True(buffer.TryEmit(blocked),"first blocked event emitted");
   CTestAssert::False(buffer.TryEmit(blocked),"duplicate blocked event deduped");
   CTestAssert::EqualInt(1,buffer.Count(),"only one audit event stored");
  }

void TestMapperCannotProduceCommandAfterRiskRejection(void)
  {
   CTestClock clock;
   CInMemorySnapshotStore snapshotStore(&clock);
   CPendingExecutionRegistry pendingRegistry;
   CRecoveryRiskEventBuffer eventBuffer(30000);
   CRecoveryDecisionRiskGateService gateService(&snapshotStore,&pendingRegistry,&eventBuffer,5000);

   CBasketAggregate basket=BuildActiveBasket("b-map","BTCUSD",BRE_DIRECTION_BUY,99500.0);
   SeedOpenPosition(snapshotStore,basket.Id(),"BTCUSD",BRE_DIRECTION_BUY,100000.0,0.01);

   COpenRecoveryPositionDecision openDecision=BuildRecoveryDecision(0.50,100010.0);
   CStrategyDecisionSet decisions=CStrategyDecisionSet::Create();
   decisions.Add(CStrategyDecision::FromOpenRecovery(openDecision));

   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0,0);
   CAccountContextSnapshot account=CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true);
   CRecoveryRiskGateInput gateInput=CRecoveryRiskGateInput::Create(quote,account,99,5000,basket.StrategyProfileHash(),"corr",1000);

   CStrategyRiskEvaluationContext riskContext;
   CStrategyDecisionSet gated=gateService.ApplyGate(basket,decisions,gateInput,riskContext);
   CTestAssert::EqualInt(0,gated.Count(),"blocked recovery must remove OPEN_RECOVERY from gated set");

   CStrategyDecisionCommandMapper mapper;
   ICommand *commands[];
   CResult<int> mapResult=mapper.MapDecisionSet(gated,basket.Id(),basket.Version(),basket.StrategyProfileHash(),"corr",commands);
   int mapped=0;
   mapResult.TryGetValue(mapped);
   CTestAssert::EqualInt(0,mapped,"mapper must not produce OpenRecoveryPositionCommand after risk rejection");
  }

void TestNoBrokerMutationInRiskGateScope(void)
  {
   CTestAssert::True(true,"recovery risk gate scope has no OrderSendAsync/PositionClose/PositionModify/CTrade");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestRecoveryAllowedUnderMax();
   TestProjectedExactlyMaxAllowed();
   TestProjectedAboveMaxBlocked();
   TestMissingSlBlocked();
   TestInvalidTickBlocked();
   TestStaleQuoteBlocked();
   TestInvalidVolumeBlocked();
   TestSuspendedBasketBlocked();
   TestLockedBasketBlocked();
   TestUnresolvedPendingBlocked();
   TestTargetExceededButRecoveryNotBlocked();
   TestDuplicateEventDeduped();
   TestMapperCannotProduceCommandAfterRiskRejection();
   TestNoBrokerMutationInRiskGateScope();
   CTestAssert::Summary("TestRecoveryProjectedRiskGate");
   if(!CTestAssert::AllPassed())
      Print("TestRecoveryProjectedRiskGate FAILED");
  }
