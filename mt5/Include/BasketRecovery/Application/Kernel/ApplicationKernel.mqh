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
#include <BasketRecovery/Application/Services/StrategyEvaluationScheduler.mqh>
#include <BasketRecovery/Application/Ports/IStrategyEngine.mqh>
#include <BasketRecovery/Infrastructure/Market/InMemoryMarketQuoteProvider.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>

class CApplicationKernel
  {
private:
   CPersistenceManager              *m_persistenceManager;
   CCommandDispatcher               *m_commandDispatcher;
   CEventDispatcher                 *m_eventDispatcher;
   CCommandProcessor                *m_commandProcessor;
   CApplicationTimerPipeline      *m_timerPipeline;
   CStrategyEvaluationScheduler     *m_strategyScheduler;
   CEvaluateBasketStrategyUseCase   *m_evaluateUseCase;
   CBindMigratedBasketStrategyUseCase *m_bindMigrationUseCase;
   CTransitionEngine                *m_transitionEngine;
   CStateTransitionHandler          *m_transitionHandler;
   CStrategyEngineAdapter           *m_strategyEngine;
   CInMemoryMarketQuoteProvider     *m_marketProvider;
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
      m_strategyScheduler=NULL;
      m_evaluateUseCase=NULL;
      m_bindMigrationUseCase=NULL;
      m_transitionEngine=NULL;
      m_transitionHandler=NULL;
      m_strategyEngine=NULL;
      m_marketProvider=NULL;
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
      if(m_marketProvider!=NULL) delete m_marketProvider;
      if(m_strategyEngine!=NULL) delete m_strategyEngine;
      if(m_transitionHandler!=NULL) delete m_transitionHandler;
      if(m_transitionEngine!=NULL) delete m_transitionEngine;
      if(m_bindMigrationUseCase!=NULL) delete m_bindMigrationUseCase;
      if(m_evaluateUseCase!=NULL) delete m_evaluateUseCase;
      if(m_strategyScheduler!=NULL) delete m_strategyScheduler;
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
                                const int restPollIntervalMs,
                                const int strategyEvalIntervalMs,
                                const int maxBasketsPerEvalCycle)
     {
      if(persistenceManager==NULL)
         return false;
      m_persistenceManager=persistenceManager;

      m_commandDispatcher=new CCommandDispatcher();
      m_eventDispatcher=new CEventDispatcher();
      m_transitionEngine=new CTransitionEngine(registry);
      m_transitionHandler=new CStateTransitionHandler(m_transitionEngine);
      m_strategyEngine=new CStrategyEngineAdapter();
      m_marketProvider=new CInMemoryMarketQuoteProvider();

      IBasketRepository *repository=m_persistenceManager.BasketRepository();
      m_evaluateUseCase=new CEvaluateBasketStrategyUseCase(repository,m_strategyEngine,
                                                           m_persistenceManager.CommandQueue(),
                                                           clock,idGenerator);
      m_bindMigrationUseCase=new CBindMigratedBasketStrategyUseCase(repository,clock,idGenerator);

      m_createHandler=new CCreateBasketCommandHandler(repository,clock,idGenerator,profileSnapshot);
      m_activateHandler=new CActivateBasketCommandHandler(repository,m_transitionHandler,clock,idGenerator);
      m_closeHandler=new CCloseBasketCommandHandler(repository,m_transitionHandler,clock,idGenerator);
      m_evaluateHandler=new CEvaluateStrategyCommandHandler(m_evaluateUseCase,m_marketProvider);
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
      m_strategyScheduler=new CStrategyEvaluationScheduler(repository,m_persistenceManager.CommandQueue(),
                                                           clock,idGenerator,strategyEvalIntervalMs,
                                                           maxBasketsPerEvalCycle);
      m_timerPipeline=new CApplicationTimerPipeline(ingestionService,m_commandProcessor,
                                                    m_persistenceManager,m_strategyScheduler,
                                                    restPollIntervalMs);
      return true;
     }

   CApplicationTimerPipeline* TimerPipeline(void) { return m_timerPipeline; }
   CPersistenceManager*       PersistenceManager(void) { return m_persistenceManager; }
   CBindMigratedBasketStrategyUseCase* BindMigrationUseCase(void) { return m_bindMigrationUseCase; }
   CInMemoryMarketQuoteProvider* MarketProvider(void) { return m_marketProvider; }
  };

#endif
