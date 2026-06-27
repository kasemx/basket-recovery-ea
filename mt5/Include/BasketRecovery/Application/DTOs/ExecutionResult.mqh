#ifndef BASKET_RECOVERY_APPLICATION_EXECUTION_RESULT_MQH
#define BASKET_RECOVERY_APPLICATION_EXECUTION_RESULT_MQH

enum ENUM_BRE_EXECUTION_STATUS
  {
   BRE_EXECUTION_STATUS_NONE=0,
   BRE_EXECUTION_STATUS_FILLED,
   BRE_EXECUTION_STATUS_REJECTED,
   BRE_EXECUTION_STATUS_DRY_RUN,
   BRE_EXECUTION_STATUS_SIMULATED,
   BRE_EXECUTION_STATUS_CANCELLED
  };

class CExecutionResult
  {
private:
   bool                      m_success;
   bool                      m_retryable;
   ENUM_BRE_EXECUTION_STATUS m_status;
   int                       m_errorCode;
   string                    m_message;
   ulong                     m_ticket;
   ulong                     m_order;
   double                    m_price;
   double                    m_volume;
   uint                      m_retcode;
   int                       m_latencyMs;
   int                       m_attemptCount;

public:
                     CExecutionResult(void)
     {
      m_success=false;
      m_retryable=false;
      m_status=BRE_EXECUTION_STATUS_NONE;
      m_errorCode=0;
      m_message="";
      m_ticket=0;
      m_order=0;
      m_price=0.0;
      m_volume=0.0;
      m_retcode=0;
      m_latencyMs=0;
      m_attemptCount=0;
     }

   bool                      Success(void) const { return m_success; }
   bool                      Retryable(void) const { return m_retryable; }
   ENUM_BRE_EXECUTION_STATUS Status(void) const { return m_status; }
   int                       ErrorCode(void) const { return m_errorCode; }
   string                    Message(void) const { return m_message; }
   ulong                     Ticket(void) const { return m_ticket; }
   ulong                     Order(void) const { return m_order; }
   double                    Price(void) const { return m_price; }
   double                    Volume(void) const { return m_volume; }
   uint                      Retcode(void) const { return m_retcode; }
   int                       LatencyMs(void) const { return m_latencyMs; }
   int                       AttemptCount(void) const { return m_attemptCount; }

   void                      SetSuccess(const bool value) { m_success=value; }
   void                      SetRetryable(const bool value) { m_retryable=value; }
   void                      SetStatus(const ENUM_BRE_EXECUTION_STATUS value) { m_status=value; }
   void                      SetErrorCode(const int value) { m_errorCode=value; }
   void                      SetMessage(const string value) { m_message=value; }
   void                      SetTicket(const ulong value) { m_ticket=value; }
   void                      SetOrder(const ulong value) { m_order=value; }
   void                      SetPrice(const double value) { m_price=value; }
   void                      SetVolume(const double value) { m_volume=value; }
   void                      SetRetcode(const uint value) { m_retcode=value; }
   void                      SetLatencyMs(const int value) { m_latencyMs=value; }
   void                      SetAttemptCount(const int value) { m_attemptCount=value; }
  };

#endif
