#ifndef BASKET_RECOVERY_APPLICATION_COMMAND_FAILED_HANDLER_MQH
#define BASKET_RECOVERY_APPLICATION_COMMAND_FAILED_HANDLER_MQH

#include <BasketRecovery/Application/Ports/IEventHandler.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Handlers/StateTransitionHandler.mqh>
#include <BasketRecovery/Domain/Requests/TransitionRequest.mqh>
#include <BasketRecovery/Domain/Validation/BasketValidator.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CCommandFailedHandler : public IEventHandler
  {
private:
   IBasketRepository         *m_repository;
   CStateTransitionHandler   *m_transitionHandler;
   IClock                    *m_clock;
   IUniqueIdGenerator        *m_idGenerator;

public:
                     CCommandFailedHandler(IBasketRepository *repository,
                                           CStateTransitionHandler *transitionHandler,
                                           IClock *clock,
                                           IUniqueIdGenerator *idGenerator)
     {
      m_repository=repository;
      m_transitionHandler=transitionHandler;
      m_clock=clock;
      m_idGenerator=idGenerator;
     }

   virtual          ~CCommandFailedHandler(void) {}

   virtual bool      CanHandle(const CDomainEvent *domainEvent) const
     {
      return domainEvent!=NULL && domainEvent.EventType()==BRE_EVENT_COMMAND_FAILED;
     }

   virtual int       Priority(void) const { return 100; }

   virtual CResult<CEventHandlingResult> Handle(CDomainEvent *domainEvent)
     {
      if(m_repository==NULL || m_transitionHandler==NULL)
         return CResult<CEventHandlingResult>::Fail(BRE_ERR_SERVICE_NOT_REGISTERED,"Command failed handler dependencies are missing");

      CResult<CBasketAggregate> loadResult=m_repository.Load(domainEvent.BasketId());
      if(loadResult.IsFail())
         return CResult<CEventHandlingResult>::Fail(loadResult.ErrorCode(),loadResult.ErrorMessage());

      CBasketAggregate aggregate;
      if(!loadResult.TryGetValue(aggregate))
         return CResult<CEventHandlingResult>::Fail(BRE_ERR_BASKET_NOT_FOUND,"Aggregate missing after load");

      CCommandId commandId(m_idGenerator.NewGuid());
      CEventId eventId(m_idGenerator.NewGuid());
      CUtcTime timestampUtc(m_clock!=NULL ? m_clock.Now() : 0);

      CTransitionRequest request=CTransitionRequest::ForLifecycle(aggregate.Id(),commandId,eventId,BRE_EVENT_COMMAND_FAILED);
      CResult<CCommandExecutionResult> transitionResult=m_transitionHandler.ProcessLifecycle(aggregate,request,timestampUtc);
      if(transitionResult.IsFail())
         return CResult<CEventHandlingResult>::Fail(transitionResult.ErrorCode(),transitionResult.ErrorMessage());

      CVoidResult validation=CBasketValidator::Validate(aggregate);
      if(validation.IsFail())
         return CResult<CEventHandlingResult>::Fail(validation.ErrorCode(),validation.ErrorMessage());

      CVoidResult saveResult=m_repository.Save(aggregate);
      if(saveResult.IsFail())
         return CResult<CEventHandlingResult>::Fail(saveResult.ErrorCode(),saveResult.ErrorMessage());

      CEventHandlingResult handlingResult;
      return BreResultOkAdopting(handlingResult);
     }
  };

#endif
