#ifndef BASKET_RECOVERY_APPLICATION_UPDATE_TP_COMMAND_HANDLER_MQH
#define BASKET_RECOVERY_APPLICATION_UPDATE_TP_COMMAND_HANDLER_MQH

#include <BasketRecovery/Application/Ports/ICommandHandler.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Handlers/StateTransitionHandler.mqh>
#include <BasketRecovery/Application/Commands/UpdateTPCommand.mqh>
#include <BasketRecovery/Domain/Requests/TransitionRequest.mqh>
#include <BasketRecovery/Domain/Validation/BasketValidator.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CUpdateTPCommandHandler : public ICommandHandler
  {
private:
   IBasketRepository         *m_repository;
   CStateTransitionHandler   *m_transitionHandler;
   IClock                    *m_clock;
   IUniqueIdGenerator        *m_idGenerator;

public:
                     CUpdateTPCommandHandler(IBasketRepository *repository,
                                               CStateTransitionHandler *transitionHandler,
                                               IClock *clock,
                                               IUniqueIdGenerator *idGenerator)
     {
      m_repository=repository;
      m_transitionHandler=transitionHandler;
      m_clock=clock;
      m_idGenerator=idGenerator;
     }

   virtual          ~CUpdateTPCommandHandler(void) {}

   virtual bool      CanHandle(const ICommand *command) const
     {
      return command!=NULL && command.Type()==BRE_COMMAND_UPDATE_TP;
     }

   virtual CResult<CCommandExecutionResult> Execute(ICommand *command)
     {
      CUpdateTPCommand *updateCommand=(CUpdateTPCommand*)command;
      if(updateCommand==NULL || m_repository==NULL || m_transitionHandler==NULL)
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_COMMAND_INVALID,"Update TP dependencies are missing");

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
      request.SetKind(BRE_TRANSITION_REQUEST_TAKE_PROFIT);
      request.SetBasketId(aggregate.Id());
      request.SetCommandId(commandId);
      request.SetEventId(eventId);
      request.SetSignalDetailsPayload(updateCommand.Details());

      CResult<CCommandExecutionResult> mutationResult=m_transitionHandler.ProcessTakeProfit(aggregate,request,timestampUtc);
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
