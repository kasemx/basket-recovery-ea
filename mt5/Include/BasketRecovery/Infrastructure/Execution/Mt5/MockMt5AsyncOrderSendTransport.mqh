#ifndef BRE_INF_MOCK_MT5_ASYNC_ORDER_SEND_TRANSPORT_MQH
#define BRE_INF_MOCK_MT5_ASYNC_ORDER_SEND_TRANSPORT_MQH

#include <BasketRecovery/Infrastructure/Execution/Mt5/IMt5AsyncOrderSendTransport.mqh>

class CMockMt5AsyncOrderSendTransport : public IMt5AsyncOrderSendTransport
  {
private:
   bool   m_nextAccepted;
   uint   m_nextRetcode;
   int    m_nextLastError;
   ulong  m_nextOrderId;
   int    m_callCount;

public:
                     CMockMt5AsyncOrderSendTransport(void)
     {
      m_nextAccepted=true;
      m_nextRetcode=TRADE_RETCODE_PLACED;
      m_nextLastError=0;
      m_nextOrderId=910001;
      m_callCount=0;
     }

   int               CallCount(void) const { return m_callCount; }

   void              SetNextAccepted(const bool accepted,const uint retcode=TRADE_RETCODE_PLACED,
                                   const int lastError=0,const ulong orderId=910001)
     {
      m_nextAccepted=accepted;
      m_nextRetcode=retcode;
      m_nextLastError=lastError;
      m_nextOrderId=orderId;
     }

   void              Reset(void) { m_callCount=0; m_nextAccepted=true; m_nextOrderId=910001; }

   virtual bool      SendAsync(MqlTradeRequest &request,MqlTradeResult &result)
     {
      m_callCount++;
      ZeroMemory(result);
      if(!m_nextAccepted)
        {
         result.retcode=m_nextRetcode;
         return false;
        }
      result.retcode=m_nextRetcode;
      result.order=m_nextOrderId;
      return true;
     }
  };

#endif
