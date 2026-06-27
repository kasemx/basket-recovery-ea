#ifndef BRE_APP_PENDING_EXECUTION_EVENT_BUFFER_MQH
#define BRE_APP_PENDING_EXECUTION_EVENT_BUFFER_MQH

#include <BasketRecovery/Domain/Execution/TradeTransactionResultCode.mqh>

class CPendingExecutionEvent
  {
private:
   string                              m_executionRequestId;
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE m_resultCode;
   string                              m_detail;
   datetime                            m_occurredAtUtc;

public:
                     CPendingExecutionEvent(void)
     {
      m_executionRequestId="";
      m_resultCode=BRE_TRADE_TX_RESULT_NONE;
      m_detail="";
      m_occurredAtUtc=0;
     }

   string            ExecutionRequestId(void) const { return m_executionRequestId; }
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE ResultCode(void) const { return m_resultCode; }
   string            Detail(void) const { return m_detail; }
   datetime          OccurredAtUtc(void) const { return m_occurredAtUtc; }

   void              SetExecutionRequestId(const string value) { m_executionRequestId=value; }
   void              SetResultCode(const ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE value) { m_resultCode=value; }
   void              SetDetail(const string value) { m_detail=value; }
   void              SetOccurredAtUtc(const datetime value) { m_occurredAtUtc=value; }
  };

class CInMemoryPendingExecutionEventBuffer
  {
private:
   CPendingExecutionEvent m_events[];
   int                    m_capacity;
   int                    m_writeIndex;
   int                    m_count;

public:
                     CInMemoryPendingExecutionEventBuffer(const int capacity=32)
     {
      m_capacity=(capacity<=0 ? 32 : capacity);
      m_writeIndex=0;
      m_count=0;
      ArrayResize(m_events,m_capacity);
     }

   int               Count(void) const { return m_count; }
   int               Capacity(void) const { return m_capacity; }

   void              Append(const CPendingExecutionEvent &event)
     {
      m_events[m_writeIndex]=event;
      m_writeIndex=(m_writeIndex+1)%m_capacity;
      if(m_count<m_capacity)
         m_count++;
     }

   bool              TryGetLatest(CPendingExecutionEvent &event) const
     {
      if(m_count<=0)
         return false;
      int index=(m_writeIndex-1+m_capacity)%m_capacity;
      event=m_events[index];
      return true;
     }

   void              Clear(void)
     {
      m_writeIndex=0;
      m_count=0;
     }
  };

#endif
