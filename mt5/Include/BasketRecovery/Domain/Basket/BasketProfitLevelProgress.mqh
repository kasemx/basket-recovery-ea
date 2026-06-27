#ifndef BASKET_RECOVERY_DOMAIN_BASKET_PROFIT_LEVEL_PROGRESS_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_PROFIT_LEVEL_PROGRESS_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Shared/Types/Money.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

class CBasketProfitLevelProgress
  {
private:
   string     m_levelId;
   bool       m_reached;
   bool       m_closeRequested;
   bool       m_closeCompleted;
   CMoney     m_realizedProfit;
   CUtcTime   m_reachedAtUtc;
   CUtcTime   m_completedAtUtc;
   CCommandId m_executionCommandId;
   CEventId   m_executionEventId;

                     CBasketProfitLevelProgress(void) {}

public:
   string     LevelId(void) const { return m_levelId; }
   bool       Reached(void) const { return m_reached; }
   bool       CloseRequested(void) const { return m_closeRequested; }
   bool       CloseCompleted(void) const { return m_closeCompleted; }
   CMoney     RealizedProfit(void) const { return m_realizedProfit; }
   CUtcTime   ReachedAtUtc(void) const { return m_reachedAtUtc; }
   CUtcTime   CompletedAtUtc(void) const { return m_completedAtUtc; }
   CCommandId ExecutionCommandId(void) const { return m_executionCommandId; }
   CEventId   ExecutionEventId(void) const { return m_executionEventId; }

   static CBasketProfitLevelProgress CreateEmpty(const string levelId)
     {
      CBasketProfitLevelProgress progress;
      progress.m_levelId=levelId;
      return progress;
     }

   static CBasketProfitLevelProgress CreateReached(const string levelId,
                                                   const CUtcTime reachedAtUtc,
                                                   const CCommandId &commandId,
                                                   const CEventId &eventId)
     {
      CBasketProfitLevelProgress progress;
      progress.m_levelId=levelId;
      progress.m_reached=true;
      progress.m_reachedAtUtc=reachedAtUtc;
      progress.m_executionCommandId=commandId;
      progress.m_executionEventId=eventId;
      return progress;
     }

   CBasketProfitLevelProgress WithCloseRequested(const CUtcTime timestampUtc,
                                                 const CCommandId &commandId) const
     {
      CBasketProfitLevelProgress copy;
      copy.m_levelId=m_levelId;
      copy.m_reached=m_reached;
      copy.m_closeRequested=true;
      copy.m_closeCompleted=m_closeCompleted;
      copy.m_realizedProfit=m_realizedProfit;
      copy.m_reachedAtUtc=timestampUtc;
      copy.m_completedAtUtc=m_completedAtUtc;
      copy.m_executionCommandId=commandId;
      copy.m_executionEventId=m_executionEventId;
      return copy;
     }

   CBasketProfitLevelProgress WithCloseCompleted(const CMoney &realizedProfit,
                                                   const CUtcTime completedAtUtc,
                                                   const CEventId &eventId) const
     {
      CBasketProfitLevelProgress copy;
      copy.m_levelId=m_levelId;
      copy.m_reached=m_reached;
      copy.m_closeRequested=m_closeRequested;
      copy.m_closeCompleted=true;
      copy.m_realizedProfit=realizedProfit;
      copy.m_reachedAtUtc=m_reachedAtUtc;
      copy.m_completedAtUtc=completedAtUtc;
      copy.m_executionCommandId=m_executionCommandId;
      copy.m_executionEventId=eventId;
      return copy;
     }
  };

#endif
