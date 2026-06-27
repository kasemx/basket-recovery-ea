#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_PROFIT_LEVEL_RUNTIME_STATE_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_PROFIT_LEVEL_RUNTIME_STATE_MQH

class CProfitLevelRuntimeState
  {
private:
   string m_levelId;
   bool   m_reached;
   bool   m_executed;
   double m_triggerPrice;
   bool   m_hasTriggerPrice;

                     CProfitLevelRuntimeState(void) {}

public:
   string            LevelId(void) const { return m_levelId; }
   bool              Reached(void) const { return m_reached; }
   bool              Executed(void) const { return m_executed; }
   bool              HasTriggerPrice(void) const { return m_hasTriggerPrice; }
   double            TriggerPrice(void) const { return m_triggerPrice; }

   static CProfitLevelRuntimeState Create(const string levelId,
                                          const bool reached,
                                          const bool executed,
                                          const double triggerPrice,
                                          const bool hasTriggerPrice)
     {
      CProfitLevelRuntimeState state;
      state.m_levelId=levelId;
      state.m_reached=reached;
      state.m_executed=executed;
      state.m_triggerPrice=triggerPrice;
      state.m_hasTriggerPrice=hasTriggerPrice;
      return state;
     }
  };

#endif
