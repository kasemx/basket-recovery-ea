#ifndef BASKET_RECOVERY_APPLICATION_APPLICATION_CONTEXT_MQH
#define BASKET_RECOVERY_APPLICATION_APPLICATION_CONTEXT_MQH

#include <BasketRecovery/Application/Kernel/ServiceContainer.mqh>
#include <BasketRecovery/Application/Kernel/ApplicationKernel.mqh>
#include <BasketRecovery/Application/Services/CommandIngestionService.mqh>
#include <BasketRecovery/Application/Services/ExecutionDryRunManualCommandService.mqh>
#include <BasketRecovery/Application/Execution/ExecuteTradeIntentUseCase.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5TradeExecutor.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5OrderCheckGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5ExecutionDiagnostics.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionRequestRepository.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionJournal.mqh>
#include <BasketRecovery/Shared/DTOs/NormalizedTradeTransaction.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5TradeTransactionAdapter.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionDiagnostics.mqh>
#include <BasketRecovery/Application/Execution/InMemoryPendingExecutionEventBuffer.mqh>
#include <BasketRecovery/Application/Execution/TradeTransactionRouter.mqh>
#include <BasketRecovery/Application/Execution/ExecutionTimeoutMonitor.mqh>
#include <BasketRecovery/Application/Execution/ExecutionReconciliationScheduler.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionTestInjectionService.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationPolicy.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRestartService.mqh>
#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Domain/Execution/SubmissionPreparationResult.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationResult.mqh>
#include <BasketRecovery/Domain/Execution/LiveSubmissionSafetyRejectionReason.mqh>
#include <BasketRecovery/Application/Execution/ManualDemoAuthorizationValidationService.mqh>
#include <BasketRecovery/Application/Execution/ManualDemoAuthorizationUseCase.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionValidationService.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionTriggerRegistry.mqh>
#include <BasketRecovery/Application/Execution/SubmitPreparedExecutionUseCase.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionDiagnostics.mqh>
#include <BasketRecovery/Domain/Execution/DemoManualSubmissionResult.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationRegistry.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionAuthorizationStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5AccountExecutionEligibilityProvider.mqh>
#include <BasketRecovery/Application/Risk/RecoveryRiskEventBuffer.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/Mt5BrokerPositionReader.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CApplicationContext
  {
private:
   CServiceContainer  *m_container;
   CApplicationKernel *m_kernel;
   CExecutionDryRunManualCommandService *m_executionDryRunManualService;
   CMt5TradeExecutor  *m_mt5TradeExecutor;
   CExecuteTradeIntentUseCase *m_executeTradeIntentUseCase;
   CInMemoryExecutionRequestRepository *m_executionRequestRepository;
   CInMemoryExecutionJournal *m_executionJournal;
   CMt5OrderCheckGateway *m_orderCheckGateway;
   CMt5ExecutionDiagnostics *m_executionDiagnostics;
   CPendingExecutionRegistry *m_pendingExecutionRegistry;
   CPendingExecutionDiagnostics *m_pendingExecutionDiagnostics;
   CInMemoryPendingExecutionEventBuffer *m_pendingExecutionEventBuffer;
   CTradeTransactionRouter *m_tradeTransactionRouter;
   CExecutionReconciliationScheduler *m_executionReconciliationScheduler;
   CExecutionTimeoutMonitor *m_executionTimeoutMonitor;
   CPendingExecutionTestInjectionService *m_pendingExecutionTestInjection;
   CMt5BrokerPositionReader *m_executionReconciliationReader;
   CExecutionSubmissionPreparer *m_submissionPreparer;
   IPendingExecutionStore *m_pendingExecutionStore;
   CManualDemoAuthorizationValidationService *m_demoAuthorizationValidationService;
   CManualDemoAuthorizationUseCase *m_demoAuthorizationUseCase;
   CExecutionAuthorizationRegistry *m_authorizationRegistry;
   CInMemoryExecutionAuthorizationStore *m_authorizationStore;
   CMt5AccountExecutionEligibilityProvider *m_accountEligibilityProvider;
   CDemoManualSubmissionValidationService *m_demoManualSubmissionValidationService;
   CDemoManualSubmissionService *m_demoManualSubmissionService;
   CDemoManualSubmissionTriggerRegistry *m_demoSubmissionTriggerRegistry;
   CSubmitPreparedExecutionUseCase *m_submitPreparedExecutionUseCase;
   CMt5AsyncSubmissionGateway *m_asyncSubmissionGateway;
   CMt5AsyncSubmissionDiagnostics *m_asyncSubmissionDiagnostics;
   CMt5LiveAsyncOrderSendTransport *m_liveAsyncTransport;
   CRecoveryRiskEventBuffer *m_recoveryRiskEventBuffer;
   CRecoveryDecisionRiskGateService *m_recoveryRiskGateService;
   bool                m_initialized;

public:
                     CApplicationContext(void)
     {
      m_container=NULL;
      m_kernel=NULL;
      m_executionDryRunManualService=NULL;
      m_mt5TradeExecutor=NULL;
      m_executeTradeIntentUseCase=NULL;
      m_executionRequestRepository=NULL;
      m_executionJournal=NULL;
      m_orderCheckGateway=NULL;
      m_executionDiagnostics=NULL;
      m_pendingExecutionRegistry=NULL;
      m_pendingExecutionDiagnostics=NULL;
      m_pendingExecutionEventBuffer=NULL;
      m_tradeTransactionRouter=NULL;
      m_executionReconciliationScheduler=NULL;
      m_executionTimeoutMonitor=NULL;
      m_pendingExecutionTestInjection=NULL;
      m_executionReconciliationReader=NULL;
      m_submissionPreparer=NULL;
      m_pendingExecutionStore=NULL;
      m_demoAuthorizationValidationService=NULL;
      m_demoAuthorizationUseCase=NULL;
      m_authorizationRegistry=NULL;
      m_authorizationStore=NULL;
      m_accountEligibilityProvider=NULL;
      m_demoManualSubmissionValidationService=NULL;
      m_demoManualSubmissionService=NULL;
      m_demoSubmissionTriggerRegistry=NULL;
      m_submitPreparedExecutionUseCase=NULL;
      m_asyncSubmissionGateway=NULL;
      m_asyncSubmissionDiagnostics=NULL;
      m_liveAsyncTransport=NULL;
      m_recoveryRiskEventBuffer=NULL;
      m_recoveryRiskGateService=NULL;
      m_initialized=false;
     }

                    ~CApplicationContext(void)
     {
      Shutdown();
     }

   bool              Initialize(CServiceContainer *container,CApplicationKernel *kernel)
     {
      if(container==NULL || kernel==NULL)
         return false;
      m_container=container;
      m_kernel=kernel;
      m_initialized=true;
      return true;
     }

   void              RegisterExecutionDryRunRuntime(CExecutionDryRunManualCommandService *manualService,
                                                    CMt5TradeExecutor *mt5Executor,
                                                    CExecuteTradeIntentUseCase *useCase,
                                                    CInMemoryExecutionRequestRepository *repository,
                                                    CInMemoryExecutionJournal *journal,
                                                    CMt5OrderCheckGateway *orderCheckGateway,
                                                    CMt5ExecutionDiagnostics *diagnostics)
     {
      m_executionDryRunManualService=manualService;
      m_mt5TradeExecutor=mt5Executor;
      m_executeTradeIntentUseCase=useCase;
      m_executionRequestRepository=repository;
      m_executionJournal=journal;
      m_orderCheckGateway=orderCheckGateway;
      m_executionDiagnostics=diagnostics;
     }

   void              RegisterPendingExecutionRuntime(CPendingExecutionRegistry *registry,
                                                     CPendingExecutionDiagnostics *diagnostics,
                                                     CInMemoryPendingExecutionEventBuffer *eventBuffer,
                                                     CTradeTransactionRouter *router,
                                                     CExecutionReconciliationScheduler *reconciliationScheduler,
                                                     CExecutionTimeoutMonitor *timeoutMonitor,
                                                     CPendingExecutionTestInjectionService *testInjection,
                                                     CMt5BrokerPositionReader *reconciliationReader)
     {
      m_pendingExecutionRegistry=registry;
      m_pendingExecutionDiagnostics=diagnostics;
      m_pendingExecutionEventBuffer=eventBuffer;
      m_tradeTransactionRouter=router;
      m_executionReconciliationScheduler=reconciliationScheduler;
      m_executionTimeoutMonitor=timeoutMonitor;
      m_pendingExecutionTestInjection=testInjection;
      m_executionReconciliationReader=reconciliationReader;
     }

   void              RegisterRecoveryRiskRuntime(CRecoveryRiskEventBuffer *eventBuffer,
                                                 CRecoveryDecisionRiskGateService *gateService)
     {
      m_recoveryRiskEventBuffer=eventBuffer;
      m_recoveryRiskGateService=gateService;
     }

   void              RegisterSubmissionPreparationRuntime(CExecutionSubmissionPreparer *preparer,
                                                          IPendingExecutionStore *store)
     {
      m_submissionPreparer=preparer;
      m_pendingExecutionStore=store;
     }

   void              RegisterDemoAuthorizationRuntime(CManualDemoAuthorizationValidationService *validationService,
                                                      CManualDemoAuthorizationUseCase *useCase,
                                                      CExecutionAuthorizationRegistry *registry,
                                                      CInMemoryExecutionAuthorizationStore *store,
                                                      CMt5AccountExecutionEligibilityProvider *eligibilityProvider)
     {
      m_demoAuthorizationValidationService=validationService;
      m_demoAuthorizationUseCase=useCase;
      m_authorizationRegistry=registry;
      m_authorizationStore=store;
      m_accountEligibilityProvider=eligibilityProvider;
     }

   void              RegisterDemoManualSubmissionRuntime(CDemoManualSubmissionValidationService *validationService,
                                                           CDemoManualSubmissionService *submissionService,
                                                           CDemoManualSubmissionTriggerRegistry *triggerRegistry,
                                                           CSubmitPreparedExecutionUseCase *submitUseCase,
                                                           CMt5AsyncSubmissionGateway *asyncGateway,
                                                           CMt5AsyncSubmissionDiagnostics *asyncDiagnostics,
                                                           CMt5LiveAsyncOrderSendTransport *liveAsyncTransport)
     {
      m_demoManualSubmissionValidationService=validationService;
      m_demoManualSubmissionService=submissionService;
      m_demoSubmissionTriggerRegistry=triggerRegistry;
      m_submitPreparedExecutionUseCase=submitUseCase;
      m_asyncSubmissionGateway=asyncGateway;
      m_asyncSubmissionDiagnostics=asyncDiagnostics;
      m_liveAsyncTransport=liveAsyncTransport;
     }

   CDemoManualSubmissionResult TryProcessManualDemoSubmission(const string executionRequestId,
                                                              const string authorizationToken,
                                                              const string triggerToken,
                                                              const string basketIdValue)
     {
      if(m_demoManualSubmissionValidationService==NULL)
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_LIVE_DISABLED,
                                                      "Demo manual submission route is not configured");
      return m_demoManualSubmissionValidationService.TryProcessManualSubmission(executionRequestId,
                                                                                  authorizationToken,
                                                                                  triggerToken,
                                                                                  basketIdValue);
     }

   CExecutionAuthorizationResult TryProcessManualDemoAuthorizationValidation(const string executionRequestId,
                                                                               const string authorizationToken,
                                                                               const string basketIdValue)
     {
      if(m_demoAuthorizationValidationService==NULL)
         return CExecutionAuthorizationResult::Rejected(BRE_LIVE_SAFETY_LIVE_DISABLED,
                                                        "Demo authorization validation route is not configured");
      return m_demoAuthorizationValidationService.TryProcessManualAuthorizationForBasket(executionRequestId,
                                                                                           authorizationToken,
                                                                                           basketIdValue);
     }

   CSubmissionPreparationResult TryPrepareSubmission(const CTradeExecutionRequest &request,
                                                     const CBasketAggregate &basket,
                                                     const long magicNumber)
     {
      if(m_submissionPreparer==NULL)
         return CSubmissionPreparationResult::Fail(BRE_PREP_FAIL_VALIDATION,"Submission preparer is not configured");
      return m_submissionPreparer.Prepare(request,basket,magicNumber);
     }

   CVoidResult       TryProcessManualExecutionDryRun(const string basketIdValue,
                                                     const string triggerToken,
                                                     const double lotSize)
     {
      if(!m_initialized || m_executionDryRunManualService==NULL)
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Manual execution dry-run route is not configured");
      return m_executionDryRunManualService.TryProcessManualDryRunOpen(basketIdValue,triggerToken,lotSize);
     }

   bool              IsMt5ExecutorWiredToTimerPipeline(void) const { return false; }
   bool              IsSubmissionGatewayWiredToProduction(void) const { return false; }
   bool              IsSubmitPreparedExecutionWiredToTimer(void) const { return false; }
   bool              IsDemoAuthorizationWiredToStrategy(void) const { return false; }
   bool              IsDemoAuthorizationWiredToAutomaticTimer(void) const { return false; }
   bool              IsDemoAuthorizationWiredToRestIntake(void) const { return false; }
   bool              IsDemoAuthorizationWiredToOnTick(void) const { return false; }
   bool              IsDemoManualSubmissionWiredToStrategy(void) const { return false; }
   bool              IsDemoManualSubmissionWiredToAutomaticTimer(void) const { return false; }
   bool              IsDemoManualSubmissionWiredToRestIntake(void) const { return false; }
   bool              IsDemoManualSubmissionWiredToOnTick(void) const { return false; }
   bool              IsDemoManualSubmissionWiredToOnTradeTransaction(void) const { return false; }
   bool              IsLiveSubmissionApiWiredToProductionRuntime(void) const { return false; }

   void              Shutdown(void)
     {
      if(m_executionDryRunManualService!=NULL)
        {
         delete m_executionDryRunManualService;
         m_executionDryRunManualService=NULL;
        }
      if(m_executeTradeIntentUseCase!=NULL)
        {
         delete m_executeTradeIntentUseCase;
         m_executeTradeIntentUseCase=NULL;
        }
      if(m_executionJournal!=NULL)
        {
         delete m_executionJournal;
         m_executionJournal=NULL;
        }
      if(m_executionRequestRepository!=NULL)
        {
         delete m_executionRequestRepository;
         m_executionRequestRepository=NULL;
        }
      if(m_mt5TradeExecutor!=NULL)
        {
         delete m_mt5TradeExecutor;
         m_mt5TradeExecutor=NULL;
        }
      if(m_orderCheckGateway!=NULL)
        {
         delete m_orderCheckGateway;
         m_orderCheckGateway=NULL;
        }
      if(m_executionDiagnostics!=NULL)
        {
         delete m_executionDiagnostics;
         m_executionDiagnostics=NULL;
        }
      if(m_recoveryRiskGateService!=NULL)
        {
         delete m_recoveryRiskGateService;
         m_recoveryRiskGateService=NULL;
        }
      if(m_recoveryRiskEventBuffer!=NULL)
        {
         delete m_recoveryRiskEventBuffer;
         m_recoveryRiskEventBuffer=NULL;
        }
      if(m_pendingExecutionTestInjection!=NULL)
        {
         delete m_pendingExecutionTestInjection;
         m_pendingExecutionTestInjection=NULL;
        }
      if(m_executionTimeoutMonitor!=NULL)
        {
         delete m_executionTimeoutMonitor;
         m_executionTimeoutMonitor=NULL;
        }
      if(m_executionReconciliationScheduler!=NULL)
        {
         delete m_executionReconciliationScheduler;
         m_executionReconciliationScheduler=NULL;
        }
      if(m_tradeTransactionRouter!=NULL)
        {
         delete m_tradeTransactionRouter;
         m_tradeTransactionRouter=NULL;
        }
      if(m_pendingExecutionEventBuffer!=NULL)
        {
         delete m_pendingExecutionEventBuffer;
         m_pendingExecutionEventBuffer=NULL;
        }
      if(m_pendingExecutionDiagnostics!=NULL)
        {
         delete m_pendingExecutionDiagnostics;
         m_pendingExecutionDiagnostics=NULL;
        }
      if(m_pendingExecutionRegistry!=NULL)
        {
         delete m_pendingExecutionRegistry;
         m_pendingExecutionRegistry=NULL;
        }
      if(m_executionReconciliationReader!=NULL)
        {
         delete m_executionReconciliationReader;
         m_executionReconciliationReader=NULL;
        }
      if(m_submissionPreparer!=NULL)
        {
         delete m_submissionPreparer;
         m_submissionPreparer=NULL;
        }
      if(m_pendingExecutionStore!=NULL)
        {
         delete m_pendingExecutionStore;
         m_pendingExecutionStore=NULL;
        }
      if(m_demoManualSubmissionValidationService!=NULL)
        {
         delete m_demoManualSubmissionValidationService;
         m_demoManualSubmissionValidationService=NULL;
        }
      if(m_demoManualSubmissionService!=NULL)
        {
         delete m_demoManualSubmissionService;
         m_demoManualSubmissionService=NULL;
        }
      if(m_demoSubmissionTriggerRegistry!=NULL)
        {
         delete m_demoSubmissionTriggerRegistry;
         m_demoSubmissionTriggerRegistry=NULL;
        }
      if(m_submitPreparedExecutionUseCase!=NULL)
        {
         delete m_submitPreparedExecutionUseCase;
         m_submitPreparedExecutionUseCase=NULL;
        }
      if(m_liveAsyncTransport!=NULL)
        {
         delete m_liveAsyncTransport;
         m_liveAsyncTransport=NULL;
        }
      if(m_asyncSubmissionGateway!=NULL)
        {
         delete m_asyncSubmissionGateway;
         m_asyncSubmissionGateway=NULL;
        }
      if(m_asyncSubmissionDiagnostics!=NULL)
        {
         delete m_asyncSubmissionDiagnostics;
         m_asyncSubmissionDiagnostics=NULL;
        }
      if(m_demoAuthorizationValidationService!=NULL)
        {
         delete m_demoAuthorizationValidationService;
         m_demoAuthorizationValidationService=NULL;
        }
      if(m_demoAuthorizationUseCase!=NULL)
        {
         delete m_demoAuthorizationUseCase;
         m_demoAuthorizationUseCase=NULL;
        }
      if(m_authorizationRegistry!=NULL)
        {
         delete m_authorizationRegistry;
         m_authorizationRegistry=NULL;
        }
      if(m_authorizationStore!=NULL)
        {
         delete m_authorizationStore;
         m_authorizationStore=NULL;
        }
      if(m_accountEligibilityProvider!=NULL)
        {
         delete m_accountEligibilityProvider;
         m_accountEligibilityProvider=NULL;
        }
      if(m_kernel!=NULL)
        {
         delete m_kernel;
         m_kernel=NULL;
        }
      if(m_container!=NULL)
        {
         m_container.Shutdown();
         delete m_container;
         m_container=NULL;
        }
      m_initialized=false;
     }

   bool              IsInitialized(void) const { return m_initialized; }

   CVoidResult       ApplyNormalizedTransaction(const CNormalizedTradeTransaction &transaction)
     {
      if(!m_initialized || m_kernel==NULL)
         return CVoidResult::Fail(BRE_ERR_SNAPSHOT_APPLY_FAILED,"Application context is not initialized");

      if(m_tradeTransactionRouter!=NULL)
        {
         CTradeTransactionCorrelationContext context=
            CMt5TradeTransactionAdapter::BuildContext(transaction,0);
         m_tradeTransactionRouter.Route(context);
        }

      CTradeTransactionFastPathService *fastPath=m_kernel.TradeTransactionFastPath();
      if(fastPath==NULL)
         return CVoidResult::Fail(BRE_ERR_SNAPSHOT_APPLY_FAILED,"Trade transaction fast path is unavailable");

      return fastPath.Handle(transaction);
     }

   int               OnTick(const string symbol)
     {
      if(!m_initialized || m_kernel==NULL)
         return 0;

      CTimerFallbackEvaluationService *fallback=m_kernel.FallbackEvaluation();
      if(fallback!=NULL)
         fallback.NotifyTick();

      CFastMarketEvaluationCoordinator *coordinator=m_kernel.FastCoordinator();
      if(coordinator==NULL)
         return 0;

      return coordinator.OnTick(symbol);
     }

   CVoidResult       OnApplicationTimer(int &commandsProcessed,int &eventsProcessed,int &evaluationsScheduled)
     {
      if(!m_initialized || m_kernel==NULL)
         return CVoidResult::Ok();

      if(m_executionTimeoutMonitor!=NULL)
         m_executionTimeoutMonitor.ScanDueTimeouts();
      if(m_executionReconciliationScheduler!=NULL)
         m_executionReconciliationScheduler.ProcessBatch();

      return m_kernel.TimerPipeline().OnTimer(commandsProcessed,eventsProcessed,evaluationsScheduled);
     }

   CVoidResult       OnRestPollTimer(void)
     {
      int commandsProcessed=0;
      int eventsProcessed=0;
      int evaluationsScheduled=0;
      return OnApplicationTimer(commandsProcessed,eventsProcessed,evaluationsScheduled);
     }

   int               ApplicationTimerIntervalMs(void) const
     {
      if(m_container==NULL)
         return 250;
      return m_container.EAConfiguration().ApplicationTimerIntervalMs();
     }

   int               RestPollIntervalMs(void) const
     {
      if(m_container==NULL)
         return 3000;
      int configured=m_container.EAConfiguration().RestPollIntervalMs();
      if(configured<=0)
         return 3000;
      return configured;
     }

   bool              IsRestIngestionConfigured(void) const
     {
      if(m_container==NULL)
         return false;
      return m_container.EAConfiguration().ApiBaseUrl()!="";
     }

   CApplicationKernel* Kernel(void) const { return m_kernel; }

   int               CommandQueuePendingCount(void) const
     {
      if(m_kernel==NULL)
         return 0;
      return m_kernel.PersistenceManager().CommandQueue().PendingCount();
     }

   void              LogFastPathDeinitSummary(void)
     {
      if(m_kernel==NULL)
         return;

      CFastPathDiagnosticReporter *reporter=m_kernel.DiagnosticReporter();
      CInMemoryHotPathDiagnostics *diagnostics=m_kernel.HotPathDiagnostics();
      if(reporter==NULL || diagnostics==NULL)
         return;

      int stagedCount=0;
      if(m_kernel.StagingQueue()!=NULL)
         stagedCount=m_kernel.StagingQueue().PendingCount();

      reporter.EmitDeinitSummary(*diagnostics,stagedCount);
     }

   void              LogShutdown(const int reason)
     {
      if(m_container==NULL)
         return;
      ILogger *logger=m_container.Logger();
      if(logger==NULL)
         return;
      logger.Info("SYSTEM","Shutdown","",StringFormat("BasketRecoveryEA stopped | reason=%d",reason));
     }

   CPendingExecutionTestInjectionService* PendingExecutionTestInjection(void) const { return m_pendingExecutionTestInjection; }
   CPendingExecutionRegistry* PendingExecutionRegistry(void) const { return m_pendingExecutionRegistry; }
   CRecoveryRiskEventBuffer* RecoveryRiskEventBuffer(void) const { return m_recoveryRiskEventBuffer; }
   CRecoveryDecisionRiskGateService* RecoveryRiskGateService(void) const { return m_recoveryRiskGateService; }
   CInMemoryPendingExecutionEventBuffer* PendingExecutionEventBuffer(void) const { return m_pendingExecutionEventBuffer; }
   CPendingExecutionDiagnostics* PendingExecutionDiagnostics(void) const { return m_pendingExecutionDiagnostics; }
   CExecutionSubmissionPreparer* SubmissionPreparer(void) const { return m_submissionPreparer; }
   IPendingExecutionStore* PendingExecutionStore(void) const { return m_pendingExecutionStore; }

   int               SnapshotCount(void) const
     {
      if(m_container==NULL)
         return 0;
      IPositionSnapshotStore *snapshotStore=m_container.SnapshotStore();
      if(snapshotStore==NULL)
         return 0;
      return snapshotStore.Count();
     }
  };

#endif
