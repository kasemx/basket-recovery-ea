#ifndef BASKET_RECOVERY_APPLICATION_ICOMMAND_MQH
#define BASKET_RECOVERY_APPLICATION_ICOMMAND_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/CommandType.mqh>

class ICommand
  {
public:
   virtual          ~ICommand(void) {}
   virtual ENUM_BRE_COMMAND_TYPE Type(void) const=0;
   virtual CCommandId          Id(void) const=0;
   virtual string              IdempotencyKey(void) const=0;
   virtual CBasketId           BasketId(void) const=0;
   virtual string              CorrelationKey(void) const=0;
   virtual ENUM_BRE_COMMAND_STATUS Status(void) const=0;
   virtual int                 Priority(void) const=0;
   virtual string              Source(void) const=0;
   virtual datetime            EnqueuedAt(void) const=0;
  };

#endif
