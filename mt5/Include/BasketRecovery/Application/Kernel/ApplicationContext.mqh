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

   CVoidResult       TryProcessManualExecutionDryRun(const string basketIdValue,
                                                     const string triggerToken,
                                                     const double lotSize)
     {
      if(!m_initialized || m_executionDryRunManualService==NULL)
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Manual execution dry-run route is not configured");
      return m_executionDryRunManualService.TryProcessManualDryRunOpen(basketIdValue,triggerToken,lotSize);
     }

   bool              IsMt5ExecutorWiredToTimerPipeline(void) const { return false; }

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
