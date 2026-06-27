#ifndef BASKET_RECOVERY_APPLICATION_APPLICATION_KERNEL_MQH
#define BASKET_RECOVERY_APPLICATION_APPLICATION_KERNEL_MQH

#include <BasketRecovery/Application/Kernel/CommandDispatcher.mqh>
#include <BasketRecovery/Application/Kernel/EventDispatcher.mqh>
#include <BasketRecovery/Application/Kernel/CommandProcessor.mqh>
#include <BasketRecovery/Application/Kernel/ApplicationTimerPipeline.mqh>
#include <BasketRecovery/Application/Kernel/KernelHandlerRegistration.mqh>
#include <BasketRecovery/Application/Kernel/TransitionEngine.mqh>
#include <BasketRecovery/Application/Handlers/StateTransitionHandler.mqh>
#include <BasketRecovery/Infrastructure/Persistence/PersistenceManager.mqh>
#include <BasketRecovery/Application/UseCases/EvaluateBasketStrategyUseCase.mqh>
#include <BasketRecovery/Application/UseCases/BindMigratedBasketStrategyUseCase.mqh>
#include <BasketRecovery/Application/Services/ReconciliationSchedulerService.mqh>
#include <BasketRecovery/Application/Services/FastMarketEvaluationCoordinator.mqh>
#include <BasketRecovery/Application/Services/TradeTransactionFastPathService.mqh>
#include <BasketRecovery/Application/Services/TimerFallbackEvaluationService.mqh>
#include <BasketRecovery/Application/Services/SystemHealthCheckService.mqh>
#include <BasketRecovery/Application/FastPath/BasketFastStateRegistry.mqh>
#include <BasketRecovery/Application/FastPath/SymbolBasketIndex.mqh>
#include <BasketRecovery/Application/FastPath/FastEvaluationTriggerPolicy.mqh>
#include <BasketRecovery/Application/FastPath/FastCommandStagingBuffer.mqh>
#include <BasketRecovery/Application/FastPath/InMemoryHotPathDiagnostics.mqh>
#include <BasketRecovery/Application/FastPath/InMemoryFastSafetyAuditBuffer.mqh>
#include <BasketRecovery/Application/FastPath/FastPathDiagnosticReporter.mqh>
#include <BasketRecovery/Application/Configuration/FastPathConfig.mqh>
#include <BasketRecovery/Application/Ports/IStrategyEngine.mqh>
#include <BasketRecovery/Application/Ports/IMarketContextProvider.mqh>
#include <BasketRecovery/Infrastructure/Market/MarketContextProviderAdapter.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>

class CApplicationKernel
  {
private:
   CPersistenceManager              *m_persistenceManager;
   CCommandDispatcher               *m_commandDispatcher;
   CEventDispatcher                 *m_eventDispatcher;
   CCommandProcessor                *m_commandProcessor;
   CApplicationTimerPipeline        *m_timerPipeline;
   CReconciliationSchedulerService  *m_reconciliationScheduler;
   CFastMarketEvaluationCoordinator *m_fastCoordinator;
   CTradeTransactionFastPathService *m_tradeTransactionFastPath;
   CTimerFallbackEvaluationService  *m_fallbackEvaluation;
   CSystemHealthCheckService        *m_healthCheck;
   CBasketFastStateRegistry         *m_fastStateRegistry;
   CSymbolBasketIndex               *m_symbolIndex;
   CFastEvaluationTriggerPolicy     *m_triggerPolicy;
   CFastCommandStagingBuffer        *m_stagingQueue;
   CInMemoryHotPathDiagnostics      *m_hotPathDiagnostics;
   CInMemoryFastSafetyAuditBuffer   *m_safetyAudit;
   CFastPathDiagnosticReporter      *m_diagnosticReporter;
   CFastPathConfig                   m_fastPathConfig;
   CEvaluateBasketStrategyUseCase   *m_evaluateUseCase;
   CBindMigratedBasketStrategyUseCase *m_bindMigrationUseCase;
   CTransitionEngine                *m_transitionEngine;
   CStateTransitionHandler          *m_transitionHandler;
   CStrategyEngineAdapter           *m_strategyEngine;
   CMarketContextProviderAdapter    *m_marketAdapter;
   bool                              m_ownsMarketAdapter;
   CCreateBasketCommandHandler      *m_createHandler;
   CActivateBasketCommandHandler    *m_activateHandler;
   CCloseBasketCommandHandler       *m_closeHandler;
   CEvaluateStrategyCommandHandler  *m_evaluateHandler;
   COpenRecoveryPositionCommandHandler *m_openRecoveryHandler;
   CClosePositionsCommandHandler    *m_closePositionsHandler;
   CMoveBasketStopLossCommandHandler *m_moveStopHandler;
   CReduceBasketRiskCommandHandler  *m_reduceRiskHandler;
   CDisableRecoveryCommandHandler   *m_disableRecoveryHandler;
   CMarkProfitLevelCompletedCommandHandler *m_markProfitHandler;
   CProfitLevelReachedEventHandler  *m_profitReachedHandler;
   CProfitLevelCloseRequestedEventHandler *m_closeRequestedHandler;
   CProfitLevelCloseCompletedEventHandler *m_closeCompletedHandler;
   CBreakEvenActivatedEventHandler  *m_breakEvenHandler;
   CRecoveryDisabledEventHandler    *m_recoveryDisabledHandler;
   CRiskReductionRequestedEventHandler *m_riskReductionHandler;
   CBasketLockedEventHandler        *m_lockedHandler;
   CStrategyProfileBoundEventHandler *m_profileBoundHandler;

public:
                     CApplicationKernel(void)
     {
      m_persistenceManager=NULL;
      m_commandDispatcher=NULL;
      m_eventDispatcher=NULL;
      m_commandProcessor=NULL;
      m_timerPipeline=NULL;
      m_reconciliationScheduler=NULL;
      m_fastCoordinator=NULL;
      m_tradeTransactionFastPath=NULL;
      m_fallbackEvaluation=NULL;
      m_healthCheck=NULL;
      m_fastStateRegistry=NULL;
      m_symbolIndex=NULL;
      m_triggerPolicy=NULL;
      m_stagingQueue=NULL;
      m_hotPathDiagnostics=NULL;
      m_safetyAudit=NULL;
      m_diagnosticReporter=NULL;
      m_evaluateUseCase=NULL;
      m_bindMigrationUseCase=NULL;
      m_transitionEngine=NULL;
      m_transitionHandler=NULL;
      m_strategyEngine=NULL;
      m_marketAdapter=NULL;
      m_ownsMarketAdapter=false;
      m_createHandler=NULL;
      m_activateHandler=NULL;
      m_closeHandler=NULL;
      m_evaluateHandler=NULL;
      m_openRecoveryHandler=NULL;
      m_closePositionsHandler=NULL;
      m_moveStopHandler=NULL;
      m_reduceRiskHandler=NULL;
      m_disableRecoveryHandler=NULL;
      m_markProfitHandler=NULL;
      m_profitReachedHandler=NULL;
      m_closeRequestedHandler=NULL;
      m_closeCompletedHandler=NULL;
      m_breakEvenHandler=NULL;
      m_recoveryDisabledHandler=NULL;
      m_riskReductionHandler=NULL;
      m_lockedHandler=NULL;
      m_profileBoundHandler=NULL;
     }

                    ~CApplicationKernel(void)
     {
      if(m_profileBoundHandler!=NULL) delete m_profileBoundHandler;
      if(m_lockedHandler!=NULL) delete m_lockedHandler;
      if(m_riskReductionHandler!=NULL) delete m_riskReductionHandler;
      if(m_recoveryDisabledHandler!=NULL) delete m_recoveryDisabledHandler;
      if(m_breakEvenHandler!=NULL) delete m_breakEvenHandler;
      if(m_closeCompletedHandler!=NULL) delete m_closeCompletedHandler;
      if(m_closeRequestedHandler!=NULL) delete m_closeRequestedHandler;
      if(m_profitReachedHandler!=NULL) delete m_profitReachedHandler;
      if(m_markProfitHandler!=NULL) delete m_markProfitHandler;
      if(m_disableRecoveryHandler!=NULL) delete m_disableRecoveryHandler;
      if(m_reduceRiskHandler!=NULL) delete m_reduceRiskHandler;
      if(m_moveStopHandler!=NULL) delete m_moveStopHandler;
      if(m_closePositionsHandler!=NULL) delete m_closePositionsHandler;
      if(m_openRecoveryHandler!=NULL) delete m_openRecoveryHandler;
      if(m_evaluateHandler!=NULL) delete m_evaluateHandler;
      if(m_closeHandler!=NULL) delete m_closeHandler;
      if(m_activateHandler!=NULL) delete m_activateHandler;
      if(m_createHandler!=NULL) delete m_createHandler;
      if(m_ownsMarketAdapter && m_marketAdapter!=NULL) delete m_marketAdapter;
      if(m_strategyEngine!=NULL) delete m_strategyEngine;
      if(m_transitionHandler!=NULL) delete m_transitionHandler;
      if(m_transitionEngine!=NULL) delete m_transitionEngine;
      if(m_bindMigrationUseCase!=NULL) delete m_bindMigrationUseCase;
      if(m_evaluateUseCase!=NULL) delete m_evaluateUseCase;
      if(m_safetyAudit!=NULL) delete m_safetyAudit;
      if(m_diagnosticReporter!=NULL) delete m_diagnosticReporter;
      if(m_hotPathDiagnostics!=NULL) delete m_hotPathDiagnostics;
      if(m_stagingQueue!=NULL) delete m_stagingQueue;
      if(m_triggerPolicy!=NULL) delete m_triggerPolicy;
      if(m_symbolIndex!=NULL) delete m_symbolIndex;
      if(m_fastStateRegistry!=NULL) delete m_fastStateRegistry;
      if(m_healthCheck!=NULL) delete m_healthCheck;
      if(m_fallbackEvaluation!=NULL) delete m_fallbackEvaluation;
      if(m_tradeTransactionFastPath!=NULL) delete m_tradeTransactionFastPath;
      if(m_fastCoordinator!=NULL) delete m_fastCoordinator;
      if(m_reconciliationScheduler!=NULL) delete m_reconciliationScheduler;
      if(m_timerPipeline!=NULL) delete m_timerPipeline;
      if(m_commandProcessor!=NULL) delete m_commandProcessor;
      if(m_eventDispatcher!=NULL) delete m_eventDispatcher;
      if(m_commandDispatcher!=NULL) delete m_commandDispatcher;
      if(m_persistenceManager!=NULL) delete m_persistenceManager;
     }

   bool              Initialize(ITransitionRuleRegistry *registry,
                                IClock *clock,
                                IUniqueIdGenerator *idGenerator,
                                CCommandIngestionService *ingestionService,
                                const CProfileSnapshot &profileSnapshot,
                                CPersistenceManager *persistenceManager,
                                IPositionSnapshotStore *snapshotStore,
                                CMarketContextProviderAdapter *marketAdapter,
                                CReconciliationSchedulerService *reconciliationScheduler,
                                const CFastPathConfig &fastPathConfig,
                                const int restPollIntervalMs,
                                const bool takeMarketAdapterOwnership=false)
     {
      if(persistenceManager==NULL)
         return false;
      m_persistenceManager=persistenceManager;
      m_marketAdapter=marketAdapter;
      m_ownsMarketAdapter=takeMarketAdapterOwnership;
      m_reconciliationScheduler=reconciliationScheduler;
      m_fastPathConfig=fastPathConfig;

      m_fastStateRegistry=new CBasketFastStateRegistry();
      m_symbolIndex=new CSymbolBasketIndex();
      m_stagingQueue=new CFastCommandStagingBuffer();
      m_hotPathDiagnostics=new CInMemoryHotPathDiagnostics();
      m_safetyAudit=new CInMemoryFastSafetyAuditBuffer();
      m_diagnosticReporter=new CFastPathDiagnosticReporter(fastPathConfig);
      m_triggerPolicy=new CFastEvaluationTriggerPolicy(fastPathConfig);

      m_commandDispatcher=new CCommandDispatcher();
      m_eventDispatcher=new CEventDispatcher();
      m_transitionEngine=new CTransitionEngine(registry);
      m_transitionHandler=new CStateTransitionHandler(m_transitionEngine);
      m_strategyEngine=new CStrategyEngineAdapter();

      IBasketRepository *repository=m_persistenceManager.BasketRepository();
      m_evaluateUseCase=new CEvaluateBasketStrategyUseCase(repository,m_strategyEngine,
                                                           m_persistenceManager.CommandQueue(),
                                                           clock,idGenerator,snapshotStore);
      m_bindMigrationUseCase=new CBindMigratedBasketStrategyUseCase(repository,clock,idGenerator);

      m_fastCoordinator=new CFastMarketEvaluationCoordinator(repository,snapshotStore,m_evaluateUseCase,
                                                             m_marketAdapter,m_stagingQueue,
                                                             m_fastStateRegistry,m_symbolIndex,
                                                             m_triggerPolicy,m_hotPathDiagnostics,
                                                             m_safetyAudit,m_diagnosticReporter,
                                                             clock,fastPathConfig);
      m_tradeTransactionFastPath=new CTradeTransactionFastPathService(snapshotStore,m_fastStateRegistry,
                                                                      m_symbolIndex);
      m_fallbackEvaluation=new CTimerFallbackEvaluationService(repository,m_marketAdapter,m_evaluateUseCase,
                                                             m_stagingQueue,m_symbolIndex,fastPathConfig);
      m_healthCheck=new CSystemHealthCheckService(m_hotPathDiagnostics);

      m_symbolIndex.Rebuild(repository);

      m_createHandler=new CCreateBasketCommandHandler(repository,clock,idGenerator,profileSnapshot);
      m_activateHandler=new CActivateBasketCommandHandler(repository,m_transitionHandler,clock,idGenerator);
      m_closeHandler=new CCloseBasketCommandHandler(repository,m_transitionHandler,clock,idGenerator);
      m_evaluateHandler=new CEvaluateStrategyCommandHandler(m_evaluateUseCase,m_marketAdapter);
      m_openRecoveryHandler=new COpenRecoveryPositionCommandHandler(repository,clock);
      m_closePositionsHandler=new CClosePositionsCommandHandler(repository,clock);
      m_moveStopHandler=new CMoveBasketStopLossCommandHandler(repository,clock);
      m_reduceRiskHandler=new CReduceBasketRiskCommandHandler(repository,clock);
      m_disableRecoveryHandler=new CDisableRecoveryCommandHandler(repository,clock,idGenerator);
      m_markProfitHandler=new CMarkProfitLevelCompletedCommandHandler(repository,clock,idGenerator);

      CKernelHandlerRegistration::RegisterCommandHandlers(*m_commandDispatcher,
         m_createHandler,m_activateHandler,m_closeHandler,m_evaluateHandler,
         m_openRecoveryHandler,m_closePositionsHandler,m_moveStopHandler,m_reduceRiskHandler,
         m_disableRecoveryHandler,m_markProfitHandler);

      m_profitReachedHandler=new CProfitLevelReachedEventHandler(repository,clock,idGenerator);
      m_closeRequestedHandler=new CProfitLevelCloseRequestedEventHandler(repository,clock,idGenerator);
      m_closeCompletedHandler=new CProfitLevelCloseCompletedEventHandler(repository,clock,idGenerator);
      m_breakEvenHandler=new CBreakEvenActivatedEventHandler(repository,clock,idGenerator);
      m_recoveryDisabledHandler=new CRecoveryDisabledEventHandler(repository,clock,idGenerator);
      m_riskReductionHandler=new CRiskReductionRequestedEventHandler(repository,clock,idGenerator);
      m_lockedHandler=new CBasketLockedEventHandler(repository,clock,idGenerator);
      m_profileBoundHandler=new CStrategyProfileBoundEventHandler(repository,clock,idGenerator);

      CKernelHandlerRegistration::RegisterStrategyEventHandlers(*m_eventDispatcher,
         m_profitReachedHandler,m_closeRequestedHandler,m_closeCompletedHandler,m_breakEvenHandler,
         m_recoveryDisabledHandler,m_riskReductionHandler,m_lockedHandler,m_profileBoundHandler);

      m_commandProcessor=new CCommandProcessor(m_persistenceManager.CommandQueue(),
                                               m_commandDispatcher,m_eventDispatcher,
                                               m_persistenceManager.IdempotencyStore());
      m_timerPipeline=new CApplicationTimerPipeline(ingestionService,m_commandProcessor,
                                                    m_persistenceManager,m_reconciliationScheduler,
                                                    m_fallbackEvaluation,m_healthCheck,m_stagingQueue,
                                                    restPollIntervalMs);
      return true;
     }

   CApplicationTimerPipeline* TimerPipeline(void) { return m_timerPipeline; }
   CFastMarketEvaluationCoordinator* FastCoordinator(void) { return m_fastCoordinator; }
   CFastPathDiagnosticReporter* DiagnosticReporter(void) { return m_diagnosticReporter; }
   CInMemoryHotPathDiagnostics* HotPathDiagnostics(void) { return m_hotPathDiagnostics; }
   CFastCommandStagingBuffer* StagingQueue(void) { return m_stagingQueue; }
   CSymbolBasketIndex* SymbolIndex(void) { return m_symbolIndex; }
   CFastPathConfig    FastPathConfig(void) const { return m_fastPathConfig; }
   CTimerFallbackEvaluationService* FallbackEvaluation(void) { return m_fallbackEvaluation; }
   CTradeTransactionFastPathService* TradeTransactionFastPath(void) { return m_tradeTransactionFastPath; }
   CBasketFastStateRegistry*       FastStateRegistry(void) { return m_fastStateRegistry; }
   CPersistenceManager*       PersistenceManager(void) { return m_persistenceManager; }
   CBindMigratedBasketStrategyUseCase* BindMigrationUseCase(void) { return m_bindMigrationUseCase; }
   CMarketContextProviderAdapter* MarketAdapter(void) { return m_marketAdapter; }
  };

#endif
