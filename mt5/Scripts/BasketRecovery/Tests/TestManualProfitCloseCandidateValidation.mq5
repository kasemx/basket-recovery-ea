#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/Market/InMemoryMarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionAuthorizationStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryAccountExecutionEligibilityProvider.mqh>
#include <BasketRecovery/Infrastructure/MT5/InMemoryAccountPositionModelProvider.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/MockMt5AsyncOrderSendTransport.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateTriggerRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateEventBuffer.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateRegistrationService.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateSubmissionValidationService.mqh>
#include <BasketRecovery/Application/Execution/ProfitCloseCandidateSubmissionValidator.mqh>
#include <BasketRecovery/Application/Execution/ProfitLevelCloseExecutionTracker.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionTriggerRegistry.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationRegistry.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationPolicy.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Application/Execution/SubmitPreparedExecutionUseCase.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>
#include <BasketRecovery/Domain/Execution/ProfitCloseCandidateExecutionRequestFactory.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Domain/Market/Enums/AccountPositionModel.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ProfitLevelCloseCandidatePlanner.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevel.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitDistributionPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ExecutionZone.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryStep.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RiskPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevelCloseCandidate.mqh>
#include <BasketRecovery/Domain/Strategy/Context/ProfitLevelEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/PositionRuntimeView.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>

#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Shared/Types/Price.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

const long TEST_MAGIC=202606004;
const string TEST_BASKET_ID_VALUE="basket-pc-001";
const string PROFIT_LEVEL_ID="M1";
const ulong TEST_POSITION_TICKET=501;
const ulong QUOTE_SEQUENCE=42;

class CManualProfitCloseTestHarness
  {
private:
   CSubmissionPreparationValidator *m_prepValidator;

   CStrategyProfile  BuildMoneyTriggerProfile(void) const
     {
      CProfitLevel levels[1];
      levels[0]=CProfitLevel::Create(PROFIT_LEVEL_ID,1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,10.0,true,20.0,
                                     BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                     BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,10.0,true);
      CProfitDistributionPlan profitPlan=CProfitDistributionPlan::Create(true,BRE_CLOSE_MODE_WORST_ENTRY_FIRST,levels,1);
      CRecoveryStep steps[1];
      steps[0]=CRecoveryStep::Create(1,0.2,0.01);
      CRecoveryPlan recovery=CRecoveryPlan::CreateCustom(steps,1,true,true,3,0.01);
      CBreakEvenRule beRules[];
      ArrayResize(beRules,0);
      CBreakEvenPlan breakEven=CBreakEvenPlan::Create(beRules,0);
      CRiskPlan risk=CRiskPlan::Create(1.0,1.2,0.95,true,BRE_RISK_REDUCTION_MODE_WORST_ENTRY,0.0,false,30,100);
      CExecutionZone zone=CExecutionZone::CreateSignalRange(BRE_ZONE_EXPANSION_SYMMETRIC,3.0,3.0,false,0.0,false);
      CExecutionProfileConfig executionPolicy;
      executionPolicy.SetMagicNumberBase(TEST_MAGIC);
      return CStrategyProfile::Create("profit-close-validation",BRE_STRATEGY_SCHEMA_VERSION,
                                      CStrategyMetadata::Create("Profit Close Validation","",""),
                                      zone,recovery,profitPlan,breakEven,risk,executionPolicy,CUtcTime(1000));
     }

public:
   CTestClock                                   *clock;
   CInMemorySnapshotStore                       *snapshotStore;
   CPendingExecutionRegistry                    *pendingRegistry;
   CInMemoryPendingExecutionStore               *pendingStore;
   CInMemoryExecutionAuthorizationStore         *authStore;
   CExecutionAuthorizationRegistry              *authRegistry;
   CDemoManualSubmissionTriggerRegistry       *demoTriggerRegistry;
   CInMemoryAccountExecutionEligibilityProvider *eligibility;
   CInMemoryAccountPositionModelProvider        *positionModel;
   CInMemoryBasketRepository                    *basketRepository;
   CManualProfitCloseCandidateRegistry          *candidateRegistry;
   CManualProfitCloseCandidateTriggerRegistry   *profitCloseTriggers;
   CManualProfitCloseCandidateEventBuffer       *events;
   CProfitLevelCloseExecutionTracker            *levelTracker;
   CProfitCloseCandidateSubmissionValidator     *validator;
   CInMemoryMarketDataProvider                  *marketData;
   CExecutionSubmissionPreparer                 *preparer;
   CMockMt5AsyncOrderSendTransport              *mockTransport;
   CMt5AsyncSubmissionGateway                   *asyncGateway;
   CSubmitPreparedExecutionUseCase              *submitUseCase;
   CDemoExecutionAuthorizationConfig            config;
   CDemoManualSubmissionService                 *demoService;
   CManualProfitCloseSubmissionService          *profitCloseService;
   CManualProfitCloseCandidateSubmissionValidationService *validationService;

                     CManualProfitCloseTestHarness(void)
     {
      m_prepValidator=NULL;
      clock=new CTestClock();
      clock.SetNow(1000);
      snapshotStore=new CInMemorySnapshotStore(clock);
      pendingRegistry=new CPendingExecutionRegistry();
      pendingStore=new CInMemoryPendingExecutionStore();
      authStore=new CInMemoryExecutionAuthorizationStore();
      authRegistry=new CExecutionAuthorizationRegistry(authStore);
      demoTriggerRegistry=new CDemoManualSubmissionTriggerRegistry();
      eligibility=new CInMemoryAccountExecutionEligibilityProvider();
      positionModel=new CInMemoryAccountPositionModelProvider(BRE_ACCOUNT_POSITION_MODEL_HEDGING);
      basketRepository=new CInMemoryBasketRepository();
      candidateRegistry=new CManualProfitCloseCandidateRegistry();
      profitCloseTriggers=new CManualProfitCloseCandidateTriggerRegistry();
      events=new CManualProfitCloseCandidateEventBuffer();
      levelTracker=new CProfitLevelCloseExecutionTracker();
      validator=new CProfitCloseCandidateSubmissionValidator(snapshotStore,pendingRegistry,levelTracker,eligibility,5000);
      marketData=new CInMemoryMarketDataProvider();
      marketData.SetQuote(BuildQuote(10));
      marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
      m_prepValidator=new CSubmissionPreparationValidator(marketData,CMarketSafetyConfig());
      preparer=new CExecutionSubmissionPreparer(CSubmissionPreparationPolicy::Default(),
                                                *m_prepValidator,pendingRegistry,pendingStore,clock);
      preparer.ConfigureRiskReadModel(snapshotStore,marketData);
      mockTransport=new CMockMt5AsyncOrderSendTransport();
      asyncGateway=new CMt5AsyncSubmissionGateway(mockTransport,NULL,10);
      submitUseCase=new CSubmitPreparedExecutionUseCase(pendingRegistry,asyncGateway,pendingStore,clock,NULL);
      config=EnabledManualConfig();
      demoService=new CDemoManualSubmissionService(config,authRegistry,demoTriggerRegistry,pendingRegistry,pendingStore,
                                                   eligibility,clock,submitUseCase,asyncGateway,CMarketSafetyConfig());
      profitCloseService=new CManualProfitCloseSubmissionService(config,candidateRegistry,profitCloseTriggers,events,
                                                                 validator,levelTracker,authRegistry,preparer,
                                                                 demoService,basketRepository,clock,NULL);
      validationService=new CManualProfitCloseCandidateSubmissionValidationService();
      validationService.Configure(config,profitCloseService,basketRepository,marketData,5000);
      SetDemoEligibility(true,true,true);
     }

                    ~CManualProfitCloseTestHarness(void)
     {
      if(validationService!=NULL) delete validationService;
      if(profitCloseService!=NULL) delete profitCloseService;
      if(demoService!=NULL) delete demoService;
      if(submitUseCase!=NULL) delete submitUseCase;
      if(asyncGateway!=NULL) delete asyncGateway;
      if(mockTransport!=NULL) delete mockTransport;
      if(preparer!=NULL) delete preparer;
      if(m_prepValidator!=NULL) delete m_prepValidator;
      if(marketData!=NULL) delete marketData;
      if(validator!=NULL) delete validator;
      if(levelTracker!=NULL) delete levelTracker;
      if(events!=NULL) delete events;
      if(profitCloseTriggers!=NULL) delete profitCloseTriggers;
      if(candidateRegistry!=NULL) delete candidateRegistry;
      if(basketRepository!=NULL) delete basketRepository;
      if(positionModel!=NULL) delete positionModel;
      if(eligibility!=NULL) delete eligibility;
      if(demoTriggerRegistry!=NULL) delete demoTriggerRegistry;
      if(authRegistry!=NULL) delete authRegistry;
      if(authStore!=NULL) delete authStore;
      if(pendingStore!=NULL) delete pendingStore;
      if(pendingRegistry!=NULL) delete pendingRegistry;
      if(snapshotStore!=NULL) delete snapshotStore;
      if(clock!=NULL) delete clock;
     }

   static CDemoExecutionAuthorizationConfig EnabledManualConfig(void)
     {
      CDemoExecutionAuthorizationConfig cfg;
      cfg.SetExecutionRuntimeMode(BRE_EXEC_RUNTIME_DEMO_MANUAL_SUBMISSION);
      cfg.SetEnableLiveDemoExecution(true);
      cfg.SetRequireManualDemoAuthorization(true);
      cfg.SetMaxAuthorizedRequestsPerSession(5);
      cfg.SetMaxProfitCloseSubmissionsPerSession(5);
      cfg.SetMaxManualDemoOpenVolume(1.0);
      cfg.SetManualProfitCloseCandidateExpirySeconds(30);
      cfg.SetAuthorizationTokenExpirySeconds(300);
      return cfg;
     }

   static CMarketQuote BuildQuote(const int freshnessAgeMs)
     {
      return CMarketQuote::Create("EURUSD",1.0990,1.1000,10,0.01,2,0.01,1.0,1000,freshnessAgeMs,
                                  BRE_TRADING_SESSION_OPEN,
                                  CSymbolTradingConstraints::Create(20,10,0.01,1.0,0.01));
     }

   void              SetDemoEligibility(const bool demo,const bool terminalAllowed,const bool chartAllowed)
     {
      CAccountExecutionEligibilitySnapshot snapshot;
      snapshot.SetClassification(demo ? BRE_ACCOUNT_ELIGIBILITY_DEMO : BRE_ACCOUNT_ELIGIBILITY_REAL);
      snapshot.SetAccountTradeAllowed(true);
      snapshot.SetTerminalTradeAllowed(terminalAllowed);
      snapshot.SetChartExpertTradeAllowed(chartAllowed);
      eligibility.SetSnapshot(snapshot);
     }

   CBasketAggregate  BuildActiveBasket(void)
     {
      CStrategyProfile profile=BuildMoneyTriggerProfile();
      string json="{\"strategy_id\":\"profit-close-validation\"}";
      CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,json,CUtcTime(1000));
      CExecutionProfileConfig execution;
      execution.SetMagicNumberBase(TEST_MAGIC);
      CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                     CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                     execution,CUtcTime(1000));
      CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId(TEST_BASKET_ID_VALUE),legacy,snapshot,
                                                                           "corr-pc",BRE_DIRECTION_BUY,"EURUSD",
                                                                           CSignalId("sig-pc"),CUtcTime(1000),
                                                                           CCommandId("cmd-create"),CEventId("evt-create"));
      CBasketAggregate basket;
      created.TryGetValue(basket);
      basket.SetLifecycleState(BRE_STATE_ACTIVE);
      basketRepository.Save(basket);
      return basket;
     }

   void              SeedOpenPosition(const CBasketId &basketId,
                                      const ulong ticket,
                                      const double volume,
                                      const double floatingProfit)
     {
      CPositionSnapshotEntry entries[1];
      entries[0]=CPositionSnapshotEntry::Create(basketId,ticket,TEST_MAGIC,"EURUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                                1.0950,1.1000,1.0950,0.0,volume,floatingProfit,0.0,0.0,1000,
                                                BRE_POSITION_SNAPSHOT_OPEN,"");
      snapshotStore.ReplaceEntries(basketId,entries,1);
     }

   bool              PlanDueReduction(const CBasketAggregate &basket,
                                      CPositionReductionInstruction &outInstruction,
                                      double &outEstimatedMoney) const
     {
      CPositionRuntimeView positions[1];
      positions[0]=CPositionRuntimeView::Create(TEST_POSITION_TICKET,1.0950,0.10,100.0,100.0,1000,BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL);
      CBasketProfitLevelProgress progress[];
      ArrayResize(progress,0);
      CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(20,10,0.01,1.0,0.01);
      CStrategyProfile profile;
      basket.StrategyProfile(profile);
      CMarketContext market=CMarketContext::Create("EURUSD",1.0990,1.1000,0.01);
      CProfitLevelEvaluationContext ctx=CProfitLevelEvaluationContext::Create(basket.Id(),basket.Version(),
                                                                              basket.StrategyProfileHash(),"EURUSD",
                                                                              BRE_DIRECTION_BUY,BRE_STATE_ACTIVE,false,
                                                                              profile,market,positions,1,progress,0,
                                                                              100.0,10000.0,100.0,constraints,
                                                                              QUOTE_SEQUENCE,10,5000,false,true,true,1000);
      CProfitLevelCloseCandidatePlanner planner;
      CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
      if(!candidate.IsDue() || candidate.Audit().ReductionCount()!=1)
         return false;
      if(!candidate.Audit().ReductionAt(0,outInstruction))
         return false;
      outEstimatedMoney=outInstruction.EstimatedCloseMoney();
      return true;
     }

   CManualProfitCloseCandidateEntry BuildSampleEntry(const string candidateId,
                                                     const datetime createdAt,
                                                     const datetime expiresAt,
                                                     const double closeVolume=0.02) const
     {
      return CManualProfitCloseCandidateEntry::Create(candidateId,
                                                        "profit-close-manual:req-001",
                                                        candidateId,
                                                        CBasketId(TEST_BASKET_ID_VALUE),
                                                        PROFIT_LEVEL_ID,
                                                        1,
                                                        "hash-pc-v1",
                                                        1,
                                                        "EURUSD",
                                                        BRE_DIRECTION_BUY,
                                                        BRE_DIRECTION_BUY,
                                                        TEST_POSITION_TICKET,
                                                        0.10,
                                                        closeVolume,
                                                        20.0,
                                                        BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,
                                                        10.0,
                                                        QUOTE_SEQUENCE,
                                                        createdAt,
                                                        expiresAt,
                                                        BRE_ACCOUNT_POSITION_MODEL_HEDGING);
     }

   CProfitLevelCloseCandidate BuildDueCandidate(const int reductionCount) const
     {
      CPositionReductionInstruction reductions[2];
      reductions[0]=CPositionReductionInstruction::Create(TEST_POSITION_TICKET,0.02,20.0);
      reductions[1]=CPositionReductionInstruction::Create(TEST_POSITION_TICKET+1,0.01,10.0);
      CProfitLevelCloseAudit audit=CProfitLevelCloseAudit::Create(CBasketId(TEST_BASKET_ID_VALUE),
                                                                  "hash-pc-v1",
                                                                  1,
                                                                  PROFIT_LEVEL_ID,
                                                                  1,
                                                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,
                                                                  10.0,
                                                                  100.0,
                                                                  20.0,
                                                                  20.0,
                                                                  reductions,
                                                                  reductionCount,
                                                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,
                                                                  QUOTE_SEQUENCE,
                                                                  "profit-close:"+TEST_BASKET_ID_VALUE+":level:"+PROFIT_LEVEL_ID,
                                                                  1000,
                                                                  BRE_PROFIT_LEVEL_CLOSE_DUE,
                                                                  BRE_PROFIT_LEVEL_CLOSE_REASON_NONE,
                                                                  BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED,
                                                                  false);
      return CProfitLevelCloseCandidate::FromAudit(audit);
     }

   bool              RegisterValidCandidate(CManualProfitCloseCandidateEntry &entry)
     {
      CBasketAggregate basket=BuildActiveBasket();
      SeedOpenPosition(basket.Id(),TEST_POSITION_TICKET,0.10,100.0);
      CPositionReductionInstruction instruction;
      double estimatedMoney=0.0;
      if(!PlanDueReduction(basket,instruction,estimatedMoney))
         return false;
      entry=BuildSampleEntry("profit-close-candidate:"+TEST_BASKET_ID_VALUE+":"+PROFIT_LEVEL_ID,1000,1030,
                             instruction.ProposedCloseVolume());
      entry=CManualProfitCloseCandidateEntry::Create(entry.CandidateId(),
                                                     entry.ExecutionRequestId(),
                                                     entry.IdempotencyKey(),
                                                     entry.BasketId(),
                                                     entry.ProfitLevelId(),
                                                     entry.ProfitLevelIndex(),
                                                     basket.StrategyProfileHash(),
                                                     basket.Version(),
                                                     entry.Symbol(),
                                                     entry.BasketDirection(),
                                                     entry.PositionDirection(),
                                                     instruction.Ticket(),
                                                     0.10,
                                                     instruction.ProposedCloseVolume(),
                                                     estimatedMoney,
                                                     entry.TriggerType(),
                                                     entry.TriggerValue(),
                                                     QUOTE_SEQUENCE,
                                                     1000,
                                                     1030,
                                                     BRE_ACCOUNT_POSITION_MODEL_HEDGING);
      return candidateRegistry.TryRegister(entry);
     }

   string            IssueToken(const CPendingExecutionEntry &entry,const datetime expiryUtc) const
     {
      string fingerprint=CExecutionAuthorizationToken::ComputeBindingFingerprint(entry.ExecutionRequestId(),
                                                                                 entry.BasketId(),
                                                                                 entry.Symbol(),
                                                                                 entry.IntentType(),
                                                                                 entry.RequestedVolume(),
                                                                                 entry.ExpectedBasketVersion(),
                                                                                 entry.StrategyProfileHash());
      return CExecutionAuthorizationToken::IssuePlaintextToken(fingerprint,expiryUtc);
     }

   bool              PrepareClosePending(const CManualProfitCloseCandidateEntry &entry,
                                         const CBasketAggregate &basket)
     {
      CTradeExecutionRequest request=CProfitCloseCandidateExecutionRequestFactory::CreateCloseRequest(entry,clock.Now());
      CSubmissionPreparationResult prep=preparer.Prepare(request,basket,TEST_MAGIC);
      return prep.IsSuccess();
     }

   CDemoManualSubmissionResult SubmitCandidate(const string candidateId,
                                               const string authorizationToken,
                                               const string triggerToken,
                                               const CMarketQuote &quote)
     {
      CResult<CBasketAggregate> loaded=basketRepository.Load(CBasketId(TEST_BASKET_ID_VALUE));
      CBasketAggregate basket;
      loaded.TryGetValue(basket);
      CRecoveryRiskGateInput gateInput=CRecoveryRiskGateInput::Create(quote,
                                                                      CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true),
                                                                      QUOTE_SEQUENCE,5000,basket.StrategyProfileHash(),
                                                                      candidateId,quote.TimestampUtc());
      return profitCloseService.TrySubmitProfitCloseCandidate(candidateId,authorizationToken,triggerToken,basket,quote,
                                                              gateInput,TEST_MAGIC);
     }

   void              Reset(void)
     {
      candidateRegistry.Clear();
      profitCloseTriggers.Clear();
      pendingRegistry.Clear();
      pendingStore.Clear();
      authRegistry.Clear();
      levelTracker.Clear();
      mockTransport.Reset();
      submitUseCase.ClearCache();
      clock.SetNow(1000);
      marketData.SetQuote(BuildQuote(10));
      SetDemoEligibility(true,true,true);
     }
  };

void TestRegistryAcceptsEligibleCandidate(void)
  {
   CManualProfitCloseTestHarness harness;
   CManualProfitCloseCandidateEntry entry;
   CTestAssert::True(harness.RegisterValidCandidate(entry),"DUE single-instruction candidate must enter registry");
   CManualProfitCloseCandidateEntry loaded;
   CTestAssert::True(harness.candidateRegistry.TryGetByCandidateId(entry.CandidateId(),loaded),
                     "Registered candidate must be retrievable");
  }

void TestMultiInstructionRejectedAtRegistration(void)
  {
   CManualProfitCloseTestHarness harness;
   CProfitCloseCandidateSubmissionValidator validator(NULL,NULL,NULL,NULL);
   CProfitLevelCloseCandidate multi=harness.BuildDueCandidate(2);
   CVoidResult result=validator.ValidateRegistrationEligible(multi,BRE_ACCOUNT_POSITION_MODEL_HEDGING);
   CTestAssert::True(result.IsFail(),"Multi-instruction candidate must be rejected at registration");
  }

void TestUnsupportedPositionModelRejectedAtRegistration(void)
  {
   CManualProfitCloseTestHarness harness;
   CProfitCloseCandidateSubmissionValidator validator(NULL,NULL,NULL,NULL);
   CProfitLevelCloseCandidate single=harness.BuildDueCandidate(1);
   CVoidResult netting=validator.ValidateRegistrationEligible(single,BRE_ACCOUNT_POSITION_MODEL_NETTING);
   CTestAssert::True(netting.IsFail(),"Netting account model must be rejected at registration");
   CVoidResult unknown=validator.ValidateRegistrationEligible(single,BRE_ACCOUNT_POSITION_MODEL_UNKNOWN);
   CTestAssert::True(unknown.IsFail(),"Unknown account model must be rejected at registration");
  }

void TestExpiredCandidateRejectedOnSubmission(void)
  {
   CManualProfitCloseTestHarness harness;
   harness.Reset();
   CManualProfitCloseCandidateEntry entry=harness.BuildSampleEntry("expired-candidate",1000,1005);
   harness.candidateRegistry.TryRegister(entry);
   CBasketAggregate basket=harness.BuildActiveBasket();
   harness.SeedOpenPosition(basket.Id(),TEST_POSITION_TICKET,0.10,100.0);
   CMarketQuote quote=CManualProfitCloseTestHarness::BuildQuote(10);
   CRecoveryRiskGateInput gateInput=CRecoveryRiskGateInput::Create(quote,
                                                                   CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true),
                                                                   QUOTE_SEQUENCE,5000,basket.StrategyProfileHash(),
                                                                   entry.CandidateId(),1005);
   CVoidResult result=harness.validator.ValidateForSubmission(entry,basket,quote,gateInput,1005);
   CTestAssert::True(result.IsFail(),"Expired candidate must fail submission validation");
  }

void TestStaleQuoteRejected(void)
  {
   CManualProfitCloseTestHarness harness;
   harness.Reset();
   CManualProfitCloseCandidateEntry entry;
   CTestAssert::True(harness.RegisterValidCandidate(entry),"candidate");
   CBasketAggregate basket=harness.BuildActiveBasket();
   harness.SeedOpenPosition(basket.Id(),TEST_POSITION_TICKET,0.10,100.0);
   CMarketQuote staleQuote=CManualProfitCloseTestHarness::BuildQuote(6000);
   CRecoveryRiskGateInput gateInput=CRecoveryRiskGateInput::Create(staleQuote,
                                                                   CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true),
                                                                   QUOTE_SEQUENCE,5000,basket.StrategyProfileHash(),
                                                                   entry.CandidateId(),1000);
   CVoidResult result=harness.validator.ValidateForSubmission(entry,basket,staleQuote,gateInput,1000);
   CTestAssert::True(result.IsFail(),"Stale quote must invalidate candidate");
  }

void TestSelectedPositionMissingRejected(void)
  {
   CManualProfitCloseTestHarness harness;
   harness.Reset();
   CManualProfitCloseCandidateEntry entry;
   CTestAssert::True(harness.RegisterValidCandidate(entry),"candidate");
   CBasketAggregate basket=harness.BuildActiveBasket();
   CMarketQuote quote=CManualProfitCloseTestHarness::BuildQuote(10);
   CRecoveryRiskGateInput gateInput=CRecoveryRiskGateInput::Create(quote,
                                                                   CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true),
                                                                   QUOTE_SEQUENCE,5000,basket.StrategyProfileHash(),
                                                                   entry.CandidateId(),1000);
   CVoidResult result=harness.validator.ValidateForSubmission(entry,basket,quote,gateInput,1000);
   CTestAssert::True(result.IsFail(),"Missing selected position must be rejected");
  }

void TestInsufficientPositionVolumeRejected(void)
  {
   CManualProfitCloseTestHarness harness;
   harness.Reset();
   CManualProfitCloseCandidateEntry entry;
   CTestAssert::True(harness.RegisterValidCandidate(entry),"candidate");
   CBasketAggregate basket=harness.BuildActiveBasket();
   harness.SeedOpenPosition(basket.Id(),TEST_POSITION_TICKET,0.01,100.0);
   entry=CManualProfitCloseCandidateEntry::Create(entry.CandidateId(),
                                                  entry.ExecutionRequestId(),
                                                  entry.IdempotencyKey(),
                                                  entry.BasketId(),
                                                  entry.ProfitLevelId(),
                                                  entry.ProfitLevelIndex(),
                                                  basket.StrategyProfileHash(),
                                                  basket.Version(),
                                                  entry.Symbol(),
                                                  entry.BasketDirection(),
                                                  entry.PositionDirection(),
                                                  entry.PositionTicket(),
                                                  0.01,
                                                  0.05,
                                                  entry.EstimatedCloseMoney(),
                                                  entry.TriggerType(),
                                                  entry.TriggerValue(),
                                                  entry.QuoteSequence(),
                                                  1000,
                                                  1030,
                                                  entry.AccountPositionModel());
   CMarketQuote quote=CManualProfitCloseTestHarness::BuildQuote(10);
   CRecoveryRiskGateInput gateInput=CRecoveryRiskGateInput::Create(quote,
                                                                   CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true),
                                                                   QUOTE_SEQUENCE,5000,basket.StrategyProfileHash(),
                                                                   entry.CandidateId(),1000);
   CVoidResult result=harness.validator.ValidateForSubmission(entry,basket,quote,gateInput,1000);
   CTestAssert::True(result.IsFail(),"Insufficient position volume must be rejected");
  }

void TestInvalidCloseVolumeRejected(void)
  {
   CManualProfitCloseTestHarness harness;
   harness.Reset();
   CManualProfitCloseCandidateEntry entry;
   CTestAssert::True(harness.RegisterValidCandidate(entry),"candidate");
   CBasketAggregate basket=harness.BuildActiveBasket();
   harness.SeedOpenPosition(basket.Id(),TEST_POSITION_TICKET,0.10,100.0);
   entry=CManualProfitCloseCandidateEntry::Create(entry.CandidateId(),
                                                  entry.ExecutionRequestId(),
                                                  entry.IdempotencyKey(),
                                                  entry.BasketId(),
                                                  entry.ProfitLevelId(),
                                                  entry.ProfitLevelIndex(),
                                                  basket.StrategyProfileHash(),
                                                  basket.Version(),
                                                  entry.Symbol(),
                                                  entry.BasketDirection(),
                                                  entry.PositionDirection(),
                                                  entry.PositionTicket(),
                                                  0.10,
                                                  0.015,
                                                  entry.EstimatedCloseMoney(),
                                                  entry.TriggerType(),
                                                  entry.TriggerValue(),
                                                  entry.QuoteSequence(),
                                                  1000,
                                                  1030,
                                                  entry.AccountPositionModel());
   CMarketQuote quote=CManualProfitCloseTestHarness::BuildQuote(10);
   CRecoveryRiskGateInput gateInput=CRecoveryRiskGateInput::Create(quote,
                                                                   CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true),
                                                                   QUOTE_SEQUENCE,5000,basket.StrategyProfileHash(),
                                                                   entry.CandidateId(),1000);
   CVoidResult result=harness.validator.ValidateForSubmission(entry,basket,quote,gateInput,1000);
   CTestAssert::True(result.IsFail(),"Invalid close volume step must be rejected");
  }

void TestFactoryBindsExactCandidateFields(void)
  {
   CManualProfitCloseTestHarness harness;
   CManualProfitCloseCandidateEntry entry=harness.BuildSampleEntry("bind-candidate",1000,1030,0.02);
   CTradeExecutionRequest request=CProfitCloseCandidateExecutionRequestFactory::CreateCloseRequest(entry,1000);
   CTestAssert::True(request.IsSealed(),"Factory request must be sealed");
   CTestAssert::EqualString("EURUSD",request.Symbol(),"Symbol must come from candidate");
   CTestAssert::True(request.Ticket()==TEST_POSITION_TICKET,"Ticket must come from candidate");
   CTestAssert::EqualInt((int)BRE_DIRECTION_SELL,(int)request.Direction(),"Close direction must oppose position");
   CTestAssert::EqualDouble(0.02,request.RequestedVolume(),0.0001,"Volume must come from candidate");
   CTestAssert::EqualInt((int)BRE_EXEC_INTENT_CLOSE_POSITION,(int)request.IntentType(),"Only CLOSE_POSITION allowed");
  }

void TestProfitCloseTriggerOneShot(void)
  {
   CManualProfitCloseCandidateTriggerRegistry triggers;
   CTestAssert::False(triggers.IsConsumed("pc-trigger-1"),"Fresh trigger must not be consumed");
   triggers.Consume("pc-trigger-1");
   CTestAssert::True(triggers.IsConsumed("pc-trigger-1"),"Trigger must be one-shot consumed");
  }

void TestLevelTrackerFillOnce(void)
  {
   CProfitLevelCloseExecutionTracker tracker;
   tracker.MarkSubmitted(TEST_BASKET_ID_VALUE,PROFIT_LEVEL_ID,"profit-close-manual:req-001");
   CTestAssert::False(tracker.IsLevelCompleted(TEST_BASKET_ID_VALUE,PROFIT_LEVEL_ID),"Submit must not complete level");
   CTestAssert::True(tracker.TryMarkFilled("profit-close-manual:req-001"),"First fill must advance");
   CTestAssert::True(tracker.IsLevelCompleted(TEST_BASKET_ID_VALUE,PROFIT_LEVEL_ID),"Fill must mark level completed");
   CTestAssert::False(tracker.TryMarkFilled("profit-close-manual:req-001"),"Duplicate fill must not advance twice");
  }

void TestNoAutomaticProfitCloseSubmissionWiring(void)
  {
   CManualProfitCloseCandidateSubmissionValidationService validationService;
   validationService.Configure(CManualProfitCloseTestHarness::EnabledManualConfig(),NULL,NULL,NULL,5000);
   CTestAssert::False(validationService.IsWiredToStrategyEngine(),"StrategyEngine must not auto-submit profit close");
   CTestAssert::False(validationService.IsWiredToRestIntake(),"REST must not auto-submit profit close");
   CTestAssert::False(validationService.IsWiredToOnTick(),"OnTick must not auto-submit profit close");
   CTestAssert::False(validationService.IsWiredToAutomaticTimer(),"Automatic timer must not auto-submit profit close");
   CTestAssert::False(validationService.IsWiredToOnTradeTransaction(),"OnTradeTransaction must not submit profit close");

   CManualProfitCloseTestHarness harness;
   CTestAssert::False(harness.profitCloseService.IsWiredToStrategyEngine(),"submission service isolated from strategy engine");
   CTestAssert::False(harness.profitCloseService.IsWiredToOnTick(),"submission service isolated from OnTick");
  }

void TestTerminalPendingNoLongerBlocks(void)
  {
   CManualProfitCloseTestHarness harness;
   harness.Reset();
   CManualProfitCloseCandidateEntry entry;
   CTestAssert::True(harness.RegisterValidCandidate(entry),"candidate");
   CBasketAggregate basket=harness.BuildActiveBasket();
   harness.SeedOpenPosition(basket.Id(),TEST_POSITION_TICKET,0.10,100.0);

   CPendingExecutionEntry pending;
   pending.SetExecutionRequestId("pending-terminal");
   pending.SetBasketId(CBasketId(TEST_BASKET_ID_VALUE));
   pending.SetStatus(BRE_TRADE_EXEC_STATUS_REJECTED);
   harness.pendingRegistry.Upsert(pending);

   CMarketQuote quote=CManualProfitCloseTestHarness::BuildQuote(10);
   CRecoveryRiskGateInput gateInput=CRecoveryRiskGateInput::Create(quote,
                                                                   CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true),
                                                                   QUOTE_SEQUENCE,5000,basket.StrategyProfileHash(),
                                                                   entry.CandidateId(),1000);
   CVoidResult result=harness.validator.ValidateForSubmission(entry,basket,quote,gateInput,1000);
   CTestAssert::True(result.IsOk(),"Terminal pending execution must not block profit close validation");
  }

void TestPreBrokerValidationDoesNotConsumeTrigger(void)
  {
   CManualProfitCloseTestHarness harness;
   harness.Reset();
   CManualProfitCloseCandidateEntry entry;
   CTestAssert::True(harness.RegisterValidCandidate(entry),"candidate");
   CMarketQuote staleQuote=CManualProfitCloseTestHarness::BuildQuote(6000);
   CDemoManualSubmissionResult result=harness.SubmitCandidate(entry.CandidateId(),"token","trigger-prebroker",staleQuote);
   CTestAssert::False(result.IsSuccess(),"Pre-broker validation must reject stale quote");
   CTestAssert::False(result.TriggerTokenConsumed(),"Trigger must not be consumed before broker call");
   CTestAssert::False(harness.profitCloseTriggers.IsConsumed("trigger-prebroker"),"Profit close trigger registry must retain token");
   CTestAssert::EqualInt(0,harness.mockTransport.CallCount(),"No OrderSendAsync without passing validation");
  }

void TestBrokerSubmissionConsumesTrigger(CManualProfitCloseTestHarness &harness)
  {
   harness.Reset();
   harness.mockTransport.SetNextAccepted(true,TRADE_RETCODE_PLACED,0,920001);
   CManualProfitCloseCandidateEntry entry;
   CTestAssert::True(harness.RegisterValidCandidate(entry),"candidate");
   CBasketAggregate basket=harness.BuildActiveBasket();
   harness.SeedOpenPosition(basket.Id(),TEST_POSITION_TICKET,0.10,100.0);
   CTestAssert::True(harness.PrepareClosePending(entry,basket),"prepare close pending");
   CPendingExecutionEntry pending;
   CTestAssert::True(harness.pendingRegistry.TryGetByExecutionRequestId(entry.ExecutionRequestId(),pending),"pending entry");
   string token=harness.IssueToken(pending,harness.clock.Now()+300);
   CMarketQuote quote=CManualProfitCloseTestHarness::BuildQuote(10);
   CDemoManualSubmissionResult result=harness.SubmitCandidate(entry.CandidateId(),token,"trigger-broker",quote);
   CTestAssert::True(result.TriggerTokenConsumed(),"Trigger must be consumed after broker attempt");
   CTestAssert::EqualInt(1,harness.mockTransport.CallCount(),"Single broker transport call via async gateway");
   CTestAssert::True(harness.profitCloseTriggers.IsConsumed("trigger-broker"),"Profit close trigger registry must consume token");
  }

void TestBrokerRejectDoesNotCompleteLevel(CManualProfitCloseTestHarness &harness)
  {
   harness.Reset();
   harness.mockTransport.SetNextAccepted(false,TRADE_RETCODE_REJECT,1,0);
   CManualProfitCloseCandidateEntry entry;
   CTestAssert::True(harness.RegisterValidCandidate(entry),"candidate");
   CBasketAggregate basket=harness.BuildActiveBasket();
   harness.SeedOpenPosition(basket.Id(),TEST_POSITION_TICKET,0.10,100.0);
   CTestAssert::True(harness.PrepareClosePending(entry,basket),"prepare close pending");
   CPendingExecutionEntry pending;
   harness.pendingRegistry.TryGetByExecutionRequestId(entry.ExecutionRequestId(),pending);
   string token=harness.IssueToken(pending,harness.clock.Now()+300);
   CMarketQuote quote=CManualProfitCloseTestHarness::BuildQuote(10);
   CDemoManualSubmissionResult result=harness.SubmitCandidate(entry.CandidateId(),token,"trigger-reject",quote);
   CTestAssert::False(result.IsSuccess(),"Broker reject must not succeed");
   CTestAssert::False(harness.levelTracker.IsLevelCompleted(TEST_BASKET_ID_VALUE,PROFIT_LEVEL_ID),
                      "Broker reject must not complete profit level");
  }

void TestConfirmedFillCompletesLevelOnce(CManualProfitCloseTestHarness &harness)
  {
   harness.Reset();
   CManualProfitCloseCandidateEntry entry;
   CTestAssert::True(harness.RegisterValidCandidate(entry),"candidate");
   harness.levelTracker.MarkSubmitted(TEST_BASKET_ID_VALUE,PROFIT_LEVEL_ID,entry.ExecutionRequestId());
   harness.profitCloseService.OnBrokerFillConfirmed(entry.ExecutionRequestId());
   CTestAssert::True(harness.levelTracker.IsLevelCompleted(TEST_BASKET_ID_VALUE,PROFIT_LEVEL_ID),
                     "Confirmed fill must complete profit level once");
   CTestAssert::False(harness.levelTracker.TryMarkFilled(entry.ExecutionRequestId()),
                      "Duplicate fill must not complete level twice");
   harness.profitCloseService.OnBrokerFillConfirmed(entry.ExecutionRequestId());
   CManualProfitCloseCandidateEntry loaded;
   harness.candidateRegistry.TryGetByCandidateId(entry.CandidateId(),loaded);
   CTestAssert::EqualInt((int)BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_EXECUTED,(int)loaded.Status(),
                         "Candidate must remain executed after duplicate fill notification");
  }

void TestMockTransportIsOnlyBrokerCallPath(CManualProfitCloseTestHarness &harness)
  {
   harness.Reset();
   harness.mockTransport.SetNextAccepted(true,TRADE_RETCODE_PLACED,0,920002);
   CManualProfitCloseCandidateEntry entry;
   CTestAssert::True(harness.RegisterValidCandidate(entry),"candidate");
   CBasketAggregate basket=harness.BuildActiveBasket();
   harness.SeedOpenPosition(basket.Id(),TEST_POSITION_TICKET,0.10,100.0);
   CTestAssert::True(harness.PrepareClosePending(entry,basket),"prepare close pending");
   CPendingExecutionEntry pending;
   harness.pendingRegistry.TryGetByExecutionRequestId(entry.ExecutionRequestId(),pending);
   string token=harness.IssueToken(pending,harness.clock.Now()+300);
   harness.SubmitCandidate(entry.CandidateId(),token,"trigger-mock-only",CManualProfitCloseTestHarness::BuildQuote(10));
   CTestAssert::EqualInt(1,harness.mockTransport.CallCount(),
                         "OrderSendAsync must flow only through CMt5AsyncSubmissionGateway mock transport");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   CManualProfitCloseTestHarness harness;

   TestRegistryAcceptsEligibleCandidate();
   TestMultiInstructionRejectedAtRegistration();
   TestUnsupportedPositionModelRejectedAtRegistration();
   TestExpiredCandidateRejectedOnSubmission();
   TestStaleQuoteRejected();
   TestSelectedPositionMissingRejected();
   TestInsufficientPositionVolumeRejected();
   TestInvalidCloseVolumeRejected();
   TestFactoryBindsExactCandidateFields();
   TestProfitCloseTriggerOneShot();
   TestLevelTrackerFillOnce();
   TestNoAutomaticProfitCloseSubmissionWiring();
   TestTerminalPendingNoLongerBlocks();
   TestPreBrokerValidationDoesNotConsumeTrigger();
   TestBrokerSubmissionConsumesTrigger(harness);
   TestBrokerRejectDoesNotCompleteLevel(harness);
   TestConfirmedFillCompletesLevelOnce(harness);
   TestMockTransportIsOnlyBrokerCallPath(harness);

   CTestAssert::Summary("TestManualProfitCloseCandidateValidation");
   if(!CTestAssert::AllPassed())
      Print("TestManualProfitCloseCandidateValidation FAILED");
  }
