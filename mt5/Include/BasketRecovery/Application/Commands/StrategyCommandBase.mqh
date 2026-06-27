#ifndef BASKET_RECOVERY_APPLICATION_STRATEGY_COMMAND_BASE_MQH
#define BASKET_RECOVERY_APPLICATION_STRATEGY_COMMAND_BASE_MQH

#include <BasketRecovery/Application/Commands/CommandBase.mqh>

class CStrategyCommandBase : public CCommandBase
  {
protected:
   long   m_expectedBasketVersion;
   string m_strategyProfileHash;

public:
                     CStrategyCommandBase(void)
     {
      m_expectedBasketVersion=-1;
      m_strategyProfileHash="";
     }

   long                ExpectedBasketVersion(void) const { return m_expectedBasketVersion; }
   string              StrategyProfileHash(void) const { return m_strategyProfileHash; }

   void                SetExpectedBasketVersion(const long value) { m_expectedBasketVersion=value; }
   void                SetStrategyProfileHash(const string value) { m_strategyProfileHash=value; }
  };

#endif
