#property script_show_inputs
#property description "Sprint 7D: register live DUE recovery candidate artifact from seeded basket."

#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5Clock.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5UniqueIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Market/Mt5MarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateRegistrationService.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateEventBuffer.mqh>
#include <BasketRecovery/Application/Execution/RecoveryStepExecutionTracker.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Application/Services/StrategyEvaluationContextFactory.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecisionSet.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/OpenRecoveryPositionDecision.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecision.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Application/Strategy/RecoveryCandidatePlanningService.mqh>
#include <BasketRecovery/Application/Strategy/RecoveryCandidateEventBuffer.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/RecoveryCandidateReason.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryStepStateBuilder.mqh>
#include <BasketRecovery/Domain/Strategy/Context/RecoveryPlanEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/Validation/StrategyProfileValidator.mqh>
#include <BasketRecovery/Domain/Strategy/Context/RiskRuntimeContext.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryCandidatePlanner.mqh>
#include <BasketRecovery/Domain/Strategy/Context/StrategyRiskEvaluationContext.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Domain/Risk/Services/RecoveryDecisionRiskValidator.mqh>
#include <BasketRecovery/Application/Risk/RecoveryProposedTradeRequestBuilder.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

input string InpBasketId = "sprint7d-demo-btc-001";
input int    InpManualRecoveryCandidateExpirySeconds = 60;

void WriteLine(const int handle,const string line)
  {
   if(handle!=INVALID_HANDLE)
      FileWriteString(handle,line+"\r\n");
   Print(line);
  }

void OnStart(void)
  {
   string reportRel="BasketRecovery/validation/sprint-7d-register-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      return;

   CMt5Clock *clock=new CMt5Clock();
   CMt5UniqueIdGenerator *idGenerator=new CMt5UniqueIdGenerator();
   CFileBasketRepository *repository=new CFileBasketRepository(BRE_PERSISTENCE_BASKET_SUBDIR);
   CMt5MarketDataProvider *marketData=new CMt5MarketDataProvider(clock);
   CInMemorySnapshotStore *snapshotStore=new CInMemorySnapshotStore(clock);
   CPendingExecutionRegistry *pendingRegistry=new CPendingExecutionRegistry();
   CRecoveryStepExecutionTracker *stepTracker=new CRecoveryStepExecutionTracker();
   CManualRecoveryCandidateRegistry *registry=new CManualRecoveryCandidateRegistry();
   CManualRecoveryCandidateEventBuffer *eventBuffer=new CManualRecoveryCandidateEventBuffer();
   CManualRecoveryCandidateRegistrationService *registrationService=
      new CManualRecoveryCandidateRegistrationService(registry,eventBuffer,snapshotStore,pendingRegistry,
                                                    stepTracker,clock,idGenerator,
                                                    InpManualRecoveryCandidateExpirySeconds,5000);

   CResult<CBasketAggregate> basketResult=repository.Load(CBasketId(InpBasketId));
   if(basketResult.IsFail())
     {
      WriteLine(reportHandle,"register_verification=FAIL");
      WriteLine(reportHandle,"failure_reason="+basketResult.ErrorMessage());
      FileClose(reportHandle);
      delete registrationService; delete eventBuffer; delete registry; delete stepTracker;
      delete pendingRegistry; delete snapshotStore; delete marketData;
      delete repository; delete idGenerator; delete clock;
      return;
     }

   CBasketAggregate basket;
   basketResult.TryGetValue(basket);

   CResult<CMarketQuote> quoteResult=marketData.TryGetQuote(basket.Symbol());
   if(quoteResult.IsFail())
     {
      WriteLine(reportHandle,"register_verification=FAIL");
      WriteLine(reportHandle,"failure_reason="+quoteResult.ErrorMessage());
      FileClose(reportHandle);
      delete registrationService; delete eventBuffer; delete registry; delete stepTracker;
      delete pendingRegistry; delete snapshotStore; delete marketData;
      delete repository; delete idGenerator; delete clock;
      return;
     }

   CMarketQuote quote;
   quoteResult.TryGetValue(quote);

   double point=quote.Point();
   if(point<=0.0)
      point=0.01;
   double pipSize=quote.TickSize()>0.0 ? quote.TickSize() : point;
   double bid=quote.Bid();
   double ask=quote.Ask();
   CSignalDetails tuned;
   tuned.SetHasDetails(true);
   tuned.SetRangeLow(CPrice(ask-point*500.0));
   tuned.SetRangeHigh(CPrice(ask+pipSize*100.0));
   tuned.SetStopLoss(CPrice(ask-point*200.0));
   tuned.SetTp1(CPrice(ask+pipSize*100.0));
   basket.ApplySignalDetails(tuned,CCommandId("cmd-register-retune"),CEventId("evt-register-retune"),CUtcTime(clock.Now()));
   basket.SetRecoveryActive(true);
   repository.Save(basket);
   repository.Load(basket.Id()).TryGetValue(basket);

   CResult<CAccountContextSnapshot> accountResult=marketData.TryGetAccountSnapshot();
   CAccountContextSnapshot account;
   if(accountResult.IsOk())
      accountResult.TryGetValue(account);

   for(int accountAttempt=0;accountAttempt<30 && account.Equity()<=0.0;accountAttempt++)
     {
      Sleep(500);
      accountResult=marketData.TryGetAccountSnapshot();
      if(accountResult.IsOk())
         accountResult.TryGetValue(account);
     }

   datetime nowUtc=clock.Now();
   WriteLine(reportHandle,"account_equity="+DoubleToString(account.Equity(),2));
   if(account.Equity()<=0.0)
     {
      WriteLine(reportHandle,"register_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Account equity unavailable");
      FileClose(reportHandle);
      delete registrationService; delete eventBuffer; delete registry; delete stepTracker;
      delete pendingRegistry; delete snapshotStore; delete marketData;
      delete repository; delete idGenerator; delete clock;
      return;
     }

   CRecoveryRiskGateInput gateInput=CRecoveryRiskGateInput::Create(quote,account,0,5000,
                                                                   basket.StrategyProfileHash(),
                                                                   basket.CorrelationKey(),
                                                                   nowUtc);

   CMarketContext market=CMarketContext::Create(basket.Symbol(),quote.Bid(),quote.Ask(),pipSize);
   CRiskRuntimeContext riskContext=CRiskRuntimeContext::Create(0.0,1.0,1.2,0.0,true,false);
   CResult<CStrategyEvaluationContext> evalResult=CStrategyEvaluationContextFactory::TryBuild(basket,market,
                                                                                            riskContext,
                                                                                            snapshotStore);
   if(evalResult.IsFail())
     {
      WriteLine(reportHandle,"register_verification=FAIL");
      WriteLine(reportHandle,"failure_reason="+evalResult.ErrorMessage());
      FileClose(reportHandle);
      delete registrationService; delete eventBuffer; delete registry; delete stepTracker;
      delete pendingRegistry; delete snapshotStore; delete marketData;
      delete repository; delete idGenerator; delete clock;
      return;
     }

   CStrategyEvaluationContext evalContext;
   evalResult.TryGetValue(evalContext);

   string candidateKey="recovery-candidate:"+InpBasketId+":step:1:q:"+IntegerToString((long)gateInput.QuoteSequence());
   COpenRecoveryPositionDecision openDecision=COpenRecoveryPositionDecision::Create(candidateKey,1,0.0,
                                                                                  quote.Constraints().VolumeMin(),
                                                                                  quote.Ask(),
                                                                                  BRE_TRADE_ROLE_RECOVERY);
   CStrategyDecisionSet decisions;
   decisions.Add(CStrategyDecision::FromOpenRecovery(openDecision));

   CStrategyRiskEvaluationContext riskEvalContext;
   CRecoveryCandidateEventBuffer *planEventBuffer=new CRecoveryCandidateEventBuffer();
   CRecoveryCandidatePlanningService *planningService=
      new CRecoveryCandidatePlanningService(snapshotStore,pendingRegistry,planEventBuffer,5000);
   CStrategyDecisionSet planned=planningService.ApplyPlanning(basket,decisions,evalContext,gateInput,riskEvalContext);
   WriteLine(reportHandle,"planned_open_recovery_count="+IntegerToString(planned.Count()));

   CRecoveryCandidatePlanner debugPlanner;
   CRecoveryPlanEvaluationContext debugContext;
   {
      CStrategyProfile profile=evalContext.Profile();
      CStrategyProfileValidator validator;
      bool profileValid=validator.Validate(profile).IsOk();
      CPositionSnapshotEntry entries[];
      CRecoveryStepState stepState=CRecoveryStepStateBuilder::BuildFromEntries(basket.Direction(),
                                                                              evalContext.BasketState().SignalRangeLow(),
                                                                              evalContext.BasketState().SignalRangeHigh(),
                                                                              entries,0);
      debugContext=CRecoveryPlanEvaluationContext::Create(basket.Id(),basket.Version(),basket.StrategyProfileHash(),
                                                          basket.Symbol(),basket.Direction(),basket.LifecycleState(),
                                                          basket.ModeFlags().RecoveryActive(),
                                                          basket.RecoveryPermanentlyDisabled(),
                                                          basket.ModeFlags().Locked(),
                                                          basket.SignalDetails().StopLoss().Value(),
                                                          profile,evalContext.Market(),evalContext.BasketState(),
                                                          stepState,quote.Constraints(),gateInput.QuoteSequence(),
                                                          quote.FreshnessAgeMs(),5000,false,profileValid,
                                                          quote.SessionStatus()==BRE_TRADING_SESSION_OPEN,nowUtc);
   }
   CRecoveryCandidate debugCandidate=debugPlanner.Plan(debugContext,false);
   WriteLine(reportHandle,"planner_status="+IntegerToString((int)debugCandidate.Status()));
   WriteLine(reportHandle,"planner_reason="+IntegerToString((int)debugCandidate.Audit().Reason()));
   WriteLine(reportHandle,"recovery_active="+(basket.ModeFlags().RecoveryActive()?"true":"false"));
   WriteLine(reportHandle,"quote_bid="+DoubleToString(quote.Bid(),8));
   WriteLine(reportHandle,"quote_ask="+DoubleToString(quote.Ask(),8));
   WriteLine(reportHandle,"pip_size="+DoubleToString(pipSize,8));
   WriteLine(reportHandle,"quote_tick_size="+DoubleToString(quote.TickSize(),8));
   WriteLine(reportHandle,"quote_tick_value="+DoubleToString(quote.TickValue(),8));
   WriteLine(reportHandle,"signal_range_low="+DoubleToString(basket.SignalDetails().RangeLow().Value(),8));
   WriteLine(reportHandle,"signal_range_high="+DoubleToString(basket.SignalDetails().RangeHigh().Value(),8));

   if(debugCandidate.IsDue())
     {
      CTradeExecutionRequest riskRequest=CRecoveryProposedTradeRequestBuilder::Build(basket,openDecision,
                                                                                     gateInput.CorrelationKey(),
                                                                                     nowUtc);
      CPositionSnapshotEntry riskEntries[];
      CStrategyProfile profile=evalContext.Profile();
      CRiskLimitProfile riskProfile=CRiskLimitProfile::FromRiskPlan(profile.StrategyId(),profile.RiskPlan());
      CRiskCalculationContext calcContext=CRiskCalculationContext::Create(gateInput.Account(),
                                                                          gateInput.Quote(),
                                                                          riskProfile,
                                                                          basket.SignalDetails().StopLoss().Value(),
                                                                          basket.Direction(),
                                                                          CRiskCalculationSettings::CreateDefault());
      CRecoveryDecisionRiskGateResult gateResult=CRecoveryDecisionRiskValidator::Validate(basket,
                                                                                          openDecision,
                                                                                          riskRequest,
                                                                                          riskEntries,
                                                                                          0,
                                                                                          calcContext,
                                                                                          riskEvalContext,
                                                                                          5000,
                                                                                          gateInput.ExpectedStrategyProfileHash(),
                                                                                          nowUtc);
      WriteLine(reportHandle,"projected_max_risk_allowed="+(gateResult.Allowed()?"true":"false"));
      WriteLine(reportHandle,"risk_block_reason="+IntegerToString((int)gateResult.Audit().BlockReason()));
      WriteLine(reportHandle,"projected_sl_risk="+DoubleToString(gateResult.Audit().ProjectedSlRisk(),4));
      WriteLine(reportHandle,"max_risk="+DoubleToString(gateResult.Audit().MaxRisk(),4));
     }

   int registered=registrationService.TryRegisterFromGatedDecisions(basket,decisions,evalContext,gateInput,riskEvalContext);

   WriteLine(reportHandle,"basket_id="+InpBasketId);
   WriteLine(reportHandle,"registered_count="+IntegerToString(registered));
   WriteLine(reportHandle,"registry_available="+IntegerToString(registry.CountAvailable()));
   WriteLine(reportHandle,"register_verification="+(registered>0 ? "OK" : "FAIL"));
   if(registered<=0)
      WriteLine(reportHandle,"failure_reason=No DUE recovery candidate registered");

   FileClose(reportHandle);
   delete planningService; delete planEventBuffer;
   delete registrationService; delete eventBuffer; delete registry; delete stepTracker;
   delete pendingRegistry; delete snapshotStore; delete marketData;
   delete repository; delete idGenerator; delete clock;
  }
