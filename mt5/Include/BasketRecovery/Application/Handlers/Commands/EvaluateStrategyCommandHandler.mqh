#ifndef BRE_APP_EVALUATE_STRATEGY_CMD_HANDLER_MQH
#define BRE_APP_EVALUATE_STRATEGY_CMD_HANDLER_MQH

#include <BasketRecovery/Application/Ports/ICommandHandler.mqh>
#include <BasketRecovery/Application/UseCases/EvaluateBasketStrategyUseCase.mqh>
#include <BasketRecovery/Application/Ports/IMarketContextProvider.mqh>
#include <BasketRecovery/Infrastructure/Market/MarketContextProviderAdapter.mqh>
#include <BasketRecovery/Application/Handlers/Commands/StrategyCommandSupport.mqh>
#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CEvaluateStrategyCommandHandler : public ICommandHandler
  {
private:
   CEvaluateBasketStrategyUseCase *m_useCase;
   IMarketContextProvider       *m_marketProvider;
   CMarketContextProviderAdapter *m_riskGateMarketAdapter;

public:
                     CEvaluateStrategyCommandHandler(CEvaluateBasketStrategyUseCase *useCase,
                                                     IMarketContextProvider *marketProvider,
                                                     CMarketContextProviderAdapter *riskGateMarketAdapter=NULL)
     {
      m_useCase=useCase;
      m_marketProvider=marketProvider;
      m_riskGateMarketAdapter=riskGateMarketAdapter;
     }

   virtual bool      CanHandle(const ICommand *command) const
     {
      return command!=NULL && command.Type()==BRE_COMMAND_EVALUATE_STRATEGY;
     }

   virtual CResult<CCommandExecutionResult> Execute(ICommand *command)
     {
      CEvaluateStrategyCommand *evaluateCommand=(CEvaluateStrategyCommand*)command;
      if(evaluateCommand==NULL || m_useCase==NULL)
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_COMMAND_INVALID,"Evaluate strategy command is required");

      CResult<CBasketAggregate> loaded=CStrategyCommandSupport::LoadAndValidate(evaluateCommand,m_useCase.Repository());
      if(loaded.IsFail())
         return CResult<CCommandExecutionResult>::Fail(loaded.ErrorCode(),loaded.ErrorMessage());

      CBasketAggregate basket;
      loaded.TryGetValue(basket);

      CMarketContext market;
      CRiskRuntimeContext riskContext;
      if(m_marketProvider==NULL || !m_marketProvider.TryBuildForBasket(basket,market,riskContext))
         return CResult<CCommandExecutionResult>::EmptyOk();

      CRecoveryRiskGateInput gateInput;
      datetime nowUtc=TimeGMT();
      if(m_riskGateMarketAdapter!=NULL &&
         m_riskGateMarketAdapter.TryBuildRiskGateInput(basket,evaluateCommand.CorrelationKey(),nowUtc,0,gateInput))
        {
         CResult<int> result=m_useCase.ExecuteWithRiskGate(*evaluateCommand,market,riskContext,gateInput);
         if(result.IsFail())
            return CResult<CCommandExecutionResult>::Fail(result.ErrorCode(),result.ErrorMessage());
         return CResult<CCommandExecutionResult>::EmptyOk();
        }

      CResult<int> result=m_useCase.Execute(*evaluateCommand,market,riskContext);
      if(result.IsFail())
         return CResult<CCommandExecutionResult>::Fail(result.ErrorCode(),result.ErrorMessage());

      return CResult<CCommandExecutionResult>::EmptyOk();
     }
  };

#endif
