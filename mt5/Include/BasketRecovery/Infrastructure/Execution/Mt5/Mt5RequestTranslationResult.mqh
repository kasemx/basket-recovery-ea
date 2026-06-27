#ifndef BRE_INF_MT5_REQUEST_TRANSLATION_RESULT_MQH
#define BRE_INF_MT5_REQUEST_TRANSLATION_RESULT_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionFailureReason.mqh>

class CMt5RequestTranslationResult
  {
private:
   bool                                    m_success;
   ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON m_failureReason;
   string                                  m_message;
   MqlTradeRequest                         m_request;
   string                                  m_summary;

public:
                     CMt5RequestTranslationResult(void)
     {
      m_success=false;
      m_failureReason=BRE_EXEC_FAIL_VALIDATION;
      m_message="";
      ZeroMemory(m_request);
      m_summary="";
     }

   bool              Success(void) const { return m_success; }
   ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON FailureReason(void) const { return m_failureReason; }
   string            Message(void) const { return m_message; }
   MqlTradeRequest   Request(void) const { return m_request; }
   string            Summary(void) const { return m_summary; }

   void              SetSuccess(const MqlTradeRequest &request,const string summary)
     {
      m_success=true;
      m_failureReason=BRE_EXEC_FAIL_NONE;
      m_message="";
      m_request=request;
      m_summary=summary;
     }

   void              SetFailure(const ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON reason,const string message)
     {
      m_success=false;
      m_failureReason=reason;
      m_message=message;
      ZeroMemory(m_request);
      m_summary="";
     }
  };

#endif
