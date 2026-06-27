#ifndef BRE_INF_SIMULATED_EXECUTION_POLICY_MQH
#define BRE_INF_SIMULATED_EXECUTION_POLICY_MQH

#include <BasketRecovery/Infrastructure/Execution/SimulatedExecutionScenario.mqh>

class CSimulatedExecutionPolicy
  {
private:
   ENUM_BRE_SIMULATED_EXECUTION_SCENARIO m_defaultScenario;
   string                              m_idempotencyKeys[];
   ENUM_BRE_SIMULATED_EXECUTION_SCENARIO m_scenarios[];
   int                                 m_count;

   int               FindIndex(const string idempotencyKey) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_idempotencyKeys[i]==idempotencyKey)
            return i;
        }
      return -1;
     }

public:
                     CSimulatedExecutionPolicy(void)
     {
      m_defaultScenario=BRE_SIM_EXEC_DEFAULT_ACCEPT_FILL;
      m_count=0;
     }

   void              SetDefaultScenario(const ENUM_BRE_SIMULATED_EXECUTION_SCENARIO scenario)
     {
      m_defaultScenario=scenario;
     }

   void              SetScenarioForIdempotencyKey(const string idempotencyKey,
                                                  const ENUM_BRE_SIMULATED_EXECUTION_SCENARIO scenario)
     {
      int index=FindIndex(idempotencyKey);
      if(index>=0)
        {
         m_scenarios[index]=scenario;
         return;
        }
      ArrayResize(m_idempotencyKeys,m_count+1);
      ArrayResize(m_scenarios,m_count+1);
      m_idempotencyKeys[m_count]=idempotencyKey;
      m_scenarios[m_count]=scenario;
      m_count++;
     }

   ENUM_BRE_SIMULATED_EXECUTION_SCENARIO ResolveScenario(const string idempotencyKey) const
     {
      int index=FindIndex(idempotencyKey);
      if(index>=0)
         return m_scenarios[index];

      if(StringFind(idempotencyKey,"sim:reject:")==0)
         return BRE_SIM_EXEC_REJECTED;
      if(StringFind(idempotencyKey,"sim:timeout:")==0)
         return BRE_SIM_EXEC_TIMEOUT;
      if(StringFind(idempotencyKey,"sim:partial-fill:")==0)
         return BRE_SIM_EXEC_PARTIAL_THEN_FILLED;
      if(StringFind(idempotencyKey,"sim:partial-reject:")==0)
         return BRE_SIM_EXEC_PARTIAL_THEN_REJECTED;
      if(StringFind(idempotencyKey,"sim:unknown:")==0)
         return BRE_SIM_EXEC_UNKNOWN;

      return m_defaultScenario;
     }
  };

#endif
