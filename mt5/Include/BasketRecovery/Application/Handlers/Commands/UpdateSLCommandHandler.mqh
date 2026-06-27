#ifndef BASKET_RECOVERY_APPLICATION_UPDATE_SL_COMMAND_HANDLER_MQH
#define BASKET_RECOVERY_APPLICATION_UPDATE_SL_COMMAND_HANDLER_MQH

#include <BasketRecovery/Application/Ports/ICommandHandler.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Handlers/StateTransitionHandler.mqh>
#include <BasketRecovery/Application/Commands/UpdateSLCommand.mqh>
#include <BasketRecovery/Domain/Requests/TransitionRequest.mqh>
#include <BasketRecovery/Domain/Validation/BasketValidator.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CUpdateSLCommandHandler : public ICommandHandler
  {
private:
   IBasketRepository         *m_repository;
   CStateTransitionHandler   *m_transitionHandler;
   IClock                    *m_clock;
   IUniqueIdGenerator        *m_idGenerator;

public:
                     CUpdateSLCommandHandler(IBasketRepository *repository,
                                               CStateTransitionHandler *transitionHandler,
                                               IClock *clock,
                                               IUniqueIdGenerator *idGenerator)
     {
      m_repository=repository;
      m_transitionHandler=transitionHandler;
      m_clock=clock;
      m_idGenerator=idGenerator;
     }

   virtual          ~CUpdateSLCommandHandler(void) {}

   virtual bool      CanHandle(const ICommand *command) const
     {
      return command!=NULL && command.Type()==BRE_COMMAND_UPDATE_SL;
     }

   virtual CResult<CCommandExecutionResult> Execute(ICommand *command)
     {
      CUpdateSLCommand *updateCommand=(CUpdateSLCommand*)command;
      if(updateCommand==NULL || m_repository==NULL || m_transitionHandler==NULL)
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_COMMAND_INVALID,"Update SL dependencies are missing");

      CResult<CBasketAggregate> loadResult=m_repository.Load(updateCommand.BasketId());
      if(loadResult.IsFail())
         return CResult<CCommandExecutionResult>::Fail(loadResult.ErrorCode(),loadResult.ErrorMessage());

      CBasketAggregate aggregate;
      if(!loadResult.TryGetValue(aggregate))
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_BASKET_NOT_FOUND,"Aggregate missing after load");

      CCommandId commandId=updateCommand.Id().IsEmpty() ? CCommandId(m_idGenerator.NewGuid()) : updateCommand.Id();
      CEventId eventId(m_idGenerator.NewGuid());
      CUtcTime timestampUtc(m_clock!=NULL ? m_clock.Now() : 0);

      CTransitionRequest request;
      request.SetKind(BRE_TRANSITION_REQUEST_STOP_LOSS);
      request.SetBasketId(aggregate.Id());
      request.SetCommandId(commandId);
      request.SetEventId(eventId);
      request.SetStopLoss(updateCommand.StopLoss());

      CResult<CCommandExecutionResult> mutationResult=m_transitionHandler.ProcessStopLoss(aggregate,request,timestampUtc);
      if(mutationResult.IsFail())
         return mutationResult;

      CVoidResult validation=CBasketValidator::Validate(aggregate);
      if(validation.IsFail())
         return CResult<CCommandExecutionResult>::Fail(validation.ErrorCode(),validation.ErrorMessage());

      CVoidResult saveResult=m_repository.Save(aggregate);
      if(saveResult.IsFail())
         return CResult<CCommandExecutionResult>::Fail(saveResult.ErrorCode(),saveResult.ErrorMessage());

      return mutationResult;
     }
  };

#endif
