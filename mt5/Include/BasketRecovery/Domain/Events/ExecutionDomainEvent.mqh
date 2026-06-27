#ifndef BRE_DOMAIN_EXECUTION_DOMAIN_EVENT_MQH
#define BRE_DOMAIN_EXECUTION_DOMAIN_EVENT_MQH

#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionFailureReason.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>

class CExecutionDomainEvent : public CDomainEvent
  {
private:
   string                                  m_executionRequestId;
   string                                  m_idempotencyKey;
   ENUM_BRE_TRADE_EXECUTION_INTENT         m_intentType;
   ENUM_BRE_TRADE_EXECUTION_STATUS         m_executionStatus;
   ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON m_failureReason;
   double                                  m_requestedVolume;
   double                                  m_filledVolume;

public:
                     CExecutionDomainEvent(void)
     {
      m_executionRequestId="";
      m_idempotencyKey="";
      m_intentType=BRE_EXEC_INTENT_NONE;
      m_executionStatus=BRE_TRADE_EXEC_STATUS_NONE;
      m_failureReason=BRE_EXEC_FAIL_NONE;
      m_requestedVolume=0.0;
      m_filledVolume=0.0;
     }

   string                                  ExecutionRequestId(void) const { return m_executionRequestId; }
   string                                  IdempotencyKey(void) const { return m_idempotencyKey; }
   ENUM_BRE_TRADE_EXECUTION_INTENT         IntentType(void) const { return m_intentType; }
   ENUM_BRE_TRADE_EXECUTION_STATUS         ExecutionStatus(void) const { return m_executionStatus; }
   ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON FailureReason(void) const { return m_failureReason; }
   double                                  RequestedVolume(void) const { return m_requestedVolume; }
   double                                  FilledVolume(void) const { return m_filledVolume; }

   void              SetExecutionRequestId(const string value) { m_executionRequestId=value; }
   void              SetIdempotencyKey(const string value) { m_idempotencyKey=value; }
   void              SetIntentType(const ENUM_BRE_TRADE_EXECUTION_INTENT value) { m_intentType=value; }
   void              SetExecutionStatus(const ENUM_BRE_TRADE_EXECUTION_STATUS value) { m_executionStatus=value; }
   void              SetFailureReason(const ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON value) { m_failureReason=value; }
   void              SetRequestedVolume(const double value) { m_requestedVolume=value; }
   void              SetFilledVolume(const double value) { m_filledVolume=value; }
  };

#endif
