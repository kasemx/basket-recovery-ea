#property script_show_inputs
#property description "Sprint 8C: register live DUE profit-close candidate from seeded basket."

#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5Clock.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5UniqueIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5AccountPositionModelProvider.mqh>
#include <BasketRecovery/Infrastructure/Market/Mt5MarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/Mt5BrokerPositionReader.mqh>
#include <BasketRecovery/Application/Services/BasketPositionReconciler.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ProfitLevelCloseCandidateStatus.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ProfitLevelCloseReason.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitDistributionPlan.mqh>
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
#include <BasketRecovery/Application/Execution/PendingExecutionReconciliationHydrator.mqh>
#include <BasketRecovery/Validation/Sprint8C/Sprint8cPendingExecutionPersistenceDiagnostics.mqh>
#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Domain/Reconciliation/BasketReconciliationApplyOutcome.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Validation/Sprint8C/ManualProfitCloseCandidateValidationArtifact.mqh>
#include <BasketRecovery/Domain/Execution/ProfitCloseCandidateCloseVolumeCalculator.mqh>
#include <BasketRecovery/Validation/Sprint8C/Sprint8cValidationProfile.mqh>

#define BRE_REGISTER_SCRIPT_BUILD_MARKER "S8C_TICKET_SCOPED_PENDING_REGISTER_V2"
#define BRE_REGISTER_TTL_BUILD_MARKER "S8C_ARTIFACT_TTL_360_D0E_V1"

input string InpBasketId = "sprint8c-demo-xauusd-002";
input int    InpManualProfitCloseCandidateExpirySeconds = 360;
input int    InpAuthorizationTokenExpirySeconds = 300;

void WriteLine(const int handle,const string line)
  {
   if(handle!=INVALID_HANDLE)
      FileWriteString(handle,line+"\r\n");
   Print(line);
  }

void WriteArtifactDiagnostics(const int reportHandle,const SSprint8cCandidateArtifactDiagnostics &diagnostics)
  {
   WriteLine(reportHandle,"candidate_artifact_store_path="+diagnostics.store_path);
   WriteLine(reportHandle,"candidate_artifact_key="+diagnostics.artifact_key);
   WriteLine(reportHandle,"candidate_artifact_found="+(diagnostics.found?"true":"false"));
   WriteLine(reportHandle,"candidate_artifact_created_at="+IntegerToString((long)diagnostics.created_at));
   WriteLine(reportHandle,"candidate_artifact_expires_at="+IntegerToString((long)diagnostics.expires_at));
   WriteLine(reportHandle,"candidate_artifact_execution_request_id="+diagnostics.execution_request_id);
   WriteLine(reportHandle,"candidate_artifact_ticket="+IntegerToString((long)diagnostics.ticket));
   WriteLine(reportHandle,"candidate_artifact_volume="+DoubleToString(diagnostics.volume,8));
   WriteLine(reportHandle,"candidate_artifact_validation="+diagnostics.validation);
   WriteLine(reportHandle,"candidate_artifact_failure_reason="+diagnostics.failure_reason);
   WriteLine(reportHandle,"candidate_artifact_existing_state="+diagnostics.existing_state);
   WriteLine(reportHandle,"candidate_artifact_replaced_expired="+(diagnostics.replaced_expired?"true":"false"));
   WriteLine(reportHandle,"candidate_artifact_replaced_insufficient_remaining="+(diagnostics.replaced_insufficient_remaining?"true":"false"));
   WriteLine(reportHandle,"candidate_artifact_expiry_remaining_seconds="+IntegerToString(diagnostics.expiry_remaining_seconds));
   WriteLine(reportHandle,"candidate_artifact_ttl_seconds="+IntegerToString(diagnostics.candidate_artifact_ttl_seconds));
   WriteLine(reportHandle,"auth_token_ttl_seconds="+IntegerToString(diagnostics.auth_token_ttl_seconds));
   WriteLine(reportHandle,"required_minimum_artifact_remaining_seconds="+IntegerToString(diagnostics.required_minimum_artifact_remaining_seconds));
   WriteLine(reportHandle,"candidate_artifact_reuse_allowed="+(diagnostics.reuse_allowed?"true":"false"));
   WriteLine(reportHandle,"candidate_artifact_reuse_rejection_reason="+diagnostics.reuse_rejection_reason);
   CManualProfitCloseCandidateValidationArtifact::LogDiagnostics(diagnostics);
   CManualProfitCloseCandidateValidationArtifact::PrintReuseEligibilityDiagnostics(diagnostics);
  }

bool TryFindSingleOpenBasketPosition(CInMemorySnapshotStore &snapshotStore,
                                     const CBasketId &basketId,
                                     CPositionSnapshotEntry &outEntry)
  {
   CPositionSnapshot *snapshot=snapshotStore.Get(basketId);
   if(snapshot==NULL)
      return false;

   bool found=false;
   for(int i=0;i<snapshot.EntryCount();i++)
     {
      CPositionSnapshotEntry entry;
      if(!snapshot.EntryAt(i,entry))
         continue;
      if(entry.Status()!=BRE_POSITION_SNAPSHOT_OPEN)
         continue;
      if(found)
         return false;
      outEntry=entry;
      found=true;
     }
   return found;
  }

bool TryFindOpenPositionByTicket(CInMemorySnapshotStore &snapshotStore,
                                 const CBasketId &basketId,
                                 const ulong ticket,
                                 CPositionSnapshotEntry &outEntry)
  {
   CPositionSnapshot *snapshot=snapshotStore.Get(basketId);
   if(snapshot==NULL)
      return false;
   for(int i=0;i<snapshot.EntryCount();i++)
     {
      CPositionSnapshotEntry entry;
      if(!snapshot.EntryAt(i,entry))
         continue;
      if(entry.Status()!=BRE_POSITION_SNAPSHOT_OPEN)
         continue;
      if(entry.Ticket()!=ticket)
         continue;
      outEntry=entry;
      return true;
     }
   return false;
  }

void WriteValidationProfileMarkers(const int reportHandle)
  {
   CSprint8cValidationProfile::LogProfileMarkers();
   WriteLine(reportHandle,"validation_profile_version="+CSprint8cValidationProfile::ProfileVersionLabel());
   WriteLine(reportHandle,"validation_profile_id="+CSprint8cValidationProfile::ProfileId());
   WriteLine(reportHandle,"validation_profit_trigger_type="+CSprint8cValidationProfile::FloatingProfitTriggerTypeLabel());
   WriteLine(reportHandle,"validation_profit_trigger_value_usd="+DoubleToString(CSprint8cValidationProfile::FloatingProfitTriggerUsd(),2));
   WriteLine(reportHandle,"validation_require_floating_profit_positive=true");
  }

void HydratePendingRegistryFromDisk(CPendingExecutionRegistry &registry,
                                    CFilePendingExecutionStore &pendingStore,
                                    int &restoredCountOut)
  {
   restoredCountOut=0;
   pendingStore.RestoreFromDisk();
   CPendingExecutionEntry restored[];
   restoredCountOut=pendingStore.RestoreEntries(restored);
   for(int i=0;i<restoredCountOut;i++)
     {
      CPendingExecutionReconciliationHydrator::TryHydrate(restored[i],&pendingStore);
      registry.Upsert(restored[i]);
     }
  }

void WriteReconciliationDiagnostics(const int reportHandle,const SBasketReconciliationApplyOutcome &outcome)
  {
   WriteLine(reportHandle,"basket_lifecycle_before_reconcile="+CBasketLifecycleStateHelper::ToString(outcome.lifecycle_before));
   WriteLine(reportHandle,"basket_lifecycle_after_reconcile="+CBasketLifecycleStateHelper::ToString(outcome.lifecycle_after));
   WriteLine(reportHandle,"basket_resume_attempted="+(outcome.resume_attempted?"true":"false"));
   WriteLine(reportHandle,"basket_resume_result="+(outcome.resume_result?"true":"false"));
   WriteLine(reportHandle,"basket_resume_failure_reason="+outcome.resume_failure_reason);
   WriteLine(reportHandle,"max_risk_lockout="+(outcome.max_risk_lockout?"true":"false"));
   WriteLine(reportHandle,"reconciliation_clean="+(outcome.reconciliation_clean?"true":"false"));
   WriteLine(reportHandle,"reconciliation_blocking_reason="+outcome.blocking_reason);
   WriteLine(reportHandle,"unresolved_execution_count="+IntegerToString(outcome.unresolved_execution_count));
   WriteLine(reportHandle,"current_ticket_unresolved_count="+IntegerToString(outcome.current_ticket_unresolved_count));
   WriteLine(reportHandle,"foreign_ticket_unresolved_count="+IntegerToString(outcome.foreign_ticket_unresolved_count));
   WriteLine(reportHandle,"orphan_position_count="+IntegerToString(outcome.orphan_position_count));
   WriteLine(reportHandle,"expected_ticket="+IntegerToString((long)outcome.expected_ticket));
   WriteLine(reportHandle,"live_ticket="+IntegerToString((long)outcome.live_ticket));
   WriteLine(reportHandle,"expected_volume="+DoubleToString(outcome.expected_volume,8));
   WriteLine(reportHandle,"live_volume="+DoubleToString(outcome.live_volume,8));
   WriteLine(reportHandle,"persisted_basket_write_result="+outcome.persisted_basket_write_result);
  }

bool SyncSnapshotAndReconcileBasket(CInMemorySnapshotStore &snapshotStore,
                                    CFileBasketRepository &repository,
                                    CMt5Clock &clock,
                                    CPendingExecutionRegistry &pendingRegistry,
                                    CFilePendingExecutionStore &pendingStore,
                                    const CBasketId &basketId,
                                    SBasketReconciliationApplyOutcome &outcome)
  {
   outcome.Reset();
   CMt5BrokerPositionReader reader;
   CPositionSnapshotEntry brokerEntries[];
   CResult<int> readResult=reader.ReadOpenPositions(brokerEntries,256);
   if(readResult.IsFail())
     {
      outcome.blocking_reason="broker_read_failed:"+readResult.ErrorMessage();
      return false;
     }

   int brokerCount=0;
   readResult.TryGetValue(brokerCount);

   CBasketPositionReconciler reconciler(&reader,&snapshotStore,&repository,NULL,&clock);
   CVoidResult applyResult=reconciler.ReconcileAndApplyForBasket(basketId,brokerEntries,brokerCount,&pendingRegistry,outcome,&pendingStore);
   return applyResult.IsOk();
  }

void OnStart(void)
  {
   string reportRel="BasketRecovery/validation/sprint-8c-register-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      return;

   WriteValidationProfileMarkers(reportHandle);
   WriteLine(reportHandle,"register_script_build_marker="+BRE_REGISTER_SCRIPT_BUILD_MARKER);
   WriteLine(reportHandle,"register_ttl_build_marker="+BRE_REGISTER_TTL_BUILD_MARKER);
   WriteLine(reportHandle,"register_input_candidate_expiry_seconds="+IntegerToString(InpManualProfitCloseCandidateExpirySeconds));

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
   CFilePendingExecutionStore *pendingStore=new CFilePendingExecutionStore(CSprint8cPendingExecutionPersistenceDiagnostics::DefaultStoreRelativePath());
   CProfitLevelCloseCandidatePlanningService *planningService=
      new CProfitLevelCloseCandidatePlanningService(pendingRegistry,planEventBuffer,5000,pendingStore);

   CResult<CBasketAggregate> basketResult=repository.Load(CBasketId(InpBasketId));
   if(basketResult.IsFail())
     {
      WriteLine(reportHandle,"register_verification=FAIL");
      WriteLine(reportHandle,"failure_reason="+basketResult.ErrorMessage());
      FileClose(reportHandle);
      delete planningService; delete planEventBuffer;
      delete registrationService; delete validator; delete eventBuffer; delete registry;
      delete positionModelProvider; delete eligibilityProvider; delete levelTracker;
      delete pendingStore; delete pendingRegistry; delete snapshotStore; delete marketData;
      delete repository; delete idGenerator; delete clock;
      return;
     }

   CBasketAggregate basket;
   basketResult.TryGetValue(basket);

   int registerPendingLoadCount=0;
   HydratePendingRegistryFromDisk(*pendingRegistry,*pendingStore,registerPendingLoadCount);
   WriteLine(reportHandle,"register_pending_load_count="+IntegerToString(registerPendingLoadCount));
   WriteLine(reportHandle,"register_pending_load_source="+CSprint8cPendingExecutionPersistenceDiagnostics::DefaultStoreRelativePath());
   WriteLine(reportHandle,"reconcile_pending_restore_count="+IntegerToString(registerPendingLoadCount));
   SBasketReconciliationApplyOutcome reconcileOutcome;
   reconcileOutcome.Reset();
   SyncSnapshotAndReconcileBasket(*snapshotStore,*repository,*clock,*pendingRegistry,*pendingStore,basket.Id(),reconcileOutcome);
   WriteReconciliationDiagnostics(reportHandle,reconcileOutcome);

   basketResult=repository.Load(CBasketId(InpBasketId));
   if(basketResult.IsFail())
     {
      WriteLine(reportHandle,"register_verification=FAIL");
      WriteLine(reportHandle,"failure_reason="+basketResult.ErrorMessage());
      FileClose(reportHandle);
      delete planningService; delete planEventBuffer;
      delete registrationService; delete validator; delete eventBuffer; delete registry;
      delete positionModelProvider; delete eligibilityProvider; delete levelTracker;
      delete pendingStore; delete pendingRegistry; delete snapshotStore; delete marketData;
      delete repository; delete idGenerator; delete clock;
      return;
     }
   basketResult.TryGetValue(basket);

   CResult<CMarketQuote> quoteResult=marketData.TryGetQuote(basket.Symbol());
   if(quoteResult.IsFail())
     {
      WriteLine(reportHandle,"register_verification=FAIL");
      WriteLine(reportHandle,"failure_reason="+quoteResult.ErrorMessage());
      FileClose(reportHandle);
      delete planningService; delete planEventBuffer;
      delete registrationService; delete validator; delete eventBuffer; delete registry;
      delete positionModelProvider; delete eligibilityProvider; delete levelTracker;
      delete pendingStore; delete pendingRegistry; delete snapshotStore; delete marketData;
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
      delete pendingStore; delete pendingRegistry; delete snapshotStore; delete marketData;
      delete repository; delete idGenerator; delete clock;
      return;
     }

   CStrategyEvaluationContext evalContext;
   evalResult.TryGetValue(evalContext);

   CPositionSnapshotEntry livePositionBeforePlan;
   bool hasLivePositionBeforePlan=TryFindSingleOpenBasketPosition(*snapshotStore,basket.Id(),livePositionBeforePlan);
   ulong currentTicket=hasLivePositionBeforePlan ? livePositionBeforePlan.Ticket() : 0;
   ulong openTickets[];
   int openTicketCount=evalContext.PositionCount();
   ArrayResize(openTickets,openTicketCount);
   for(int ticketIndex=0;ticketIndex<openTicketCount;ticketIndex++)
      openTickets[ticketIndex]=evalContext.PositionAt(ticketIndex).Ticket();

   WriteLine(reportHandle,"register_runtime_build_marker="+BRE_REGISTER_SCRIPT_BUILD_MARKER);
   WriteLine(reportHandle,"register_pending_store_build_marker="+CFilePendingExecutionStore::BuildMarker());
   WriteLine(reportHandle,"planner_pending_checker_build_marker="+CRecoveryPendingExecutionChecker::BuildMarker());
   WriteLine(reportHandle,"current_ticket="+IntegerToString((long)currentTicket));
   WriteLine(reportHandle,"ticket_scoped_pending_filter_applied=true");
   WriteLine(reportHandle,"raw_unresolved_count="+IntegerToString(reconcileOutcome.unresolved_execution_count));
   WriteLine(reportHandle,"current_ticket_unresolved_count="+IntegerToString(reconcileOutcome.current_ticket_unresolved_count));
   WriteLine(reportHandle,"foreign_ticket_unresolved_count="+IntegerToString(reconcileOutcome.foreign_ticket_unresolved_count));

   CSprint8cPendingExecutionPersistenceDiagnostics::PrintRegisterRuntimeSummary(*pendingRegistry,
                                                                                 basket.Id(),
                                                                                 currentTicket,
                                                                                 openTickets,
                                                                                 openTicketCount,
                                                                                 pendingStore,
                                                                                 BRE_REGISTER_SCRIPT_BUILD_MARKER,
                                                                                 CFilePendingExecutionStore::BuildMarker(),
                                                                                 CRecoveryPendingExecutionChecker::BuildMarker());
   int pendingRowsPrinted=CSprint8cPendingExecutionPersistenceDiagnostics::PrintRegistryRecordsForBasket(*pendingRegistry,
                                                                                                       basket.Id(),
                                                                                                       currentTicket,
                                                                                                       openTickets,
                                                                                                       openTicketCount,
                                                                                                       pendingStore,
                                                                                                       "register_runtime_registry",
                                                                                                       pendingStore.FileRelativePath());
   if(pendingRowsPrinted==0)
     {
      Print("pending_record_id=NONE");
      Print("pending_record_execution_request_id=NONE");
      Print("pending_record_basket_id=",basket.Id().Value());
      Print("pending_record_ticket=NONE");
      Print("pending_record_status=NONE");
      Print("pending_record_is_current_ticket=false");
      Print("pending_record_blocks_current_ticket=false");
      Print("pending_record_blocks_basket_resume=false");
      Print("pending_record_blocks_planner=false");
      Print("pending_record_source_path=",pendingStore.FileRelativePath());
     }

   ENUM_BRE_ACCOUNT_POSITION_MODEL positionModel=positionModelProvider.Capture();
   WriteLine(reportHandle,"account_position_model="+CAccountPositionModelHelper::ToString(positionModel));
   WriteLine(reportHandle,"snapshot_open_positions="+IntegerToString(evalContext.PositionCount()));
   WriteLine(reportHandle,"floating_profit_usd="+DoubleToString(evalContext.FloatingProfitUsd(),4));

   CProfitLevelCloseCandidate candidate=planningService.EvaluateAndEmit(basket,evalContext,gateInput);
   WriteLine(reportHandle,"planner_status="+IntegerToString((int)candidate.Status()));
   WriteLine(reportHandle,"planner_status_enum_name="+CProfitLevelCloseCandidateStatusText::ToString(candidate.Status()));
   WriteLine(reportHandle,"planner_close_reason="+CProfitLevelCloseReasonText::ToString(candidate.Reason()));
   WriteLine(reportHandle,"basket_lifecycle="+CBasketLifecycleStateHelper::ToString(basket.LifecycleState()));
   WriteLine(reportHandle,"basket_version="+IntegerToString(basket.Version()));
   WriteLine(reportHandle,"strategy_profile_hash="+basket.StrategyProfileHash());
   WriteLine(reportHandle,"profit_level_id="+candidate.Audit().ProfitLevelId());
   CBasketProfitLevelProgress levelProgress;
   bool hasLevelProgress=basket.FindProfitLevelProgress(candidate.Audit().ProfitLevelId(),levelProgress);
   WriteLine(reportHandle,"profit_level_completed="+(hasLevelProgress && levelProgress.CloseCompleted()?"true":"false"));
   WriteLine(reportHandle,"profit_level_already_submitted="+(hasLevelProgress && levelProgress.CloseRequested()?"true":"false"));
   WriteLine(reportHandle,"profit_level_current_state="+CProfitLevelProgressStateText::ToString(
      CProfitLevelProgressStateText::FromBasketProgress(hasLevelProgress && levelProgress.CloseCompleted(),
                                                        hasLevelProgress && levelProgress.CloseRequested())));
   CProfitLevel plannerLevel;
   double remainingClosePercent=0.0;
   CProfitDistributionPlan distributionPlan=evalContext.Profile().ProfitDistributionPlan();
   for(int levelIndex=0;levelIndex<distributionPlan.LevelCount();levelIndex++)
     {
      CProfitLevel level=distributionPlan.LevelAt(levelIndex);
      if(level.LevelId()==candidate.Audit().ProfitLevelId())
        {
         plannerLevel=level;
         remainingClosePercent=level.ClosePercent();
         break;
        }
     }
   WriteLine(reportHandle,"profit_level_remaining_close_percent="+DoubleToString(remainingClosePercent,2));
   WriteLine(reportHandle,"profit_close_volume_calc_build_marker="+CProfitCloseCandidateCloseVolumeCalculator::BuildMarker());
   WriteLine(reportHandle,"reduction_count="+IntegerToString(candidate.Audit().ReductionCount()));
   WriteLine(reportHandle,"candidate_due="+(candidate.IsDue()?"true":"false"));
   WriteLine(reportHandle,"candidate_current_floating_profit_usd="+DoubleToString(evalContext.FloatingProfitUsd(),4));

   CPositionReductionInstruction plannerInstruction;
   ulong plannerTicket=0;
   double plannerOriginalVolume=0.0;
   if(candidate.Audit().ReductionAt(0,plannerInstruction))
     {
      plannerTicket=plannerInstruction.Ticket();
      CPositionSnapshotEntry plannerPosition;
      if(TryFindOpenPositionByTicket(*snapshotStore,basket.Id(),plannerTicket,plannerPosition))
         plannerOriginalVolume=plannerPosition.Volume();
     }

   CPositionSnapshotEntry livePosition;
   bool hasLivePosition=TryFindSingleOpenBasketPosition(*snapshotStore,basket.Id(),livePosition);
   ulong liveTicket=hasLivePosition ? livePosition.Ticket() : 0;
   double liveVolume=hasLivePosition ? livePosition.Volume() : 0.0;
   WriteLine(reportHandle,"current_position_ticket="+IntegerToString((long)liveTicket));
   WriteLine(reportHandle,"current_position_volume="+DoubleToString(liveVolume,8));
   WriteLine(reportHandle,"expected_position_ticket="+IntegerToString((long)plannerTicket));
   WriteLine(reportHandle,"expected_position_volume="+DoubleToString(plannerOriginalVolume,8));
   if(candidate.Audit().ReductionAt(0,plannerInstruction))
      WriteLine(reportHandle,"profit_level_remaining_close_volume="+DoubleToString(plannerInstruction.ProposedCloseVolume(),8));
   else
      WriteLine(reportHandle,"profit_level_remaining_close_volume=0.00000000");
   if(!candidate.IsDue())
      WriteLine(reportHandle,"candidate_blocking_condition="+CProfitLevelCloseReasonText::ToString(candidate.Reason()));

   string liveValidationFailure="";
   bool liveValidationOk=hasLivePosition &&
                         CManualProfitCloseCandidateValidationArtifact::ValidateLiveRegistrationPreconditions(
                            candidate.IsDue(),
                            evalContext.FloatingProfitUsd(),
                            plannerTicket,
                            plannerOriginalVolume,
                            liveTicket,
                            liveVolume,
                            basket.StrategyProfileHash(),
                            liveValidationFailure);
   WriteLine(reportHandle,"candidate_live_position_validation="+(liveValidationOk?"OK":"FAIL"));
   if(!liveValidationOk && liveValidationFailure!="")
      WriteLine(reportHandle,"failure_reason="+liveValidationFailure);

   int registered=0;
   bool artifactReused=false;
   bool artifactReplacedExpired=false;
   bool artifactReplacedInsufficientRemaining=false;
   string newExecutionRequestId="";
   SSprint8cCandidateArtifactRecord artifactRecord;
   SSprint8cCandidateArtifactDiagnostics artifactDiag;
   artifactDiag.Reset();

   if(!liveValidationOk)
     {
      WriteLine(reportHandle,"registered_count=0");
      WriteLine(reportHandle,"candidate_artifact_reused=false");
      WriteLine(reportHandle,"candidate_artifact_replaced_expired=false");
      WriteLine(reportHandle,"registry_available="+IntegerToString(registry.CountAvailable()));
      WriteLine(reportHandle,"basket_id="+InpBasketId);
      WriteLine(reportHandle,"register_verification=FAIL");
      FileClose(reportHandle);
      delete planningService; delete planEventBuffer;
      delete registrationService; delete validator; delete eventBuffer; delete registry;
      delete positionModelProvider; delete eligibilityProvider; delete levelTracker;
      delete pendingStore; delete pendingRegistry; delete snapshotStore; delete marketData;
      delete repository; delete idGenerator; delete clock;
      return;
     }

   SSprint8cCandidateArtifactRecord existingArtifact;
   bool hasExistingArtifact=CManualProfitCloseCandidateValidationArtifact::TryReadRecord(
      CManualProfitCloseCandidateValidationArtifact::DefaultRelativePath(),existingArtifact);
   string oldExecutionRequestId=hasExistingArtifact ? existingArtifact.execution_request_id : "";
   string existingState="none";
   string existingClassifyFailure="";
   double registerClosePercent=remainingClosePercent>0.0 ? remainingClosePercent : candidate.Audit().TargetClosePercent();
   double registerCanonicalCloseVolume=CProfitCloseCandidateCloseVolumeCalculator::ComputePartialCloseVolume(
      liveVolume,registerClosePercent,quote.Constraints());
   CManualProfitCloseCandidateEntry provisionalEntry=CManualProfitCloseCandidateEntry::Create(
      candidate.Audit().IdempotencyKey(),
      "provisional",
      candidate.Audit().IdempotencyKey(),
      basket.Id(),
      candidate.Audit().ProfitLevelId(),
      candidate.Audit().ProfitLevelIndex(),
      basket.StrategyProfileHash(),
      candidate.Audit().BasketVersion(),
      basket.Symbol(),
      basket.Direction(),
      livePosition.Direction(),
      liveTicket,
      liveVolume,
      registerCanonicalCloseVolume,
      plannerInstruction.EstimatedCloseMoney(),
      candidate.Audit().TriggerType(),
      candidate.Audit().TriggerValue(),
      candidate.Audit().QuoteSequence(),
      nowUtc,
      nowUtc+InpManualProfitCloseCandidateExpirySeconds,
      positionModel);
   if(hasExistingArtifact)
      existingState=CManualProfitCloseCandidateValidationArtifact::ClassifyExistingArtifactState(
         existingArtifact,nowUtc,provisionalEntry,existingClassifyFailure,InpAuthorizationTokenExpirySeconds);
   if(hasExistingArtifact)
      CManualProfitCloseCandidateValidationArtifact::FillReuseEligibilityDiagnostics(existingArtifact,
                                                                                      nowUtc,
                                                                                      InpAuthorizationTokenExpirySeconds,
                                                                                      artifactDiag);
   WriteLine(reportHandle,"candidate_artifact_existing_state="+existingState);
   WriteLine(reportHandle,"candidate_artifact_ttl_seconds="+IntegerToString(CManualProfitCloseCandidateValidationArtifact::DefaultArtifactTtlSeconds()));
   WriteLine(reportHandle,"auth_token_ttl_seconds="+IntegerToString(InpAuthorizationTokenExpirySeconds));
   WriteLine(reportHandle,"required_minimum_artifact_remaining_seconds="+IntegerToString(
      CManualProfitCloseCandidateValidationArtifact::ComputeRequiredMinimumArtifactRemainingSeconds(InpAuthorizationTokenExpirySeconds)));
   if(hasExistingArtifact)
     {
      WriteLine(reportHandle,"candidate_artifact_expiry_remaining_seconds="+IntegerToString(artifactDiag.expiry_remaining_seconds));
      WriteLine(reportHandle,"candidate_artifact_reuse_allowed="+(artifactDiag.reuse_allowed?"true":"false"));
      WriteLine(reportHandle,"candidate_artifact_reuse_rejection_reason="+artifactDiag.reuse_rejection_reason);
     }

   if(existingState=="invalid")
     {
      artifactDiag.store_path=CManualProfitCloseCandidateValidationArtifact::DefaultRelativePath();
      artifactDiag.found=true;
      artifactDiag.existing_state=existingState;
      artifactDiag.validation="FAIL";
      artifactDiag.failure_reason=existingClassifyFailure;
      WriteArtifactDiagnostics(reportHandle,artifactDiag);
      WriteLine(reportHandle,"registered_count=0");
      WriteLine(reportHandle,"registry_available="+IntegerToString(registry.CountAvailable()));
      WriteLine(reportHandle,"basket_id="+InpBasketId);
      WriteLine(reportHandle,"candidate_artifact_reused=false");
      WriteLine(reportHandle,"candidate_artifact_replaced_expired=false");
      WriteLine(reportHandle,"register_verification=FAIL");
      FileClose(reportHandle);
      delete planningService; delete planEventBuffer;
      delete registrationService; delete validator; delete eventBuffer; delete registry;
      delete positionModelProvider; delete eligibilityProvider; delete levelTracker;
      delete pendingStore; delete pendingRegistry; delete snapshotStore; delete marketData;
      delete repository; delete idGenerator; delete clock;
      return;
     }

   bool reuseGateAllowed=false;
   if(hasExistingArtifact && existingState!="invalid")
      reuseGateAllowed=CManualProfitCloseCandidateValidationArtifact::TryEvaluateArtifactReuseAllowed(
         existingArtifact,nowUtc,provisionalEntry,InpAuthorizationTokenExpirySeconds,artifactDiag);

   if(reuseGateAllowed)
     {
      if(CManualProfitCloseCandidateValidationArtifact::EntryFromRecord(existingArtifact,provisionalEntry))
        {
         registry.TryRegister(provisionalEntry);
         registered=1;
         artifactReused=true;
         artifactRecord=existingArtifact;
         artifactDiag.store_path=CManualProfitCloseCandidateValidationArtifact::DefaultRelativePath();
         CManualProfitCloseCandidateValidationArtifact::FillDiagnosticsFromRecord(artifactDiag.store_path,
                                                                                  existingArtifact,
                                                                                  artifactDiag);
         CManualProfitCloseCandidateValidationArtifact::FillReuseEligibilityDiagnostics(existingArtifact,
                                                                                        nowUtc,
                                                                                        InpAuthorizationTokenExpirySeconds,
                                                                                        artifactDiag);
         artifactDiag.existing_state="valid";
         artifactDiag.validation="OK";
         newExecutionRequestId=existingArtifact.execution_request_id;
         if(artifactRecord.created_at>0 && artifactRecord.expires_at>artifactRecord.created_at)
           {
            long persistActualLifetime=(long)(artifactRecord.expires_at-artifactRecord.created_at);
            WriteLine(reportHandle,"persist_requested_artifact_ttl_seconds="+IntegerToString(InpManualProfitCloseCandidateExpirySeconds));
            WriteLine(reportHandle,"persist_actual_lifetime_seconds="+IntegerToString(persistActualLifetime));
           }
        }
     }
   else
     {
      registered=registrationService.TryRegisterFromCandidate(basket,candidate,gateInput);
      if(registered>0)
        {
         CManualProfitCloseCandidateEntry registeredEntry;
         if(registry.TryGetByCandidateId(candidate.Audit().IdempotencyKey(),registeredEntry))
           {
            bool persistedReused=false;
            bool persistedReplacedExpired=false;
            CManualProfitCloseCandidateEntry persistedEntry;
            if(!CManualProfitCloseCandidateValidationArtifact::TryPersistIdempotent(registeredEntry,
                                                                                  "DUE",
                                                                                  nowUtc,
                                                                                  persistedEntry,
                                                                                  persistedReused,
                                                                                  persistedReplacedExpired,
                                                                                  artifactDiag,
                                                                                  CManualProfitCloseCandidateValidationArtifact::DefaultRelativePath(),
                                                                                  InpAuthorizationTokenExpirySeconds))
              {
               WriteArtifactDiagnostics(reportHandle,artifactDiag);
               WriteLine(reportHandle,"candidate_artifact_reused=false");
               WriteLine(reportHandle,"candidate_artifact_replaced_expired=false");
               WriteLine(reportHandle,"candidate_artifact_replaced_insufficient_remaining=false");
               WriteLine(reportHandle,"register_verification=FAIL");
               WriteLine(reportHandle,"failure_reason=Could not persist candidate artifact");
               FileClose(reportHandle);
               delete planningService; delete planEventBuffer;
               delete registrationService; delete validator; delete eventBuffer; delete registry;
               delete positionModelProvider; delete eligibilityProvider; delete levelTracker;
               delete pendingStore; delete pendingRegistry; delete snapshotStore; delete marketData;
               delete repository; delete idGenerator; delete clock;
               return;
              }
            artifactReused=persistedReused;
            artifactReplacedExpired=persistedReplacedExpired;
            artifactReplacedInsufficientRemaining=artifactDiag.replaced_insufficient_remaining;
            newExecutionRequestId=persistedEntry.ExecutionRequestId();
            if(CManualProfitCloseCandidateValidationArtifact::TryReadRecord(
                  CManualProfitCloseCandidateValidationArtifact::DefaultRelativePath(),artifactRecord))
              {
               artifactDiag.expires_at=artifactRecord.expires_at;
               long persistActualLifetime=(long)(artifactRecord.expires_at-artifactRecord.created_at);
               WriteLine(reportHandle,"persist_requested_artifact_ttl_seconds="+IntegerToString(InpManualProfitCloseCandidateExpirySeconds));
               WriteLine(reportHandle,"persist_actual_lifetime_seconds="+IntegerToString(persistActualLifetime));
              }
           }
        }
     }

   WriteLine(reportHandle,"candidate_artifact_reused="+(artifactReused?"true":"false"));
   WriteLine(reportHandle,"candidate_artifact_replaced_expired="+(artifactReplacedExpired?"true":"false"));
   WriteLine(reportHandle,"candidate_artifact_replaced_insufficient_remaining="+(artifactReplacedInsufficientRemaining?"true":"false"));
   WriteLine(reportHandle,"candidate_artifact_new_execution_request_id="+newExecutionRequestId);
   WriteLine(reportHandle,"candidate_artifact_previous_execution_request_id="+oldExecutionRequestId);
   WriteLine(reportHandle,"candidate_artifact_expires_at="+IntegerToString((long)artifactDiag.expires_at));
   if(artifactDiag.store_path!="")
      WriteArtifactDiagnostics(reportHandle,artifactDiag);

   WriteLine(reportHandle,"registered_count="+IntegerToString(registered));
   WriteLine(reportHandle,"registry_available="+IntegerToString(registry.CountAvailable()));

   CManualProfitCloseCandidateEntry entry;
   string lookupCandidateId=artifactReused ? artifactRecord.candidate_id : candidate.Audit().IdempotencyKey();
   if(registered>0 && registry.TryGetByCandidateId(lookupCandidateId,entry))
     {
      WriteLine(reportHandle,"candidate_id="+entry.CandidateId());
      WriteLine(reportHandle,"execution_request_id="+entry.ExecutionRequestId());
      WriteLine(reportHandle,"profit_level_id="+entry.ProfitLevelId());
      WriteLine(reportHandle,"position_ticket="+IntegerToString((long)entry.PositionTicket()));
      WriteLine(reportHandle,"original_position_volume="+DoubleToString(entry.OriginalPositionVolume(),8));
      WriteLine(reportHandle,"proposed_close_volume="+DoubleToString(entry.ProposedCloseVolume(),8));
      WriteLine(reportHandle,"status=DUE");
      WriteLine(reportHandle,"single_instruction="+(candidate.Audit().ReductionCount()==1?"true":"false"));
     }

   WriteLine(reportHandle,"basket_id="+InpBasketId);
   bool registerOk=registered>0 &&
                   (artifactReused || (candidate.IsDue() && candidate.Audit().ReductionCount()==1));
   WriteLine(reportHandle,"register_verification="+(registerOk ? "OK" : "FAIL"));
   if(registered<=0)
      WriteLine(reportHandle,"failure_reason=No DUE single-instruction profit-close candidate registered");
   FileClose(reportHandle);

   delete planningService; delete planEventBuffer;
   delete registrationService; delete validator; delete eventBuffer; delete registry;
   delete positionModelProvider; delete eligibilityProvider; delete levelTracker;
   delete pendingStore; delete pendingRegistry; delete snapshotStore; delete marketData;
   delete repository; delete idGenerator; delete clock;
  }
