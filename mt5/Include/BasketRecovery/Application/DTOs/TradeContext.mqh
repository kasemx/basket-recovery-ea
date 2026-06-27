#ifndef BASKET_RECOVERY_APPLICATION_TRADE_CONTEXT_MQH
#define BASKET_RECOVERY_APPLICATION_TRADE_CONTEXT_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/TradeRole.mqh>

class CTradeContext
  {
private:
   CBasketId             m_basketId;
   CSignalId             m_signalId;
   int                   m_recoveryStep;
   ENUM_BRE_TRADE_ROLE   m_tradeRole;
   int                   m_magic;
   string                m_correlationId;
   string                m_idempotencyKey;

public:
                     CTradeContext(void)
     {
      m_recoveryStep=0;
      m_tradeRole=BRE_TRADE_ROLE_NONE;
      m_magic=0;
      m_correlationId="";
      m_idempotencyKey="";
     }

   CBasketId             BasketId(void) const { return m_basketId; }
   CSignalId             SignalId(void) const { return m_signalId; }
   int                   RecoveryStep(void) const { return m_recoveryStep; }
   ENUM_BRE_TRADE_ROLE   TradeRole(void) const { return m_tradeRole; }
   int                   Magic(void) const { return m_magic; }
   string                CorrelationId(void) const { return m_correlationId; }
   string                IdempotencyKey(void) const { return m_idempotencyKey; }

   void                  SetBasketId(const CBasketId &value) { m_basketId=value; }
   void                  SetSignalId(const CSignalId &value) { m_signalId=value; }
   void                  SetRecoveryStep(const int value) { m_recoveryStep=value; }
   void                  SetTradeRole(const ENUM_BRE_TRADE_ROLE value) { m_tradeRole=value; }
   void                  SetMagic(const int value) { m_magic=value; }
   void                  SetCorrelationId(const string value) { m_correlationId=value; }
   void                  SetIdempotencyKey(const string value) { m_idempotencyKey=value; }
  };

#endif
