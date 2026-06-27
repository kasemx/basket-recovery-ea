#ifndef BRE_DOMAIN_PENDING_EXECUTION_ENTRY_MQH
#define BRE_DOMAIN_PENDING_EXECUTION_ENTRY_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Shared/Types/ExecutionCorrelationId.mqh>
#include <BasketRecovery/Domain/Execution/BrokerRequestCorrelation.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionCorrelationState.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>

class CPendingExecutionEntry
  {
private:
   string                                m_executionRequestId;
   string                                m_idempotencyKey;
   CBasketId                             m_basketId;
   int                                   m_expectedBasketVersion;
   string                                m_strategyProfileHash;
   ENUM_BRE_TRADE_EXECUTION_INTENT       m_intentType;
   string                                m_symbol;
   CBrokerRequestCorrelation             m_brokerCorrelation;
   double                                m_requestedVolume;
   double                                m_filledVolume;
   datetime                              m_createdAtUtc;
   datetime                              m_submittedAtUtc;
   datetime                              m_deadlineUtc;
   int                                   m_retryCount;
   ENUM_BRE_TRADE_EXECUTION_STATUS       m_status;
   ENUM_BRE_PENDING_EXECUTION_CORRELATION_STATE m_correlationState;
   string                                m_lastTransactionKey;
   int                                   m_seenTransactionCount;

public:
                     CPendingExecutionEntry(void)
     {
      m_executionRequestId="";
      m_idempotencyKey="";
      m_expectedBasketVersion=0;
      m_strategyProfileHash="";
      m_intentType=BRE_EXEC_INTENT_NONE;
      m_symbol="";
      m_requestedVolume=0.0;
      m_filledVolume=0.0;
      m_createdAtUtc=0;
      m_submittedAtUtc=0;
      m_deadlineUtc=0;
      m_retryCount=0;
      m_status=BRE_TRADE_EXEC_STATUS_CREATED;
      m_correlationState=BRE_PENDING_CORRELATION_UNMATCHED;
      m_lastTransactionKey="";
      m_seenTransactionCount=0;
     }

   string            ExecutionRequestId(void) const { return m_executionRequestId; }
   string            IdempotencyKey(void) const { return m_idempotencyKey; }
   CBasketId         BasketId(void) const { return m_basketId; }
   int               ExpectedBasketVersion(void) const { return m_expectedBasketVersion; }
   string            StrategyProfileHash(void) const { return m_strategyProfileHash; }
   ENUM_BRE_TRADE_EXECUTION_INTENT IntentType(void) const { return m_intentType; }
   string            Symbol(void) const { return m_symbol; }
   CBrokerRequestCorrelation BrokerCorrelation(void) const { return m_brokerCorrelation; }
   double            RequestedVolume(void) const { return m_requestedVolume; }
   double            FilledVolume(void) const { return m_filledVolume; }
   datetime          CreatedAtUtc(void) const { return m_createdAtUtc; }
   datetime          SubmittedAtUtc(void) const { return m_submittedAtUtc; }
   datetime          DeadlineUtc(void) const { return m_deadlineUtc; }
   int               RetryCount(void) const { return m_retryCount; }
   ENUM_BRE_TRADE_EXECUTION_STATUS Status(void) const { return m_status; }
   ENUM_BRE_PENDING_EXECUTION_CORRELATION_STATE CorrelationState(void) const { return m_correlationState; }
   string            LastTransactionKey(void) const { return m_lastTransactionKey; }
   int               SeenTransactionCount(void) const { return m_seenTransactionCount; }

   void              SetExecutionRequestId(const string value) { m_executionRequestId=value; }
   void              SetIdempotencyKey(const string value) { m_idempotencyKey=value; }
   void              SetBasketId(const CBasketId &value) { m_basketId=value; }
   void              SetExpectedBasketVersion(const int value) { m_expectedBasketVersion=value; }
   void              SetStrategyProfileHash(const string value) { m_strategyProfileHash=value; }
   void              SetIntentType(const ENUM_BRE_TRADE_EXECUTION_INTENT value) { m_intentType=value; }
   void              SetSymbol(const string value) { m_symbol=value; }
   void              SetBrokerCorrelation(const CBrokerRequestCorrelation &value) { m_brokerCorrelation=value; }
   void              SetRequestedVolume(const double value) { m_requestedVolume=value; }
   void              SetFilledVolume(const double value) { m_filledVolume=value; }
   void              SetCreatedAtUtc(const datetime value) { m_createdAtUtc=value; }
   void              SetSubmittedAtUtc(const datetime value) { m_submittedAtUtc=value; }
   void              SetDeadlineUtc(const datetime value) { m_deadlineUtc=value; }
   void              SetRetryCount(const int value) { m_retryCount=value; }
   void              SetStatus(const ENUM_BRE_TRADE_EXECUTION_STATUS value) { m_status=value; }
   void              SetCorrelationState(const ENUM_BRE_PENDING_EXECUTION_CORRELATION_STATE value) { m_correlationState=value; }
   void              SetLastTransactionKey(const string value) { m_lastTransactionKey=value; }
   void              IncrementSeenTransactionCount(void) { m_seenTransactionCount++; }

   void              AccumulateFill(const double volumeDelta)
     {
      if(volumeDelta<=0.0)
         return;
      m_filledVolume+=volumeDelta;
     }

   bool              IsPendingTimeout(const datetime nowUtc) const
     {
      if(m_deadlineUtc<=0)
         return false;
      if(m_status==BRE_TRADE_EXEC_STATUS_FILLED ||
         m_status==BRE_TRADE_EXEC_STATUS_REJECTED ||
         m_status==BRE_TRADE_EXEC_STATUS_RECONCILED)
         return false;
      return nowUtc>=m_deadlineUtc;
     }

   bool              BlocksBlindResend(void) const
     {
      return m_status==BRE_TRADE_EXEC_STATUS_UNKNOWN ||
             m_status==BRE_TRADE_EXEC_STATUS_TIMED_OUT ||
             m_status==BRE_TRADE_EXEC_STATUS_RECONCILING;
     }
  };

#endif
