#ifndef BRE_DOMAIN_EXECUTION_RECONCILIATION_REQUEST_MQH
#define BRE_DOMAIN_EXECUTION_RECONCILIATION_REQUEST_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>

class CExecutionReconciliationRequest
  {
private:
   string    m_executionRequestId;
   CBasketId m_basketId;
   string    m_symbol;
   datetime  m_requestedAtUtc;
   string    m_reason;

public:
                     CExecutionReconciliationRequest(void)
     {
      m_executionRequestId="";
      m_symbol="";
      m_requestedAtUtc=0;
      m_reason="";
     }

   string            ExecutionRequestId(void) const { return m_executionRequestId; }
   CBasketId         BasketId(void) const { return m_basketId; }
   string            Symbol(void) const { return m_symbol; }
   datetime          RequestedAtUtc(void) const { return m_requestedAtUtc; }
   string            Reason(void) const { return m_reason; }

   void              SetExecutionRequestId(const string value) { m_executionRequestId=value; }
   void              SetBasketId(const CBasketId &value) { m_basketId=value; }
   void              SetSymbol(const string value) { m_symbol=value; }
   void              SetRequestedAtUtc(const datetime value) { m_requestedAtUtc=value; }
   void              SetReason(const string value) { m_reason=value; }
  };

#endif
