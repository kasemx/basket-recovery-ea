#ifndef BASKET_RECOVERY_APPLICATION_CLOSE_BASKET_COMMAND_MQH
#define BASKET_RECOVERY_APPLICATION_CLOSE_BASKET_COMMAND_MQH

#include <BasketRecovery/Application/Commands/CommandBase.mqh>

class CCloseBasketCommand : public CCommandBase
  {
private:
   string m_reason;

public:
                     CCloseBasketCommand(void)
     {
      SetType(BRE_COMMAND_CLOSE_BASKET);
      SetPriority(100);
      m_reason="";
     }

   string            Reason(void) const { return m_reason; }
   void              SetReason(const string value) { m_reason=value; }
  };

#endif
