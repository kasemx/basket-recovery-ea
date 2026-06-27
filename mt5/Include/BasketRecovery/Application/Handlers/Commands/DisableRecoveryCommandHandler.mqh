#ifndef BRE_APP_DISABLE_RECOVERY_CMD_HANDLER_MQH
#define BRE_APP_DISABLE_RECOVERY_CMD_HANDLER_MQH

#include <BasketRecovery/Application/Ports/ICommandHandler.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Handlers/Commands/StrategyCommandSupport.mqh>
#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Domain/Events/DomainEvent.mqh>

class CDisableRecoveryCommandHandler : public ICommandHandler
  {
private:
   IBasketRepository  *m_repository;
   IClock             *m_clock;
   IUniqueIdGenerator *m_idGenerator;

public:
                     CDisableRecoveryCommandHandler(IBasketRepository *repository,
                                                    IClock *clock,
                                                    IUniqueIdGenerator *idGenerator)
     {
      m_repository=repository;
      m_clock=clock;
      m_idGenerator=idGenerator;
     }

   virtual bool      CanHandle(const ICommand *command) const
     {
      return command!=NULL && command.Type()==BRE_COMMAND_DISABLE_RECOVERY;
     }

   virtual CResult<CCommandExecutionResult> Execute(ICommand *command)
     {
      CDisableRecoveryCommand *disableCommand=(CDisableRecoveryCommand*)command;
      CResult<CBasketAggregate> loaded=CStrategyCommandSupport::LoadAndValidate(disableCommand,m_repository);
      if(loaded.IsFail())
         return CResult<CCommandExecutionResult>::Fail(loaded.ErrorCode(),loaded.ErrorMessage());

      CBasketAggregate basket;
      loaded.TryGetValue(basket);

      CCommandId commandId=disableCommand.Id().IsEmpty() ? CCommandId(m_idGenerator.NewGuid()) : disableCommand.Id();
      CEventId eventId(m_idGenerator.NewGuid());
      CUtcTime timestampUtc(m_clock!=NULL ? m_clock.Now() : 0);
      basket.ApplyRecoveryDisabled(commandId,eventId,timestampUtc);

      if(m_repository.Save(basket).IsFail())
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to save basket");

      CCommandExecutionResult executionResult;
      CDomainEvent *event=new CDomainEvent();
      event.SetEventType(BRE_EVENT_RECOVERY_DISABLED);
      event.SetBasketId(basket.Id());
      event.SetCorrelationId(disableCommand.CorrelationKey());
      event.SetOccurredAt(timestampUtc.Value());
      executionResult.AddEvent(event);
      return BreResultOkAdopting(executionResult);
     }
  };

#endif
