#ifndef BASKET_RECOVERY_APPLICATION_UPDATE_SL_COMMAND_MQH
#define BASKET_RECOVERY_APPLICATION_UPDATE_SL_COMMAND_MQH

#include <BasketRecovery/Application/Commands/CommandBase.mqh>
#include <BasketRecovery/Shared/Types/Price.mqh>

class CUpdateSLCommand : public CCommandBase
  {
private:
   CPrice    m_stopLoss;
   CSignalId m_signalId;

public:
                     CUpdateSLCommand(void)
     {
      SetType(BRE_COMMAND_UPDATE_SL);
      SetPriority(50);
     }

   CPrice            StopLoss(void) const { return m_stopLoss; }
   CSignalId         SignalId(void) const { return m_signalId; }

   void              SetStopLoss(const CPrice &value) { m_stopLoss=value; }
   void              SetSignalId(const CSignalId &value) { m_signalId=value; }
  };

#endif
