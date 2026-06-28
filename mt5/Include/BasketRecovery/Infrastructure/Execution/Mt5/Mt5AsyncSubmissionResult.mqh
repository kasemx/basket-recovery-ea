#ifndef BRE_INF_MT5_ASYNC_SUBMISSION_RESULT_MQH
#define BRE_INF_MT5_ASYNC_SUBMISSION_RESULT_MQH

class CMt5AsyncSubmissionResult
  {
private:
   bool   m_accepted;
   uint   m_retcode;
   int    m_lastError;
   ulong  m_brokerOrderId;
   string m_detail;

public:
                     CMt5AsyncSubmissionResult(void)
     {
      m_accepted=false;
      m_retcode=0;
      m_lastError=0;
      m_brokerOrderId=0;
     }

   bool              IsAccepted(void) const { return m_accepted; }
   uint              Retcode(void) const { return m_retcode; }
   int               LastError(void) const { return m_lastError; }
   ulong             BrokerOrderId(void) const { return m_brokerOrderId; }
   string            Detail(void) const { return m_detail; }

   void              SetAccepted(const uint retcode,const ulong brokerOrderId,const string detail="")
     {
      m_accepted=true;
      m_retcode=retcode;
      m_brokerOrderId=brokerOrderId;
      m_detail=detail;
     }

   void              SetRejected(const int lastError,const uint retcode,const string detail)
     {
      m_accepted=false;
      m_lastError=lastError;
      m_retcode=retcode;
      m_detail=detail;
     }
  };

#endif
