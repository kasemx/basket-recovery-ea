#ifndef BASKET_RECOVERY_INTERFACES_BOOTSTRAPPER_MQH
#define BASKET_RECOVERY_INTERFACES_BOOTSTRAPPER_MQH

#include <BasketRecovery/Application/Kernel/ApplicationContext.mqh>
#include <BasketRecovery/Application/Kernel/ApplicationKernel.mqh>
#include <BasketRecovery/Application/Kernel/ServiceContainer.mqh>
#include <BasketRecovery/Application/Configuration/ProfileSnapshotFactory.mqh>
#include <BasketRecovery/Infrastructure/Configuration/Mt5ConfigurationLoader.mqh>
#include <BasketRecovery/Infrastructure/Logging/FileLogger.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5Clock.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5UniqueIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Persistence/PersistenceManager.mqh>
#include <BasketRecovery/Infrastructure/Events/InMemoryEventBus.mqh>
#include <BasketRecovery/Infrastructure/TradeRequests/InMemoryTradeRequestQueue.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/BrokerReconciliationService.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/Mt5BrokerPositionReader.mqh>
#include <BasketRecovery/Infrastructure/Market/Mt5MarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Market/MarketContextProviderAdapter.mqh>
#include <BasketRecovery/Application/Services/BasketPositionReconciler.mqh>
#include <BasketRecovery/Application/Configuration/FastPathConfig.mqh>
#include <BasketRecovery/Application/Services/ReconciliationSchedulerService.mqh>
#include <BasketRecovery/Infrastructure/Configuration/DefaultProfileLoader.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestWebRequestClient.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestClient.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestClientConfig.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestCommandSource.mqh>
#include <BasketRecovery/Application/Services/CommandIngestionService.mqh>
#include <BasketRecovery/Application/Services/ExecutionDryRunManualCommandService.mqh>
#include <BasketRecovery/Application/Execution/ExecuteTradeIntentUseCase.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5TradeExecutor.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5OrderCheckGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5ExecutionDiagnostics.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionRequestRepository.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionJournal.mqh>
#include <BasketRecovery/Application/Kernel/TransitionRuleRegistry.mqh>
#include <BasketRecovery/Application/Kernel/DefaultTransitionRuleTable.mqh>
#include <BasketRecovery/Domain/StateMachine/AlwaysTrueTransitionGuard.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRestartService.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationPolicy.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionAuthorizationStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5AccountExecutionEligibilityProvider.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualDemoAuthorizationUseCase.mqh>
#include <BasketRecovery/Application/Execution/ManualDemoAuthorizationValidationService.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionValidationService.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionTriggerRegistry.mqh>
#include <BasketRecovery/Application/Execution/SubmitPreparedExecutionUseCase.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/IMt5AsyncOrderSendTransport.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionDiagnostics.mqh>
#include <BasketRecovery/Shared/Constants/FeatureFlags.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CBootstrapper
  {
public:
   static CApplicationContext* Bootstrap(const string profileName,
                                         const string logFilePath,
                                         const int logLevel,
                                         const string accountLabel,
                                         const string apiBaseUrl,
                                         const string apiKey,
                                         const int restPollIntervalMs,
                                         const int applicationTimerIntervalMs,
                                         const int maxBasketsPerTick,
                                         const int reconciliationIntervalMs,
                                         const int quoteStaleThresholdMs,
                                         const int maxSpreadPoints,
                                         const int maxEvaluationAgeMs,
                                         const int minEvaluationIntervalMs,
                                         const int materialQuoteChangePoints,
                                         const int tickSilenceFallbackMs,
                                         const bool enableFastPathDiagnostics,
                                         const int fastPathDiagnosticIntervalMs,
                                         const bool enableFastPathNoBasketHeartbeat,
                                         const int executionRuntimeMode,
                                         const bool enableExecutionDryRun,
                                         const bool enableExecutionDiagnostics,
                                         const bool enableLiveDemoExecution,
                                         const bool requireManualDemoAuthorization,
                                         const bool globalExecutionKillSwitch,
                                         const bool basketExecutionKillSwitch,
                                         const string basketExecutionKillSwitchBasketId,
                                         const int maxAuthorizedRequestsPerSession,
                                         const int authorizationTokenExpirySeconds,
                                         const double maxManualDemoOpenVolume)
     {
      CResult<CEAConfiguration> configurationResult=
         CMt5ConfigurationLoader::LoadFromInputs(profileName,logFilePath,logLevel,accountLabel,apiBaseUrl,apiKey,
                                                 restPollIntervalMs,applicationTimerIntervalMs,
                                                 maxBasketsPerTick,reconciliationIntervalMs,
                                                 quoteStaleThresholdMs,maxSpreadPoints,
                                                 maxEvaluationAgeMs,minEvaluationIntervalMs,
                                                 materialQuoteChangePoints,tickSilenceFallbackMs,
                                                 enableFastPathDiagnostics,fastPathDiagnosticIntervalMs,
                                                 enableFastPathNoBasketHeartbeat,
                                                 executionRuntimeMode,enableExecutionDryRun,enableExecutionDiagnostics,
                                                 enableLiveDemoExecution,requireManualDemoAuthorization,
                                                 globalExecutionKillSwitch,basketExecutionKillSwitch,
                                                 basketExecutionKillSwitchBasketId,
                                                 maxAuthorizedRequestsPerSession,authorizationTokenExpirySeconds,
                                                 maxManualDemoOpenVolume);

      if(configurationResult.IsFail())
        {
         Print("BasketRecovery bootstrap failed: ",configurationResult.ErrorMessage());
         return NULL;
        }

      CEAConfiguration configuration;
      if(!configurationResult.TryGetValue(configuration))
        {
         Print("BasketRecovery bootstrap failed: configuration result has no value");
         return NULL;
        }

      CFileLogger *logger=new CFileLogger();
      if(!logger.Initialize(configuration.LogFilePath(),configuration.LogLevel()))
        {
         delete logger;
         Print("BasketRecovery logger initialization failed");
         return NULL;
        }

      CMt5Clock *clock=new CMt5Clock();

      CDefaultProfileLoader *profileLoader=new CDefaultProfileLoader(clock);
      CResult<CProfileBundle> profileResult=profileLoader.LoadProfile(configuration.ProfileName());
      if(profileResult.IsFail())
        {
         logger.Error("SYSTEM","Bootstrap","","Profile load failed",profileResult.ErrorCode());
         delete profileLoader;
         delete clock;
         delete logger;
         return NULL;
        }

      CProfileBundle profileBundle;
      if(!profileResult.TryGetValue(profileBundle))
        {
         logger.Error("SYSTEM","Bootstrap","","Profile result has no value",BRE_ERR_PROFILE_LOAD_FAILED);
         delete profileLoader;
         delete clock;
         delete logger;
         return NULL;
        }

      CProfileSnapshot profileSnapshot=CProfileSnapshotFactory::FromBundle(profileBundle,*clock);

      int effectivePollIntervalMs=configuration.RestPollIntervalMs();
      if(effectivePollIntervalMs<=0)
         effectivePollIntervalMs=profileBundle.Execution().RestPollIntervalMs();
      configuration.SetRestPollIntervalMs(effectivePollIntervalMs);

      static CAlwaysTrueTransitionGuard s_defaultTransitionGuard;

      CTransitionRuleRegistry *transitionRuleRegistry=new CTransitionRuleRegistry();
      CVoidResult populateResult=
         CDefaultTransitionRuleTable::RegisterDefaultRules(*transitionRuleRegistry,&s_defaultTransitionGuard);
      if(populateResult.IsFail())
        {
         logger.Error("SYSTEM","Bootstrap","","Transition rule table population failed",populateResult.ErrorCode());
         delete transitionRuleRegistry;
         delete profileLoader;
         delete clock;
         delete logger;
         return NULL;
        }

      CVoidResult registryValidation=transitionRuleRegistry.Validate();
      if(registryValidation.IsFail())
        {
         logger.Error("SYSTEM","Bootstrap","","Transition registry validation failed",registryValidation.ErrorCode());
         delete transitionRuleRegistry;
         delete profileLoader;
         delete clock;
         delete logger;
         return NULL;
        }

      CInMemorySnapshotStore *snapshotStore=new CInMemorySnapshotStore(clock);
      CMt5MarketDataProvider *marketDataProvider=new CMt5MarketDataProvider(clock);
      CMarketContextProviderAdapter *marketContextProvider=
         new CMarketContextProviderAdapter(marketDataProvider,configuration.MarketSafetyConfig(),snapshotStore,true);

      CServiceContainer *container=new CServiceContainer();
      container.RegisterLogger(logger,true);
      container.RegisterClock(clock,true);
      container.RegisterEventBus(new CInMemoryEventBus(),true);
      container.RegisterTradeRequestQueue(new CInMemoryTradeRequestQueue(),true);
      container.RegisterSnapshotStore(snapshotStore,true);
      container.RegisterProfileLoader(profileLoader,true);
      container.RegisterTransitionRuleRegistry(transitionRuleRegistry,true);
      container.RegisterUniqueIdGenerator(new CMt5UniqueIdGenerator(),true);
      container.SetEAConfiguration(configuration);

      CPersistenceManager *persistenceManager=new CPersistenceManager(false,500);
      if(persistenceManager.RecoverOnStartup().IsFail())
        {
         delete marketContextProvider;
         delete persistenceManager;
         delete container;
         return NULL;
        }
      container.RegisterCommandQueue(persistenceManager.CommandQueue(),false);

      CMt5BrokerPositionReader *brokerPositionReader=new CMt5BrokerPositionReader();
      CBasketPositionReconciler *positionReconciler=
         new CBasketPositionReconciler(brokerPositionReader,snapshotStore,
                                       persistenceManager.BasketRepository(),logger,clock);
      CBrokerReconciliationService *reconciliationService=
         new CBrokerReconciliationService(brokerPositionReader,positionReconciler,true);
      container.RegisterReconciliationService(reconciliationService,true);

      CReconciliationSchedulerService *reconciliationScheduler=
         new CReconciliationSchedulerService(reconciliationService.Reconciler(),
                                             configuration.ReconciliationIntervalMs(),
                                             configuration.MaxBasketsPerReconcileCycle());

      CFastPathConfig fastPathConfig=CFastPathConfig::Create(configuration.MaxBasketsPerTick(),
                                                             configuration.MaxEvaluationAgeMs(),
                                                             configuration.MinEvaluationIntervalMs(),
                                                             configuration.MaterialQuoteChangePoints(),
                                                             configuration.TickSilenceFallbackMs(),
                                                             configuration.EnableFastPathDiagnostics(),
                                                             configuration.FastPathDiagnosticIntervalMs(),
                                                             configuration.EnableFastPathNoBasketHeartbeat());

      CRestClientConfig restConfig;
      restConfig.SetBaseUrl(configuration.ApiBaseUrl());
      restConfig.SetApiKey(configuration.ApiKey());
      restConfig.SetAccountId(configuration.AccountLogin());
      restConfig.SetMt5InstanceId(IntegerToString(configuration.AccountLogin())+"-"+configuration.AccountLabel());
      restConfig.SetTimeoutMs(5000);

      CRestClient *restClient=new CRestClient(new CRestWebRequestClient(restConfig.TimeoutMs()),true);
      CRestCommandSource *commandSource=new CRestCommandSource(restClient,restConfig,true);
      CCommandIngestionService *commandIngestionService=
         new CCommandIngestionService(commandSource,persistenceManager.CommandQueue(),logger);
      container.RegisterCommandSource(commandSource,true);
      container.RegisterCommandIngestionService(commandIngestionService,true);

      CVoidResult reconciliationResult=reconciliationService.ReconcileAtStartup();
      if(reconciliationResult.IsFail())
        {
         logger.Error("SYSTEM","Bootstrap","","Startup reconciliation failed",reconciliationResult.ErrorCode());
         delete reconciliationScheduler;
         delete marketContextProvider;
         delete persistenceManager;
         delete container;
         return NULL;
        }

      CApplicationKernel *kernel=new CApplicationKernel();
      if(!kernel.Initialize(transitionRuleRegistry,clock,container.UniqueIdGenerator(),
                             commandIngestionService,profileSnapshot,persistenceManager,
                             snapshotStore,marketContextProvider,reconciliationScheduler,
                             fastPathConfig,effectivePollIntervalMs,true))
        {
         delete kernel;
         delete reconciliationScheduler;
         delete marketContextProvider;
         delete persistenceManager;
         delete container;
         return NULL;
        }

      CApplicationContext *context=new CApplicationContext();
      if(!context.Initialize(container,kernel))
        {
         delete context;
         delete kernel;
         delete container;
         return NULL;
        }

      CInMemoryExecutionRequestRepository *executionRequestRepository=new CInMemoryExecutionRequestRepository();
      CInMemoryExecutionJournal *executionJournal=new CInMemoryExecutionJournal(executionRequestRepository);
      CMt5OrderCheckGateway *orderCheckGateway=new CMt5OrderCheckGateway();
      CMt5ExecutionDiagnostics *executionDiagnostics=
         new CMt5ExecutionDiagnostics(logger,configuration.EnableExecutionDiagnostics());
      CMt5TradeExecutor *mt5TradeExecutor=new CMt5TradeExecutor();
      mt5TradeExecutor.Configure(configuration.ExecutionRuntimeMode(),
                                 persistenceManager.BasketRepository(),
                                 marketDataProvider,
                                 orderCheckGateway,
                                 executionDiagnostics,
                                 configuration.MarketSafetyConfig(),
                                 configuration.EnableExecutionDryRun());
      CExecuteTradeIntentUseCase *executeTradeIntentUseCase=
         new CExecuteTradeIntentUseCase(persistenceManager.BasketRepository(),
                                        mt5TradeExecutor,
                                        executionJournal,
                                        executionRequestRepository,
                                        clock);
      CExecutionDryRunManualCommandService *manualDryRunService=new CExecutionDryRunManualCommandService();
      manualDryRunService.Configure(configuration.ExecutionRuntimeMode(),
                                    configuration.EnableExecutionDryRun(),
                                    configuration.EnableExecutionDiagnostics(),
                                    BRE_PERSISTENCE_BASKET_SUBDIR,
                                    executeTradeIntentUseCase,
                                    persistenceManager.BasketRepository(),
                                    container.EventBus(),
                                    container.UniqueIdGenerator(),
                                    logger);
      context.RegisterExecutionDryRunRuntime(manualDryRunService,
                                             mt5TradeExecutor,
                                             executeTradeIntentUseCase,
                                             executionRequestRepository,
                                             executionJournal,
                                             orderCheckGateway,
                                             executionDiagnostics);

      CPendingExecutionRegistry *pendingExecutionRegistry=new CPendingExecutionRegistry();
      CInMemoryPendingExecutionEventBuffer *pendingExecutionEventBuffer=
         new CInMemoryPendingExecutionEventBuffer(32);
      CPendingExecutionDiagnostics *pendingExecutionDiagnostics=
         new CPendingExecutionDiagnostics(logger,configuration.EnableExecutionDiagnostics(),64);
      CMt5BrokerPositionReader *executionReconciliationReader=new CMt5BrokerPositionReader();
      CExecutionReconciliationScheduler *executionReconciliationScheduler=
         new CExecutionReconciliationScheduler(pendingExecutionRegistry,executionReconciliationReader,
                                               pendingExecutionDiagnostics,8);
      CTradeTransactionRouter *tradeTransactionRouter=
         new CTradeTransactionRouter(pendingExecutionRegistry,
                                     pendingExecutionDiagnostics,
                                     pendingExecutionEventBuffer,
                                     kernel.FastStateRegistry(),
                                     clock);
      CExecutionTimeoutMonitor *executionTimeoutMonitor=
         new CExecutionTimeoutMonitor(pendingExecutionRegistry,
                                      executionReconciliationScheduler,
                                      pendingExecutionDiagnostics,
                                      clock);
      CPendingExecutionTestInjectionService *pendingExecutionTestInjection=
         new CPendingExecutionTestInjectionService(pendingExecutionRegistry,tradeTransactionRouter);
      context.RegisterPendingExecutionRuntime(pendingExecutionRegistry,
                                              pendingExecutionDiagnostics,
                                              pendingExecutionEventBuffer,
                                              tradeTransactionRouter,
                                              executionReconciliationScheduler,
                                              executionTimeoutMonitor,
                                              pendingExecutionTestInjection,
                                              executionReconciliationReader);

      CRecoveryRiskEventBuffer *recoveryRiskEventBuffer=new CRecoveryRiskEventBuffer(30000);
      CRecoveryDecisionRiskGateService *recoveryRiskGateService=
         new CRecoveryDecisionRiskGateService(snapshotStore,
                                              pendingExecutionRegistry,
                                              recoveryRiskEventBuffer,
                                              configuration.MarketSafetyConfig().QuoteStaleThresholdMs());
      kernel.ConfigureRecoveryRiskGate(recoveryRiskGateService);
      context.RegisterRecoveryRiskRuntime(recoveryRiskEventBuffer,recoveryRiskGateService);

      CRecoveryCandidateEventBuffer *recoveryCandidateEventBuffer=new CRecoveryCandidateEventBuffer();
      CRecoveryCandidatePlanningService *recoveryCandidatePlanningService=
         new CRecoveryCandidatePlanningService(snapshotStore,
                                               pendingExecutionRegistry,
                                               recoveryCandidateEventBuffer,
                                               configuration.MarketSafetyConfig().QuoteStaleThresholdMs());
      kernel.ConfigureRecoveryCandidatePlanning(recoveryCandidatePlanningService);
      context.RegisterRecoveryCandidateRuntime(recoveryCandidateEventBuffer,recoveryCandidatePlanningService);

      CFilePendingExecutionStore *pendingExecutionStore=
         new CFilePendingExecutionStore("BasketRecovery/pending_executions.dat");
      pendingExecutionStore.RestoreFromDisk();
      CSubmissionPreparationValidator preparationValidator(marketDataProvider,configuration.MarketSafetyConfig());
      CExecutionSubmissionPreparer *submissionPreparer=
         new CExecutionSubmissionPreparer(CSubmissionPreparationPolicy::Default(),
                                          preparationValidator,
                                          pendingExecutionRegistry,
                                          pendingExecutionStore,
                                          clock);
      submissionPreparer.ConfigureRiskReadModel(snapshotStore,marketDataProvider);
      string restartWarnings[];
      CPendingExecutionRestartService::RestorePreparedEntries(pendingExecutionStore,
                                                              pendingExecutionRegistry,
                                                              restartWarnings);
      context.RegisterSubmissionPreparationRuntime(submissionPreparer,pendingExecutionStore);
      // Sprint 6E: CSimulatedSubmissionGateway / CSubmitPreparedExecutionUseCase remain test-only.
      // CSubmissionGatewayCompositionGuard blocks bootstrap auto-wire of simulated gateways.

      CInMemoryExecutionAuthorizationStore *authorizationStore=new CInMemoryExecutionAuthorizationStore();
      CExecutionAuthorizationRegistry *authorizationRegistry=new CExecutionAuthorizationRegistry(authorizationStore);
      authorizationRegistry.RestoreFromStore();
      CMt5AccountExecutionEligibilityProvider *accountEligibilityProvider=new CMt5AccountExecutionEligibilityProvider();
      CManualDemoAuthorizationUseCase *demoAuthorizationUseCase=
         new CManualDemoAuthorizationUseCase(configuration.DemoAuthorizationConfig(),
                                             authorizationRegistry,
                                             pendingExecutionRegistry,
                                             pendingExecutionStore,
                                             accountEligibilityProvider,
                                             clock,
                                             configuration.MarketSafetyConfig());
      CManualDemoAuthorizationValidationService *demoAuthorizationValidationService=
         new CManualDemoAuthorizationValidationService();
      demoAuthorizationValidationService.Configure(configuration.DemoAuthorizationConfig(),
                                                   demoAuthorizationUseCase,
                                                   persistenceManager.BasketRepository(),
                                                   marketDataProvider);
      context.RegisterDemoAuthorizationRuntime(demoAuthorizationValidationService,
                                               demoAuthorizationUseCase,
                                               authorizationRegistry,
                                               authorizationStore,
                                               accountEligibilityProvider);
      // Sprint 6F: authorization evaluates safety gates only; no submission gateway is wired.

      CMt5AsyncSubmissionDiagnostics *asyncSubmissionDiagnostics=
         new CMt5AsyncSubmissionDiagnostics(logger,configuration.EnableExecutionDiagnostics(),64);
      CMt5LiveAsyncOrderSendTransport *liveAsyncTransport=new CMt5LiveAsyncOrderSendTransport();
      CMt5AsyncSubmissionGateway *asyncSubmissionGateway=
         new CMt5AsyncSubmissionGateway(liveAsyncTransport,asyncSubmissionDiagnostics,10);
      CSubmitPreparedExecutionUseCase *submitPreparedExecutionUseCase=
         new CSubmitPreparedExecutionUseCase(pendingExecutionRegistry,
                                             asyncSubmissionGateway,
                                             pendingExecutionStore,
                                             clock,
                                             NULL);
      CDemoManualSubmissionTriggerRegistry *demoSubmissionTriggerRegistry=
         new CDemoManualSubmissionTriggerRegistry();
      CDemoManualSubmissionService *demoManualSubmissionService=
         new CDemoManualSubmissionService(configuration.DemoAuthorizationConfig(),
                                          authorizationRegistry,
                                          demoSubmissionTriggerRegistry,
                                          pendingExecutionRegistry,
                                          pendingExecutionStore,
                                          accountEligibilityProvider,
                                          clock,
                                          submitPreparedExecutionUseCase,
                                          asyncSubmissionGateway,
                                          configuration.MarketSafetyConfig());
      CDemoManualSubmissionValidationService *demoManualSubmissionValidationService=
         new CDemoManualSubmissionValidationService();
      demoManualSubmissionValidationService.Configure(configuration.DemoAuthorizationConfig(),
                                                      demoManualSubmissionService,
                                                      persistenceManager.BasketRepository(),
                                                      marketDataProvider,
                                                      snapshotStore);
      context.RegisterDemoManualSubmissionRuntime(demoManualSubmissionValidationService,
                                                demoManualSubmissionService,
                                                demoSubmissionTriggerRegistry,
                                                submitPreparedExecutionUseCase,
                                                asyncSubmissionGateway,
                                                asyncSubmissionDiagnostics,
                                                liveAsyncTransport);
      // Sprint 6G: OrderSendAsync exists only in CMt5AsyncSubmissionGateway; manual route only.

      CFastPathDiagnosticReporter *diagnosticReporter=kernel.DiagnosticReporter();
      if(diagnosticReporter!=NULL)
        {
         int symbolIndexCount=0;
         if(kernel.SymbolIndex()!=NULL)
            symbolIndexCount=kernel.SymbolIndex().TotalActiveBasketCount();
         diagnosticReporter.EmitStartupLine(symbolIndexCount,configuration.MaxBasketsPerTick());
        }

      logger.Info("SYSTEM","Startup",
                  "",
                  StringFormat("BasketRecoveryEA initialized | profile=%s | profile_snapshot=%s | account=%I64d | label=%s | transition_rules=%d | snapshots=%d | rest=%s | rest_poll_ms=%d | fast_path_tick_budget=%d | reconciliation_ms=%d | features=signals:%s",
                               configuration.ProfileName(),
                               profileSnapshot.ProfileName(),
                               configuration.AccountLogin(),
                               configuration.AccountLabel(),
                               transitionRuleRegistry.RuleCount(),
                               context.SnapshotCount(),
                               configuration.ApiBaseUrl()=="" ? "disabled" : configuration.ApiBaseUrl(),
                               effectivePollIntervalMs,
                               configuration.MaxBasketsPerTick(),
                               configuration.ReconciliationIntervalMs(),
                               BRE_FEATURE_SIGNALS ? "on" : "off"));

      return context;
     }
  };

#endif
