#ifndef BRE_DOMAIN_BROKER_REQUEST_CORRELATION_MQH
#define BRE_DOMAIN_BROKER_REQUEST_CORRELATION_MQH

#include <BasketRecovery/Shared/Types/ExecutionCorrelationId.mqh>

class CBrokerRequestCorrelation
  {
private:
   CExecutionCorrelationId m_correlationId;
   ulong                   m_brokerOrderId;
   ulong                   m_brokerDealId;
   ulong                   m_positionTicket;
   long                    m_magicNumber;
   string                  m_symbol;
   string                  m_commentToken;
   string                  m_requestFingerprint;

public:
                     CBrokerRequestCorrelation(void)
     {
      m_brokerOrderId=0;
      m_brokerDealId=0;
      m_positionTicket=0;
      m_magicNumber=0;
      m_symbol="";
      m_commentToken="";
      m_requestFingerprint="";
     }

   CExecutionCorrelationId CorrelationId(void) const { return m_correlationId; }
   ulong             BrokerOrderId(void) const { return m_brokerOrderId; }
   ulong             BrokerDealId(void) const { return m_brokerDealId; }
   ulong             PositionTicket(void) const { return m_positionTicket; }
   long              MagicNumber(void) const { return m_magicNumber; }
   string            Symbol(void) const { return m_symbol; }
   string            CommentToken(void) const { return m_commentToken; }
   string            RequestFingerprint(void) const { return m_requestFingerprint; }

   void              SetCorrelationId(const CExecutionCorrelationId &value) { m_correlationId=value; }
   void              SetBrokerOrderId(const ulong value) { m_brokerOrderId=value; }
   void              SetBrokerDealId(const ulong value) { m_brokerDealId=value; }
   void              SetPositionTicket(const ulong value) { m_positionTicket=value; }
   void              SetMagicNumber(const long value) { m_magicNumber=value; }
   void              SetSymbol(const string value) { m_symbol=value; }
   void              SetCommentToken(const string value) { m_commentToken=value; }
   void              SetRequestFingerprint(const string value) { m_requestFingerprint=value; }

   bool              HasBrokerOrderId(void) const { return m_brokerOrderId>0; }
   bool              HasBrokerDealId(void) const { return m_brokerDealId>0; }
   bool              HasPositionTicket(void) const { return m_positionTicket>0; }
  };

#endif
