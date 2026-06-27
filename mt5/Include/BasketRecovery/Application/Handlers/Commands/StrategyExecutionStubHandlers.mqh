#ifndef BRE_APP_STRATEGY_EXECUTION_STUB_HANDLERS_MQH
#define BRE_APP_STRATEGY_EXECUTION_STUB_HANDLERS_MQH

#include <BasketRecovery/Application/Ports/ICommandHandler.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Handlers/Commands/StrategyCommandSupport.mqh>
#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>

class CStrategyExecutionStubHandlerBase : public ICommandHandler
  {
protected:
   IBasketRepository *m_repository;
   IClock            *m_clock;
   ENUM_BRE_COMMAND_TYPE m_commandType;

   CStrategyExecutionStubHandlerBase(IBasketRepository *repository,IClock *clock,const ENUM_BRE_COMMAND_TYPE commandType)
     {
      m_repository=repository;
      m_clock=clock;
      m_commandType=commandType;
     }

   CResult<CCommandExecutionResult> ExecuteStub(CStrategyCommandBase *command)
     {
      CResult<CBasketAggregate> loaded=CStrategyCommandSupport::LoadAndValidate(command,m_repository);
      if(loaded.IsFail())
         return CResult<CCommandExecutionResult>::Fail(loaded.ErrorCode(),loaded.ErrorMessage());

      CBasketAggregate basket;
      loaded.TryGetValue(basket);

      CCommandExecutionResult executionResult;
      CStrategyDomainEvent *event=CStrategyCommandSupport::CreateExecutionPendingEvent(basket,command,m_commandType);
      if(event!=NULL && m_clock!=NULL)
         event.SetOccurredAt(m_clock.Now());
      executionResult.AddEvent(event);
      return BreResultOkAdopting(executionResult);
     }
  };

class COpenRecoveryPositionCommandHandler : public CStrategyExecutionStubHandlerBase
  {
public:
                     COpenRecoveryPositionCommandHandler(IBasketRepository *repository,IClock *clock)
        : CStrategyExecutionStubHandlerBase(repository,clock,BRE_COMMAND_OPEN_RECOVERY_POSITION) {}

   virtual bool      CanHandle(const ICommand *command) const
     {
      return command!=NULL && command.Type()==BRE_COMMAND_OPEN_RECOVERY_POSITION;
     }

   virtual CResult<CCommandExecutionResult> Execute(ICommand *command)
     {
      return ExecuteStub((COpenRecoveryPositionCommand*)command);
     }
  };

class CClosePositionsCommandHandler : public CStrategyExecutionStubHandlerBase
  {
public:
                     CClosePositionsCommandHandler(IBasketRepository *repository,IClock *clock)
        : CStrategyExecutionStubHandlerBase(repository,clock,BRE_COMMAND_CLOSE_POSITIONS) {}

   virtual bool      CanHandle(const ICommand *command) const
     {
      return command!=NULL && command.Type()==BRE_COMMAND_CLOSE_POSITIONS;
     }

   virtual CResult<CCommandExecutionResult> Execute(ICommand *command)
     {
      return ExecuteStub((CClosePositionsCommand*)command);
     }
  };

class CMoveBasketStopLossCommandHandler : public CStrategyExecutionStubHandlerBase
  {
public:
                     CMoveBasketStopLossCommandHandler(IBasketRepository *repository,IClock *clock)
        : CStrategyExecutionStubHandlerBase(repository,clock,BRE_COMMAND_MOVE_BASKET_STOP_LOSS) {}

   virtual bool      CanHandle(const ICommand *command) const
     {
      return command!=NULL && command.Type()==BRE_COMMAND_MOVE_BASKET_STOP_LOSS;
     }

   virtual CResult<CCommandExecutionResult> Execute(ICommand *command)
     {
      return ExecuteStub((CMoveBasketStopLossCommand*)command);
     }
  };

class CReduceBasketRiskCommandHandler : public CStrategyExecutionStubHandlerBase
  {
public:
                     CReduceBasketRiskCommandHandler(IBasketRepository *repository,IClock *clock)
        : CStrategyExecutionStubHandlerBase(repository,clock,BRE_COMMAND_REDUCE_BASKET_RISK) {}

   virtual bool      CanHandle(const ICommand *command) const
     {
      return command!=NULL && command.Type()==BRE_COMMAND_REDUCE_BASKET_RISK;
     }

   virtual CResult<CCommandExecutionResult> Execute(ICommand *command)
     {
      return ExecuteStub((CReduceBasketRiskCommand*)command);
     }
  };

#endif
