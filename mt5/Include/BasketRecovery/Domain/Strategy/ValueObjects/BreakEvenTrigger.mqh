#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_BREAK_EVEN_TRIGGER_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_BREAK_EVEN_TRIGGER_MQH

#include <BasketRecovery/Domain/Strategy/Enums/BreakEvenTriggerType.mqh>

class CBreakEvenTrigger
  {
private:
   ENUM_BRE_BREAK_EVEN_TRIGGER_TYPE m_type;
   double                           m_realizedProfitUsd;
   bool                             m_hasRealizedProfitUsd;
   double                           m_floatingProfitUsd;
   bool                             m_hasFloatingProfitUsd;
   double                           m_percentOfTargetRisk;
   bool                             m_hasPercentOfTargetRisk;
   string                           m_profitLevelId;
   string                           m_basketState;
   string                           m_eventType;
   string                           m_manualToken;

                     CBreakEvenTrigger(void) {}

public:
   ENUM_BRE_BREAK_EVEN_TRIGGER_TYPE Type(void) const { return m_type; }
   bool                             HasRealizedProfitUsd(void) const { return m_hasRealizedProfitUsd; }
   double                           RealizedProfitUsd(void) const { return m_realizedProfitUsd; }
   bool                             HasFloatingProfitUsd(void) const { return m_hasFloatingProfitUsd; }
   double                           FloatingProfitUsd(void) const { return m_floatingProfitUsd; }
   bool                             HasPercentOfTargetRisk(void) const { return m_hasPercentOfTargetRisk; }
   double                           PercentOfTargetRisk(void) const { return m_percentOfTargetRisk; }
   string                           ProfitLevelId(void) const { return m_profitLevelId; }
   string                           BasketState(void) const { return m_basketState; }
   string                           EventType(void) const { return m_eventType; }
   string                           ManualToken(void) const { return m_manualToken; }

   static CBreakEvenTrigger         Create(const ENUM_BRE_BREAK_EVEN_TRIGGER_TYPE type,
                                           const double realizedProfitUsd,
                                           const bool hasRealizedProfitUsd,
                                           const double floatingProfitUsd,
                                           const bool hasFloatingProfitUsd,
                                           const double percentOfTargetRisk,
                                           const bool hasPercentOfTargetRisk,
                                           const string profitLevelId,
                                           const string basketState,
                                           const string eventType,
                                           const string manualToken)
     {
      CBreakEvenTrigger trigger;
      trigger.m_type=type;
      trigger.m_realizedProfitUsd=realizedProfitUsd;
      trigger.m_hasRealizedProfitUsd=hasRealizedProfitUsd;
      trigger.m_floatingProfitUsd=floatingProfitUsd;
      trigger.m_hasFloatingProfitUsd=hasFloatingProfitUsd;
      trigger.m_percentOfTargetRisk=percentOfTargetRisk;
      trigger.m_hasPercentOfTargetRisk=hasPercentOfTargetRisk;
      trigger.m_profitLevelId=profitLevelId;
      trigger.m_basketState=basketState;
      trigger.m_eventType=eventType;
      trigger.m_manualToken=manualToken;
      return trigger;
     }
  };

#endif
