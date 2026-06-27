#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_DECISION_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_DECISION_MQH

#include <BasketRecovery/Domain/Strategy/Enums/StrategyDecisionType.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/OpenRecoveryPositionDecision.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/ClosePositionsDecision.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/MoveBreakEvenDecision.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/DisableRecoveryDecision.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/ReduceRiskDecision.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/NoActionDecision.mqh>

class CStrategyDecision
  {
private:
   ENUM_BRE_STRATEGY_DECISION_TYPE m_type;
   COpenRecoveryPositionDecision   m_openRecovery;
   CClosePositionsDecision         m_closePositions;
   CMoveBreakEvenDecision          m_moveBreakEven;
   CDisableRecoveryDecision        m_disableRecovery;
   CReduceRiskDecision             m_reduceRisk;
   CNoActionDecision               m_noAction;

                     CStrategyDecision(void) { m_type=BRE_STRATEGY_DECISION_NONE; }

public:
   ENUM_BRE_STRATEGY_DECISION_TYPE Type(void) const { return m_type; }
   COpenRecoveryPositionDecision   OpenRecovery(void) const { return m_openRecovery; }
   CClosePositionsDecision         ClosePositions(void) const { return m_closePositions; }
   CMoveBreakEvenDecision          MoveBreakEven(void) const { return m_moveBreakEven; }
   CDisableRecoveryDecision        DisableRecovery(void) const { return m_disableRecovery; }
   CReduceRiskDecision             ReduceRisk(void) const { return m_reduceRisk; }
   CNoActionDecision               NoAction(void) const { return m_noAction; }

   string                          IdempotencyKey(void) const
     {
      switch(m_type)
        {
         case BRE_STRATEGY_DECISION_OPEN_RECOVERY: return m_openRecovery.IdempotencyKey();
         case BRE_STRATEGY_DECISION_CLOSE_POSITIONS: return m_closePositions.IdempotencyKey();
         case BRE_STRATEGY_DECISION_MOVE_BREAK_EVEN: return m_moveBreakEven.IdempotencyKey();
         case BRE_STRATEGY_DECISION_DISABLE_RECOVERY: return m_disableRecovery.IdempotencyKey();
         case BRE_STRATEGY_DECISION_REDUCE_RISK: return m_reduceRisk.IdempotencyKey();
         case BRE_STRATEGY_DECISION_NO_ACTION: return m_noAction.IdempotencyKey();
         default: return "";
        }
     }

   static CStrategyDecision        FromOpenRecovery(const COpenRecoveryPositionDecision &decision)
     {
      CStrategyDecision wrapper;
      wrapper.m_type=BRE_STRATEGY_DECISION_OPEN_RECOVERY;
      wrapper.m_openRecovery=decision;
      return wrapper;
     }

   static CStrategyDecision        FromClosePositions(const CClosePositionsDecision &decision)
     {
      CStrategyDecision wrapper;
      wrapper.m_type=BRE_STRATEGY_DECISION_CLOSE_POSITIONS;
      wrapper.m_closePositions=decision;
      return wrapper;
     }

   static CStrategyDecision        FromMoveBreakEven(const CMoveBreakEvenDecision &decision)
     {
      CStrategyDecision wrapper;
      wrapper.m_type=BRE_STRATEGY_DECISION_MOVE_BREAK_EVEN;
      wrapper.m_moveBreakEven=decision;
      return wrapper;
     }

   static CStrategyDecision        FromDisableRecovery(const CDisableRecoveryDecision &decision)
     {
      CStrategyDecision wrapper;
      wrapper.m_type=BRE_STRATEGY_DECISION_DISABLE_RECOVERY;
      wrapper.m_disableRecovery=decision;
      return wrapper;
     }

   static CStrategyDecision        FromReduceRisk(const CReduceRiskDecision &decision)
     {
      CStrategyDecision wrapper;
      wrapper.m_type=BRE_STRATEGY_DECISION_REDUCE_RISK;
      wrapper.m_reduceRisk=decision;
      return wrapper;
     }

   static CStrategyDecision        FromNoAction(const CNoActionDecision &decision)
     {
      CStrategyDecision wrapper;
      wrapper.m_type=BRE_STRATEGY_DECISION_NO_ACTION;
      wrapper.m_noAction=decision;
      return wrapper;
     }
  };

#endif
