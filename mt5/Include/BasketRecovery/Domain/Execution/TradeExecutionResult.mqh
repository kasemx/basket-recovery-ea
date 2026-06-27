#ifndef BRE_DOMAIN_TRADE_EXECUTION_RESULT_MQH
#define BRE_DOMAIN_TRADE_EXECUTION_RESULT_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionFailureReason.mqh>

class CTradeExecutionResult
  {
private:
   ENUM_BRE_TRADE_EXECUTION_STATUS         m_status;
   ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON m_failureReason;
   string                                  m_message;
   double                                  m_requestedVolume;
   double                                  m_filledVolume;
   double                                  m_fillPrice;
   ulong                                   m_brokerTicket;
   string                                  m_brokerCorrelationId;
   datetime                                m_completedAtUtc;

public:
                     CTradeExecutionResult(void)
     {
      m_status=BRE_TRADE_EXEC_STATUS_NONE;
      m_failureReason=BRE_EXEC_FAIL_NONE;
      m_message="";
      m_requestedVolume=0.0;
      m_filledVolume=0.0;
      m_fillPrice=0.0;
      m_brokerTicket=0;
      m_brokerCorrelationId="";
      m_completedAtUtc=0;
     }

   ENUM_BRE_TRADE_EXECUTION_STATUS         Status(void) const { return m_status; }
   ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON FailureReason(void) const { return m_failureReason; }
   string                                  Message(void) const { return m_message; }
   double                                  RequestedVolume(void) const { return m_requestedVolume; }
   double                                  FilledVolume(void) const { return m_filledVolume; }
   double                                  FillPrice(void) const { return m_fillPrice; }
   ulong                                   BrokerTicket(void) const { return m_brokerTicket; }
   string                                  BrokerCorrelationId(void) const { return m_brokerCorrelationId; }
   datetime                                CompletedAtUtc(void) const { return m_completedAtUtc; }

   void              SetStatus(const ENUM_BRE_TRADE_EXECUTION_STATUS value) { m_status=value; }
   void              SetFailureReason(const ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON value) { m_failureReason=value; }
   void              SetMessage(const string value) { m_message=value; }
   void              SetRequestedVolume(const double value) { m_requestedVolume=value; }
   void              SetFilledVolume(const double value) { m_filledVolume=value; }
   void              SetFillPrice(const double value) { m_fillPrice=value; }
   void              SetBrokerTicket(const ulong value) { m_brokerTicket=value; }
   void              SetBrokerCorrelationId(const string value) { m_brokerCorrelationId=value; }
   void              SetCompletedAtUtc(const datetime value) { m_completedAtUtc=value; }

   static CTradeExecutionResult Rejected(const ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON reason,
                                         const string message,
                                         const double requestedVolume=0.0)
     {
      CTradeExecutionResult result;
      result.m_status=BRE_TRADE_EXEC_STATUS_REJECTED;
      result.m_failureReason=reason;
      result.m_message=message;
      result.m_requestedVolume=requestedVolume;
      result.m_filledVolume=0.0;
      return result;
     }
  };

#endif
