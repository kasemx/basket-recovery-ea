#ifndef BASKET_RECOVERY_APPLICATION_ICOMMAND_SOURCE_MQH
#define BASKET_RECOVERY_APPLICATION_ICOMMAND_SOURCE_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Application/Commands/ICommand.mqh>

class ICommandSource
  {
public:
   virtual          ~ICommandSource(void) {}
   virtual bool      IsAvailable(void) const=0;
   virtual CResult<int> FetchPending(ICommand * &commands[])=0;
   virtual CVoidResult Acknowledge(const CCommandId &commandId)=0;
   virtual int       LastValidationRejectedCount(void) const { return 0; }
  };

#endif
