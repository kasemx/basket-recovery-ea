#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_DOMAIN_EVENT_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_DOMAIN_EVENT_MQH

#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Domain/Enums/CommandType.mqh>

class CStrategyDomainEvent : public CDomainEvent
  {
private:
   string              m_levelId;
   string              m_ruleId;
   double              m_realizedProfit;
   ENUM_BRE_COMMAND_TYPE m_sourceCommandType;

public:
                     CStrategyDomainEvent(void)
     {
      m_levelId="";
      m_ruleId="";
      m_realizedProfit=0.0;
      m_sourceCommandType=BRE_COMMAND_NONE;
     }

   string              LevelId(void) const { return m_levelId; }
   string              RuleId(void) const { return m_ruleId; }
   double              RealizedProfit(void) const { return m_realizedProfit; }
   ENUM_BRE_COMMAND_TYPE SourceCommandType(void) const { return m_sourceCommandType; }

   void                SetLevelId(const string value) { m_levelId=value; }
   void                SetRuleId(const string value) { m_ruleId=value; }
   void                SetRealizedProfit(const double value) { m_realizedProfit=value; }
   void                SetSourceCommandType(const ENUM_BRE_COMMAND_TYPE value) { m_sourceCommandType=value; }
  };

#endif
