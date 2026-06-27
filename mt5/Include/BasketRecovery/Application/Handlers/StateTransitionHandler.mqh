#ifndef BASKET_RECOVERY_APPLICATION_STATE_TRANSITION_HANDLER_MQH
#define BASKET_RECOVERY_APPLICATION_STATE_TRANSITION_HANDLER_MQH

#include <BasketRecovery/Application/Kernel/TransitionEngine.mqh>
#include <BasketRecovery/Application/DTOs/CommandExecutionResult.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Requests/TransitionRequest.mqh>
#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>
#include <BasketRecovery/Shared/Types/ResultValueTransfer.mqh>

class CStateTransitionHandler
  {
private:
   CTransitionEngine *m_engine;

   void              AppendTransitionEvent(CCommandExecutionResult &executionResult,
                                           const CBasketAggregate &aggregate,
                                           const CTransitionResult &transitionResult) const
     {
      if(transitionResult.Applied())
        {
         CDomainEvent *event=new CDomainEvent();
         event.SetEventType(BRE_EVENT_STATE_TRANSITIONED);
         event.SetBasketId(aggregate.Id());
         event.SetCorrelationId(aggregate.CorrelationKey());
         executionResult.AddEvent(event);
         return;
        }

      CDomainEvent *event=new CDomainEvent();
      event.SetEventType(BRE_EVENT_TRANSITION_REJECTED);
      event.SetBasketId(aggregate.Id());
      event.SetCorrelationId(transitionResult.RejectionReason());
      executionResult.AddEvent(event);
     }

public:
                     CStateTransitionHandler(CTransitionEngine *engine)
     {
      m_engine=engine;
     }

   CResult<CCommandExecutionResult> ProcessLifecycle(CBasketAggregate &aggregate,
                                                       const CTransitionRequest &request,
                                                       const CUtcTime &timestampUtc)
     {
      if(m_engine==NULL)
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_SERVICE_NOT_REGISTERED,"Transition engine is not registered");

      if(request.TriggerEvent()==BRE_EVENT_NONE)
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_TRANSITION_REQUEST_INVALID,"Trigger event is required");

      CDomainEvent triggerEvent;
      triggerEvent.SetEventType(request.TriggerEvent());
      triggerEvent.SetBasketId(aggregate.Id());

      CResult<CTransitionResult> transitionResult=m_engine.ApplyTransition(aggregate,triggerEvent);
      if(transitionResult.IsFail())
         return CResult<CCommandExecutionResult>::Fail(transitionResult.ErrorCode(),transitionResult.ErrorMessage());

      CTransitionResult outcome;
      if(!transitionResult.TryGetValue(outcome))
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_TRANSITION_INVALID,"Transition outcome missing");

      CCommandExecutionResult executionResult;

      if(outcome.Applied())
        {
         if(!aggregate.ApplyLifecycleTransition(outcome,request.CommandId(),request.EventId(),timestampUtc))
            return CResult<CCommandExecutionResult>::Fail(BRE_ERR_BASKET_INVALID,"Failed to apply lifecycle transition");
        }

      if(request.Kind()==BRE_TRANSITION_REQUEST_CLOSE && request.CloseReason()!="")
         aggregate.ApplyCloseReason(request.CloseReason());

      AppendTransitionEvent(executionResult,aggregate,outcome);
      return BreResultOkAdopting(executionResult);
     }

   CResult<CCommandExecutionResult> ProcessSignalDetails(CBasketAggregate &aggregate,
                                                           const CTransitionRequest &request,
                                                           const CUtcTime &timestampUtc)
     {
      if(!request.HasSignalDetails())
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_TRANSITION_REQUEST_INVALID,"Signal details payload is required");

      if(!aggregate.ApplySignalDetails(request.SignalDetailsPayload(),request.CommandId(),request.EventId(),timestampUtc))
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_BASKET_INVALID,"Failed to apply signal details");

      CCommandExecutionResult executionResult;
      CDomainEvent *event=new CDomainEvent();
      event.SetEventType(BRE_EVENT_BASKET_ACTIVATED);
      event.SetBasketId(aggregate.Id());
      executionResult.AddEvent(event);
      return BreResultOkAdopting(executionResult);
     }

   CResult<CCommandExecutionResult> ProcessStopLoss(CBasketAggregate &aggregate,
                                                      const CTransitionRequest &request,
                                                      const CUtcTime &timestampUtc)
     {
      if(!request.HasStopLoss())
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_TRANSITION_REQUEST_INVALID,"Stop loss payload is required");

      if(!aggregate.ApplyStopLossUpdate(request.StopLoss(),request.CommandId(),request.EventId(),timestampUtc))
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_BASKET_INVALID,"Failed to apply stop loss update");

      return CResult<CCommandExecutionResult>::EmptyOk();
     }

   CResult<CCommandExecutionResult> ProcessTakeProfit(CBasketAggregate &aggregate,
                                                        const CTransitionRequest &request,
                                                        const CUtcTime &timestampUtc)
     {
      if(!request.HasSignalDetails())
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_TRANSITION_REQUEST_INVALID,"Take profit payload is required");

      if(!aggregate.ApplyTakeProfitUpdate(request.SignalDetailsPayload(),request.CommandId(),request.EventId(),timestampUtc))
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_BASKET_INVALID,"Failed to apply take profit update");

      return CResult<CCommandExecutionResult>::EmptyOk();
     }
  };

#endif
