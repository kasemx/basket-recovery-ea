#property script_show_inputs
#property description "Sprint 8C: register live DUE profit-close candidate from seeded basket."

#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5Clock.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5UniqueIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5AccountPositionModelProvider.mqh>
#include <BasketRecovery/Infrastructure/Market/Mt5MarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/Mt5BrokerPositionReader.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5AccountExecutionEligibilityProvider.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateRegistrationService.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateEventBuffer.mqh>
#include <BasketRecovery/Application/Execution/ProfitCloseCandidateSubmissionValidator.mqh>
#include <BasketRecovery/Application/Execution/ProfitLevelCloseExecutionTracker.mqh>
#include <BasketRecovery/Application/Strategy/ProfitLevelCloseCandidatePlanningService.mqh>
#include <BasketRecovery/Application/Strategy/ProfitLevelCloseCandidateEventBuffer.mqh>
#include <BasketRecovery/Application/Services/StrategyEvaluationContextFactory.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Domain/Market/Enums/AccountPositionModel.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

input string InpBasketId = "sprint8c-demo-btc-001";
input int    InpManualProfitCloseCandidateExpirySeconds = 60;

void WriteLine(const int handle,const string line)
  {
   if(handle!=INVALID_HANDLE)
      FileWriteString(handle,line+"\r\n");
   Print(line);
  }

void SyncSnapshotFromBroker(CInMemorySnapshotStore &snapshotStore,const CBasketId &basketId)
  {
   CMt5BrokerPositionReader reader;
   CPositionSnapshotEntry brokerEntries[];
   CResult<int> readResult=reader.ReadOpenPositions(brokerEntries,256);
   if(readResult.IsFail())
      return;
   int brokerCount=0;
   readResult.TryGetValue(brokerCount);

   CPositionSnapshotEntry matched[];
   int matchedCount=0;
   for(int i=0;i<brokerCount;i++)
     {
      if(brokerEntries[i].BasketId()!=basketId)
         continue;
      ArrayResize(matched,matchedCount+1);
      matched[matchedCount]=brokerEntries[i];
      matchedCount++;
     }
   snapshotStore.CreateEmpty(basketId);
   snapshotStore.ReplaceEntries(basketId,matched,matchedCount);
  }

void OnStart(void)
  {
   string reportRel="BasketRecovery/validation/sprint-8c-register-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      return;

   CMt5Clock *clock=new CMt5Clock();
   CMt5UniqueIdGenerator *idGenerator=new CMt5UniqueIdGenerator();
   CFileBasketRepository *repository=new CFileBasketRepository(BRE_PERSISTENCE_BASKET_SUBDIR);
   CMt5MarketDataProvider *marketData=new CMt5MarketDataProvider(clock);
   CInMemorySnapshotStore *snapshotStore=new CInMemorySnapshotStore(clock);
   CPendingExecutionRegistry *pendingRegistry=new CPendingExecutionRegistry();
   CProfitLevelCloseExecutionTracker *levelTracker=new CProfitLevelCloseExecutionTracker();
   CMt5AccountExecutionEligibilityProvider *eligibilityProvider=new CMt5AccountExecutionEligibilityProvider();
   CMt5AccountPositionModelProvider *positionModelProvider=new CMt5AccountPositionModelProvider();
   CManualProfitCloseCandidateRegistry *registry=new CManualProfitCloseCandidateRegistry();
   CManualProfitCloseCandidateEventBuffer *eventBuffer=new CManualProfitCloseCandidateEventBuffer();
   CProfitCloseCandidateSubmissionValidator *validator=
      new CProfitCloseCandidateSubmissionValidator(snapshotStore,
                                                   pendingRegistry,
                                                   levelTracker,
                                                   eligibilityProvider,
                                                   5000);
   CManualProfitCloseCandidateRegistrationService *registrationService=
      new CManualProfitCloseCandidateRegistrationService(registry,
                                                         eventBuffer,
                                                         validator,
                                                         levelTracker,
                                                         snapshotStore,
                                                         positionModelProvider,
                                                         clock,
                                                         idGenerator,
                                                         InpManualProfitCloseCandidateExpirySeconds);
   CProfitLevelCloseCandidateEventBuffer *planEventBuffer=new CProfitLevelCloseCandidateEventBuffer();
   CProfitLevelCloseCandidatePlanningService *planningService=
      new CProfitLevelCloseCandidatePlanningService(pendingRegistry,planEventBuffer,5000);

   CResult<CBasketAggregate> basketResult=repository.Load(CBasketId(InpBasketId));
   if(basketResult.IsFail())
     {
      WriteLine(reportHandle,"register_verification=FAIL");
      WriteLine(reportHandle,"failure_reason="+basketResult.ErrorMessage());
      FileClose(reportHandle);
      delete planningService; delete planEventBuffer;
      delete registrationService; delete validator; delete eventBuffer; delete registry;
      delete positionModelProvider; delete eligibilityProvider; delete levelTracker;
      delete pendingRegistry; delete snapshotStore; delete marketData;
      delete repository; delete idGenerator; delete clock;
      return;
     }

   CBasketAggregate basket;
   basketResult.TryGetValue(basket);
   SyncSnapshotFromBroker(*snapshotStore,basket.Id());

   CResult<CMarketQuote> quoteResult=marketData.TryGetQuote(basket.Symbol());
   if(quoteResult.IsFail())
     {
      WriteLine(reportHandle,"register_verification=FAIL");
      WriteLine(reportHandle,"failure_reason="+quoteResult.ErrorMessage());
      FileClose(reportHandle);
      delete planningService; delete planEventBuffer;
      delete registrationService; delete validator; delete eventBuffer; delete registry;
      delete positionModelProvider; delete eligibilityProvider; delete levelTracker;
      delete pendingRegistry; delete snapshotStore; delete marketData;
      delete repository; delete idGenerator; delete clock;
      return;
     }

   CMarketQuote quote;
   quoteResult.TryGetValue(quote);

   CResult<CAccountContextSnapshot> accountResult=marketData.TryGetAccountSnapshot();
   CAccountContextSnapshot account;
   if(accountResult.IsOk())
      accountResult.TryGetValue(account);

   datetime nowUtc=clock.Now();
   CRecoveryRiskGateInput gateInput=CRecoveryRiskGateInput::Create(quote,account,0,5000,
                                                                   basket.StrategyProfileHash(),
                                                                   basket.CorrelationKey(),
                                                                   nowUtc);

   CRiskRuntimeContext riskContext=CRiskRuntimeContext::Create(0.0,1.0,1.2,0.0,true,false);
   CResult<CStrategyEvaluationContext> evalResult=CStrategyEvaluationContextFactory::TryBuild(basket,
                                                                                            CMarketContext::Create(basket.Symbol(),quote.Bid(),quote.Ask(),quote.Point()),
                                                                                            riskContext,
                                                                                            snapshotStore);
   if(evalResult.IsFail())
     {
      WriteLine(reportHandle,"register_verification=FAIL");
      WriteLine(reportHandle,"failure_reason="+evalResult.ErrorMessage());
      FileClose(reportHandle);
      delete planningService; delete planEventBuffer;
      delete registrationService; delete validator; delete eventBuffer; delete registry;
      delete positionModelProvider; delete eligibilityProvider; delete levelTracker;
      delete pendingRegistry; delete snapshotStore; delete marketData;
      delete repository; delete idGenerator; delete clock;
      return;
     }

   CStrategyEvaluationContext evalContext;
   evalResult.TryGetValue(evalContext);

   ENUM_BRE_ACCOUNT_POSITION_MODEL positionModel=positionModelProvider.Capture();
   WriteLine(reportHandle,"account_position_model="+CAccountPositionModelHelper::ToString(positionModel));
   WriteLine(reportHandle,"snapshot_open_positions="+IntegerToString(evalContext.PositionCount()));
   WriteLine(reportHandle,"floating_profit_usd="+DoubleToString(evalContext.FloatingProfitUsd(),4));

   CProfitLevelCloseCandidate candidate=planningService.EvaluateAndEmit(basket,evalContext,gateInput);
   WriteLine(reportHandle,"planner_status="+IntegerToString((int)candidate.Status()));
   WriteLine(reportHandle,"reduction_count="+IntegerToString(candidate.Audit().ReductionCount()));
   WriteLine(reportHandle,"candidate_due="+(candidate.IsDue()?"true":"false"));

   int registered=registrationService.TryRegisterFromCandidate(basket,candidate,gateInput);
   WriteLine(reportHandle,"registered_count="+IntegerToString(registered));
   WriteLine(reportHandle,"registry_available="+IntegerToString(registry.CountAvailable()));

   CManualProfitCloseCandidateEntry entry;
   if(candidate.IsDue() && registry.TryGetByCandidateId(candidate.Audit().IdempotencyKey(),entry))
     {
      WriteLine(reportHandle,"candidate_id="+entry.CandidateId());
      WriteLine(reportHandle,"profit_level_id="+entry.ProfitLevelId());
      WriteLine(reportHandle,"position_ticket="+IntegerToString((long)entry.PositionTicket()));
      WriteLine(reportHandle,"original_position_volume="+DoubleToString(entry.OriginalPositionVolume(),8));
      WriteLine(reportHandle,"proposed_close_volume="+DoubleToString(entry.ProposedCloseVolume(),8));
      WriteLine(reportHandle,"single_instruction="+(candidate.Audit().ReductionCount()==1?"true":"false"));
     }

   WriteLine(reportHandle,"basket_id="+InpBasketId);
   WriteLine(reportHandle,"register_verification="+(registered>0 && candidate.IsDue() && candidate.Audit().ReductionCount()==1 ? "OK" : "FAIL"));
   if(registered<=0)
      WriteLine(reportHandle,"failure_reason=No DUE single-instruction profit-close candidate registered");
   FileClose(reportHandle);

   delete planningService; delete planEventBuffer;
   delete registrationService; delete validator; delete eventBuffer; delete registry;
   delete positionModelProvider; delete eligibilityProvider; delete levelTracker;
   delete pendingRegistry; delete snapshotStore; delete marketData;
   delete repository; delete idGenerator; delete clock;
  }
