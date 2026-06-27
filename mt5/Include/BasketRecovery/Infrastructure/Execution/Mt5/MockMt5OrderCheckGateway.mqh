#ifndef BRE_INF_MOCK_MT5_ORDER_CHECK_GATEWAY_MQH
#define BRE_INF_MOCK_MT5_ORDER_CHECK_GATEWAY_MQH

#include <BasketRecovery/Infrastructure/Execution/Mt5/IMt5OrderCheckGateway.mqh>

class CMockMt5OrderCheckGateway : public IMt5OrderCheckGateway
  {
private:
   bool   m_nextSuccess;
   uint   m_nextRetcode;
   string m_nextComment;
   int    m_callCount;

public:
                     CMockMt5OrderCheckGateway(void)
     {
      m_nextSuccess=true;
      m_nextRetcode=TRADE_RETCODE_DONE;
      m_nextComment="mock ok";
      m_callCount=0;
     }

   int               CallCount(void) const { return m_callCount; }

   void              SetNextResult(const bool success,const uint retcode,const string comment)
     {
      m_nextSuccess=success;
      m_nextRetcode=retcode;
      m_nextComment=comment;
     }

   virtual bool      Check(MqlTradeRequest &request,MqlTradeCheckResult &outResult)
     {
      m_callCount++;
      ZeroMemory(outResult);
      outResult.retcode=m_nextRetcode;
      outResult.comment=m_nextComment;
      return m_nextSuccess;
     }
  };

#endif
