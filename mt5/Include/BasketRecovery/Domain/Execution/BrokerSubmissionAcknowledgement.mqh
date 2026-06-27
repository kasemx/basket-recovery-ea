#ifndef BRE_DOMAIN_BROKER_SUBMISSION_ACKNOWLEDGEMENT_MQH
#define BRE_DOMAIN_BROKER_SUBMISSION_ACKNOWLEDGEMENT_MQH

class CBrokerSubmissionAcknowledgement
  {
private:
   string   m_executionRequestId;
   string   m_idempotencyKey;
   ulong    m_brokerOrderId;
   ulong    m_brokerRequestId;
   datetime m_acknowledgedAtUtc;

public:
                     CBrokerSubmissionAcknowledgement(void)
     {
      m_brokerOrderId=0;
      m_brokerRequestId=0;
      m_acknowledgedAtUtc=0;
     }

   string            ExecutionRequestId(void) const { return m_executionRequestId; }
   string            IdempotencyKey(void) const { return m_idempotencyKey; }
   ulong             BrokerOrderId(void) const { return m_brokerOrderId; }
   ulong             BrokerRequestId(void) const { return m_brokerRequestId; }
   datetime          AcknowledgedAtUtc(void) const { return m_acknowledgedAtUtc; }

   void              SetExecutionRequestId(const string value) { m_executionRequestId=value; }
   void              SetIdempotencyKey(const string value) { m_idempotencyKey=value; }
   void              SetBrokerOrderId(const ulong value) { m_brokerOrderId=value; }
   void              SetBrokerRequestId(const ulong value) { m_brokerRequestId=value; }
   void              SetAcknowledgedAtUtc(const datetime value) { m_acknowledgedAtUtc=value; }
  };

#endif
