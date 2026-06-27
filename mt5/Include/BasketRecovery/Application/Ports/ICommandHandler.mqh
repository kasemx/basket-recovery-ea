#ifndef BASKET_RECOVERY_APPLICATION_ICOMMAND_HANDLER_MQH
#define BASKET_RECOVERY_APPLICATION_ICOMMAND_HANDLER_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Application/Commands/ICommand.mqh>
#include <BasketRecovery/Application/DTOs/CommandExecutionResult.mqh>
#include <BasketRecovery/Shared/Types/ResultValueTransfer.mqh>

class ICommandHandler
  {
public:
   virtual          ~ICommandHandler(void) {}
   virtual bool      CanHandle(const ICommand *command) const=0;
   virtual CResult<CCommandExecutionResult> Execute(ICommand *command)=0;
  };

#endif
