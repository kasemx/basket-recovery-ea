#ifndef BRE_APP_MARK_PROFIT_LEVEL_COMPLETED_CMD_H_MQH
#define BRE_APP_MARK_PROFIT_LEVEL_COMPLETED_CMD_H_MQH

#include <BasketRecovery/Application/Ports/ICommandHandler.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Handlers/Commands/StrategyCommandSupport.mqh>
#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Domain/Events/StrategyDomainEvent.mqh>

class CMarkProfitLevelCompletedCommandHandler : public ICommandHandler
  {
private:
   IBasketRepository   *m_repository;
   IClock              *m_clock;
   IUniqueIdGenerator  *m_idGenerator;

public:
                     CMarkProfitLevelCompletedCommandHandler(IBasketRepository *repository,
                                                             IClock *clock,
                                                             IUniqueIdGenerator *idGenerator)
     {
      m_repository=repository;
      m_clock=clock;
      m_idGenerator=idGenerator;
     }

   virtual bool      CanHandle(const ICommand *command) const
     {
      return command!=NULL && command.Type()==BRE_COMMAND_MARK_PROFIT_LEVEL_COMPLETED;
     }

   virtual CResult<CCommandExecutionResult> Execute(ICommand *command)
     {
      CMarkProfitLevelCompletedCommand *completeCommand=(CMarkProfitLevelCompletedCommand*)command;
      CResult<CBasketAggregate> loaded=CStrategyCommandSupport::LoadAndValidate(completeCommand,m_repository);
      if(loaded.IsFail())
         return CResult<CCommandExecutionResult>::Fail(loaded.ErrorCode(),loaded.ErrorMessage());

      CBasketAggregate basket;
      loaded.TryGetValue(basket);

      CCommandId commandId=completeCommand.Id().IsEmpty() ? CCommandId(m_idGenerator.NewGuid()) : completeCommand.Id();
      CEventId eventId(m_idGenerator.NewGuid());
      CUtcTime timestampUtc(m_clock!=NULL ? m_clock.Now() : 0);

      CVoidResult applyResult=basket.ApplyProfitLevelCloseCompleted(completeCommand.LevelId(),
                                                                    CMoney(completeCommand.RealizedProfit()),
                                                                    commandId,eventId,timestampUtc);
      if(applyResult.IsFail())
         return CResult<CCommandExecutionResult>::Fail(applyResult.ErrorCode(),applyResult.ErrorMessage());

      if(m_repository.Save(basket).IsFail())
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to save basket");

      CCommandExecutionResult executionResult;
      CStrategyDomainEvent *event=new CStrategyDomainEvent();
      event.SetEventType(BRE_EVENT_PROFIT_LEVEL_CLOSE_COMPLETED);
      event.SetBasketId(basket.Id());
      event.SetCorrelationId(completeCommand.CorrelationKey());
      event.SetLevelId(completeCommand.LevelId());
      event.SetRealizedProfit(completeCommand.RealizedProfit());
      event.SetOccurredAt(timestampUtc.Value());
      executionResult.AddEvent(event);
      return BreResultOkAdopting(executionResult);
     }
  };

#endif
