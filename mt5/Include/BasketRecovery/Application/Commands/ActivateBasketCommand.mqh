#ifndef BASKET_RECOVERY_APPLICATION_ACTIVATE_BASKET_COMMAND_MQH
#define BASKET_RECOVERY_APPLICATION_ACTIVATE_BASKET_COMMAND_MQH

#include <BasketRecovery/Application/Commands/CommandBase.mqh>
#include <BasketRecovery/Domain/ValueObjects/SignalDetails.mqh>

class CActivateBasketCommand : public CCommandBase
  {
private:
   CSignalDetails m_details;
   CSignalId      m_signalId;

public:
                     CActivateBasketCommand(void)
     {
      SetType(BRE_COMMAND_ACTIVATE_BASKET);
      SetPriority(50);
     }

   CSignalDetails    Details(void) const { return m_details; }
   CSignalId         SignalId(void) const { return m_signalId; }

   void              SetDetails(const CSignalDetails &value) { m_details=value; }
   void              SetSignalId(const CSignalId &value) { m_signalId=value; }
  };

#endif
