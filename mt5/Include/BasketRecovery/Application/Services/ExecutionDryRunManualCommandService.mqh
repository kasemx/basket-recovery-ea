#ifndef BRE_APP_EXECUTION_DRY_RUN_MANUAL_COMMAND_SERVICE_MQH
#define BRE_APP_EXECUTION_DRY_RUN_MANUAL_COMMAND_SERVICE_MQH

#include <BasketRecovery/Application/Execution/ExecutionDryRunGate.mqh>
#include <BasketRecovery/Application/Execution/ExecuteTradeIntentUseCase.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IEventBus.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Ports/ILogger.mqh>
#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>
#include <BasketRecovery/Domain/Events/ExecutionDomainEvent.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketPersistenceLoadDiagnostic.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CExecutionDryRunManualCommandService
  {
private:
   ENUM_BRE_EXECUTION_RUNTIME_MODE m_mode;
   bool                            m_enableExecutionDryRun;
   bool                            m_enableExecutionDiagnostics;
   string                          m_basketPersistenceSubdir;
   CExecuteTradeIntentUseCase     *m_useCase;
   IBasketRepository              *m_basketRepository;
   IEventBus                      *m_eventBus;
   IUniqueIdGenerator             *m_idGenerator;
   ILogger                        *m_logger;
   string                          m_lastProcessedTriggerToken;
   bool                            m_basketLoadDiagnosticEmitted;

   bool              IsGateOpen(void) const
     {
      return CExecutionDryRunGate::IsDryRunRouteEnabled(m_mode,m_enableExecutionDryRun);
     }

   void              EmitBasketLoadDiagnosticOnce(const string basketIdValue)
     {
      if(!m_enableExecutionDiagnostics || m_basketLoadDiagnosticEmitted || basketIdValue=="")
         return;

      CFileBasketRepository repository(m_basketPersistenceSubdir);
      CBasketPersistenceLoadDiagnostic report=
         CBasketPersistenceLoadDiagnostic::Inspect(m_basketPersistenceSubdir,CBasketId(basketIdValue),repository);
      string line=CBasketPersistenceLoadDiagnostic::FormatLogLine(report);
      Print(line);
      if(m_logger!=NULL)
         m_logger.Info("EXECUTION","BasketLoadDiagnostic","",line);
      m_basketLoadDiagnosticEmitted=true;
     }

public:
                     CExecutionDryRunManualCommandService(void)
     {
      m_mode=BRE_EXEC_RUNTIME_DISABLED;
      m_enableExecutionDryRun=false;
      m_enableExecutionDiagnostics=false;
      m_basketPersistenceSubdir=BRE_PERSISTENCE_BASKET_SUBDIR;
      m_useCase=NULL;
      m_basketRepository=NULL;
      m_eventBus=NULL;
      m_idGenerator=NULL;
      m_logger=NULL;
      m_lastProcessedTriggerToken="";
      m_basketLoadDiagnosticEmitted=false;
     }

   void              Configure(const ENUM_BRE_EXECUTION_RUNTIME_MODE mode,
                               const bool enableExecutionDryRun,
                               const bool enableExecutionDiagnostics,
                               const string basketPersistenceSubdir,
                               CExecuteTradeIntentUseCase *useCase,
                               IBasketRepository *basketRepository,
                               IEventBus *eventBus,
                               IUniqueIdGenerator *idGenerator,
                               ILogger *logger)
     {
      m_mode=mode;
      m_enableExecutionDryRun=enableExecutionDryRun;
      m_enableExecutionDiagnostics=enableExecutionDiagnostics;
      if(basketPersistenceSubdir!="")
         m_basketPersistenceSubdir=basketPersistenceSubdir;
      m_useCase=useCase;
      m_basketRepository=basketRepository;
      m_eventBus=eventBus;
      m_idGenerator=idGenerator;
      m_logger=logger;
     }

   bool              BasketLoadDiagnosticEmitted(void) const { return m_basketLoadDiagnosticEmitted; }

   CVoidResult       TryProcessManualDryRunOpen(const string basketIdValue,
                                                const string triggerToken,
                                                const double lotSize)
     {
      if(basketIdValue=="")
         return CVoidResult::Ok();

      if(m_enableExecutionDiagnostics)
         EmitBasketLoadDiagnosticOnce(basketIdValue);

      if(triggerToken!="" && triggerToken!="0")
        {
         if(m_logger!=NULL && m_enableExecutionDiagnostics)
            m_logger.Info("EXECUTION","ChartValidation","",
                          StringFormat("BRE chart-validation | broker_state_before | positions=%d | orders=%d | no_ordersend=true",
                                       PositionsTotal(),OrdersTotal()));
        }

      if(triggerToken=="" || triggerToken=="0")
         return CVoidResult::Ok();

      if(triggerToken==m_lastProcessedTriggerToken)
         return CVoidResult::Ok();

      if(!IsGateOpen())
        {
         if(m_logger!=NULL)
            m_logger.Warn("EXECUTION","ManualDryRun","","Manual dry-run rejected | execution gate closed",BRE_ERR_EXEC_DISABLED);
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Manual dry-run requires MT5_DRY_RUN and EnableExecutionDryRun");
        }

      if(m_useCase==NULL || m_basketRepository==NULL)
         return CVoidResult::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Manual dry-run use case is not configured");

      if(basketIdValue=="")
         return CVoidResult::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Manual dry-run basket id is required");

      CResult<CBasketAggregate> loaded=m_basketRepository.Load(CBasketId(basketIdValue));
      if(loaded.IsFail())
         return CVoidResult::Fail(loaded.ErrorCode(),loaded.ErrorMessage());

      CBasketAggregate basket;
      loaded.TryGetValue(basket);

      string executionRequestId=(m_idGenerator!=NULL) ?
                                m_idGenerator.NewGuid() :
                                "exec-manual-"+IntegerToString(GetTickCount());

      COpenRecoveryPositionCommand command;
      command.SetId(CCommandId("cmd-manual-dryrun"));
      command.SetBasketId(basket.Id());
      command.SetExpectedBasketVersion(basket.Version());
      command.SetStrategyProfileHash(basket.StrategyProfileHash());
      command.SetIdempotencyKey("manual:dryrun:"+triggerToken);
      command.SetCorrelationKey("manual-dryrun");
      command.SetLotSize(lotSize);

      CResult<CExecutionDomainEvent> result=m_useCase.Execute(command,
                                                              executionRequestId,
                                                              basket.Symbol(),
                                                              basket.Direction(),
                                                              0,
                                                              lotSize,
                                                              0.0,
                                                              0.0,
                                                              0.0,
                                                              "manual dry-run open probe");
      m_lastProcessedTriggerToken=triggerToken;

      if(result.IsFail())
         return CVoidResult::Fail(result.ErrorCode(),result.ErrorMessage());

      if(m_eventBus!=NULL)
        {
         CExecutionDomainEvent eventValue;
         result.TryGetValue(eventValue);
         CExecutionDomainEvent *published=new CExecutionDomainEvent();
         published.SetEventType(eventValue.EventType());
         published.SetBasketId(eventValue.BasketId());
         published.SetCorrelationId(eventValue.CorrelationId());
         published.SetOccurredAt(eventValue.OccurredAt());
         published.SetExecutionRequestId(eventValue.ExecutionRequestId());
         published.SetIdempotencyKey(eventValue.IdempotencyKey());
         published.SetIntentType(eventValue.IntentType());
         published.SetExecutionStatus(eventValue.ExecutionStatus());
         published.SetFailureReason(eventValue.FailureReason());
         published.SetRequestedVolume(eventValue.RequestedVolume());
         published.SetFilledVolume(eventValue.FilledVolume());
         m_eventBus.Publish(published);
        }

      if(m_logger!=NULL)
        {
         CExecutionDomainEvent eventValue;
         result.TryGetValue(eventValue);
         m_logger.Info("EXECUTION","ManualDryRun","",
                       StringFormat("Manual dry-run completed | basket=%s | status=%s | event_type=%d",
                                    basketIdValue,
                                    TradeExecutionStatusLabel(eventValue.ExecutionStatus()),
                                    (int)eventValue.EventType()));
        }

      if(m_enableExecutionDiagnostics && triggerToken!="")
        {
         string brokerAfter=StringFormat("BRE chart-validation | broker_state_after | positions=%d | orders=%d | no_ordersend=true",
                                         PositionsTotal(),OrdersTotal());
         Print(brokerAfter);
         if(m_logger!=NULL)
            m_logger.Info("EXECUTION","ChartValidation","",brokerAfter);
        }

      return CVoidResult::Ok();
     }
  };

#endif
