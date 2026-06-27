#ifndef BASKET_RECOVERY_APPLICATION_CREATE_BASKET_COMMAND_MQH
#define BASKET_RECOVERY_APPLICATION_CREATE_BASKET_COMMAND_MQH

#include <BasketRecovery/Application/Commands/CommandBase.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CCreateBasketCommand : public CCommandBase
  {
private:
   string                    m_symbol;
   ENUM_BRE_TRADE_DIRECTION  m_direction;
   CSignalId                 m_signalId;

public:
                     CCreateBasketCommand(void)
     {
      SetType(BRE_COMMAND_CREATE_BASKET);
      SetPriority(30);
     }

   string                    Symbol(void) const { return m_symbol; }
   ENUM_BRE_TRADE_DIRECTION  Direction(void) const { return m_direction; }
   CSignalId                 SignalId(void) const { return m_signalId; }

   void                      SetSymbol(const string value) { m_symbol=value; }
   void                      SetDirection(const ENUM_BRE_TRADE_DIRECTION value) { m_direction=value; }
   void                      SetSignalId(const CSignalId &value) { m_signalId=value; }
  };

#endif
