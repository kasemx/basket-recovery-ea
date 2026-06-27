#ifndef BASKET_RECOVERY_DOMAIN_TRADING_SIGNAL_MQH
#define BASKET_RECOVERY_DOMAIN_TRADING_SIGNAL_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/ValueObjects/SignalDetails.mqh>

class CTradingSignal
  {
private:
   CSignalId                 m_id;
   string                    m_correlationKey;
   string                    m_sequence;
   ENUM_BRE_TRADE_DIRECTION  m_direction;
   string                    m_symbol;
   CSignalDetails            m_details;
   datetime                  m_receivedAt;
   bool                      m_isConsumed;

public:
                     CTradingSignal(void)
     {
      m_correlationKey="";
      m_sequence="";
      m_direction=BRE_DIRECTION_NONE;
      m_symbol="";
      m_receivedAt=0;
      m_isConsumed=false;
     }

   CSignalId                 Id(void) const { return m_id; }
   string                    CorrelationKey(void) const { return m_correlationKey; }
   string                    Sequence(void) const { return m_sequence; }
   ENUM_BRE_TRADE_DIRECTION  Direction(void) const { return m_direction; }
   string                    Symbol(void) const { return m_symbol; }
   CSignalDetails            Details(void) const { return m_details; }
   datetime                  ReceivedAt(void) const { return m_receivedAt; }
   bool                      IsConsumed(void) const { return m_isConsumed; }

   void                      SetId(const CSignalId &value) { m_id=value; }
   void                      SetCorrelationKey(const string value) { m_correlationKey=value; }
   void                      SetSequence(const string value) { m_sequence=value; }
   void                      SetDirection(const ENUM_BRE_TRADE_DIRECTION value) { m_direction=value; }
   void                      SetSymbol(const string value) { m_symbol=value; }
   void                      SetDetails(const CSignalDetails &value) { m_details=value; }
   void                      SetReceivedAt(const datetime value) { m_receivedAt=value; }
   void                      SetIsConsumed(const bool value) { m_isConsumed=value; }
  };

#endif
