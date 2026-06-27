#ifndef BRE_DOMAIN_EXECUTION_STATUS_TRANSITION_MQH
#define BRE_DOMAIN_EXECUTION_STATUS_TRANSITION_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>

class CExecutionStatusTransition
  {
private:
   ENUM_BRE_TRADE_EXECUTION_STATUS m_fromStatus;
   ENUM_BRE_TRADE_EXECUTION_STATUS m_toStatus;
   datetime                        m_occurredAtUtc;
   string                          m_detail;

public:
                     CExecutionStatusTransition(void)
     {
      m_fromStatus=BRE_TRADE_EXEC_STATUS_NONE;
      m_toStatus=BRE_TRADE_EXEC_STATUS_NONE;
      m_occurredAtUtc=0;
      m_detail="";
     }

   ENUM_BRE_TRADE_EXECUTION_STATUS FromStatus(void) const { return m_fromStatus; }
   ENUM_BRE_TRADE_EXECUTION_STATUS ToStatus(void) const { return m_toStatus; }
   datetime                        OccurredAtUtc(void) const { return m_occurredAtUtc; }
   string                          Detail(void) const { return m_detail; }

   void              SetFromStatus(const ENUM_BRE_TRADE_EXECUTION_STATUS value) { m_fromStatus=value; }
   void              SetToStatus(const ENUM_BRE_TRADE_EXECUTION_STATUS value) { m_toStatus=value; }
   void              SetOccurredAtUtc(const datetime value) { m_occurredAtUtc=value; }
   void              SetDetail(const string value) { m_detail=value; }

   static CExecutionStatusTransition Create(const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus,
                                            const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus,
                                            const datetime occurredAtUtc,
                                            const string detail="")
     {
      CExecutionStatusTransition transition;
      transition.m_fromStatus=fromStatus;
      transition.m_toStatus=toStatus;
      transition.m_occurredAtUtc=occurredAtUtc;
      transition.m_detail=detail;
      return transition;
     }
  };

#endif
