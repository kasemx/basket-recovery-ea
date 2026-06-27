#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_CLOSE_POSITIONS_DECISION_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_CLOSE_POSITIONS_DECISION_MQH

#include <BasketRecovery/Domain/Strategy/Enums/CloseMode.mqh>

class CClosePositionsDecision
  {
private:
   string              m_idempotencyKey;
   string              m_levelId;
   double              m_closePercent;
   ENUM_BRE_CLOSE_MODE m_closeMode;
   bool                m_partialClose;
   ulong               m_tickets[];

                     CClosePositionsDecision(void) {}

public:
   string              IdempotencyKey(void) const { return m_idempotencyKey; }
   string              LevelId(void) const { return m_levelId; }
   double              ClosePercent(void) const { return m_closePercent; }
   ENUM_BRE_CLOSE_MODE CloseMode(void) const { return m_closeMode; }
   bool                PartialClose(void) const { return m_partialClose; }
   int                 TicketCount(void) const { return ArraySize(m_tickets); }

   ulong               TicketAt(const int index) const
     {
      if(index<0 || index>=ArraySize(m_tickets))
         return 0;
      return m_tickets[index];
     }

   static CClosePositionsDecision Create(const string idempotencyKey,
                                         const string levelId,
                                         const double closePercent,
                                         const ENUM_BRE_CLOSE_MODE closeMode,
                                         const bool partialClose,
                                         const ulong &tickets[],
                                         const int ticketCount)
     {
      CClosePositionsDecision decision;
      decision.m_idempotencyKey=idempotencyKey;
      decision.m_levelId=levelId;
      decision.m_closePercent=closePercent;
      decision.m_closeMode=closeMode;
      decision.m_partialClose=partialClose;
      ArrayResize(decision.m_tickets,ticketCount);
      for(int i=0;i<ticketCount;i++)
         decision.m_tickets[i]=tickets[i];
      return decision;
     }
  };

#endif
