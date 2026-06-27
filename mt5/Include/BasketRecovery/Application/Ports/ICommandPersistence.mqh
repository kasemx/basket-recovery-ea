#ifndef BASKET_RECOVERY_APPLICATION_ICOMMAND_PERSISTENCE_MQH
#define BASKET_RECOVERY_APPLICATION_ICOMMAND_PERSISTENCE_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Application/Commands/ICommand.mqh>

class ICommandPersistence
  {
public:
   virtual          ~ICommandPersistence(void) {}
   virtual CVoidResult SavePendingCommands(ICommand *commands[],const int count)=0;
   virtual CResult<int> LoadPendingCommands(ICommand * &commands[])=0;
   virtual CVoidResult ClearPendingCommands(void)=0;
  };

#endif
