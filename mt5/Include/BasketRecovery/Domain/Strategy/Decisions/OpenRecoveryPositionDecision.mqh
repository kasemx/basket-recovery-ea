#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_OPEN_RECOVERY_DECISION_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_OPEN_RECOVERY_DECISION_MQH

#include <BasketRecovery/Domain/Enums/TradeRole.mqh>

class COpenRecoveryPositionDecision
  {
private:
   string                m_idempotencyKey;
   int                   m_stepIndex;
   double                m_distancePips;
   double                m_lot;
   double                m_expectedEntryPrice;
   ENUM_BRE_TRADE_ROLE   m_tradeRole;

public:
                     COpenRecoveryPositionDecision(void) {}

                     COpenRecoveryPositionDecision(const COpenRecoveryPositionDecision &other)
     {
      m_idempotencyKey=other.m_idempotencyKey;
      m_stepIndex=other.m_stepIndex;
      m_distancePips=other.m_distancePips;
      m_lot=other.m_lot;
      m_expectedEntryPrice=other.m_expectedEntryPrice;
      m_tradeRole=other.m_tradeRole;
     }

   string                IdempotencyKey(void) const { return m_idempotencyKey; }
   int                   StepIndex(void) const { return m_stepIndex; }
   double                DistancePips(void) const { return m_distancePips; }
   double                Lot(void) const { return m_lot; }
   double                ExpectedEntryPrice(void) const { return m_expectedEntryPrice; }
   ENUM_BRE_TRADE_ROLE   TradeRole(void) const { return m_tradeRole; }

   static COpenRecoveryPositionDecision Create(const string idempotencyKey,
                                               const int stepIndex,
                                               const double distancePips,
                                               const double lot,
                                               const double expectedEntryPrice,
                                               const ENUM_BRE_TRADE_ROLE tradeRole)
     {
      COpenRecoveryPositionDecision decision;
      decision.m_idempotencyKey=idempotencyKey;
      decision.m_stepIndex=stepIndex;
      decision.m_distancePips=distancePips;
      decision.m_lot=lot;
      decision.m_expectedEntryPrice=expectedEntryPrice;
      decision.m_tradeRole=tradeRole;
      return decision;
     }
  };

#endif
