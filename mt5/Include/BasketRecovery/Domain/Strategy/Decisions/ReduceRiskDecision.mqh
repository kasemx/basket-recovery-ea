#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_REDUCE_RISK_DECISION_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_REDUCE_RISK_DECISION_MQH

#include <BasketRecovery/Domain/Strategy/Enums/ExecutionZoneExpansionMode.mqh>

class CReduceRiskDecision
  {
private:
   string                      m_idempotencyKey;
   ENUM_BRE_RISK_REDUCTION_MODE m_reductionMode;
   ulong                       m_tickets[];

                     CReduceRiskDecision(void) {}

public:
   string                      IdempotencyKey(void) const { return m_idempotencyKey; }
   ENUM_BRE_RISK_REDUCTION_MODE ReductionMode(void) const { return m_reductionMode; }
   int                         TicketCount(void) const { return ArraySize(m_tickets); }

   ulong                       TicketAt(const int index) const
     {
      if(index<0 || index>=ArraySize(m_tickets))
         return 0;
      return m_tickets[index];
     }

   static CReduceRiskDecision  Create(const string idempotencyKey,
                                      const ENUM_BRE_RISK_REDUCTION_MODE reductionMode,
                                      const ulong &tickets[],
                                      const int ticketCount)
     {
      CReduceRiskDecision decision;
      decision.m_idempotencyKey=idempotencyKey;
      decision.m_reductionMode=reductionMode;
      ArrayResize(decision.m_tickets,ticketCount);
      for(int i=0;i<ticketCount;i++)
         decision.m_tickets[i]=tickets[i];
      return decision;
     }
  };

#endif
