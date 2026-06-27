#ifndef BASKET_RECOVERY_INFRASTRUCTURE_EXECUTION_POLICY_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_EXECUTION_POLICY_MQH

class CExecutionPolicy
  {
private:
   int    m_maxRetries;
   int    m_slippagePoints;
   int    m_executionTimeoutMs;
   int    m_retryDelayMs;
   int    m_fillingMode;
   bool   m_enableExecution;
   bool   m_dryRunMode;
   bool   m_mockExecution;
   bool   m_simulationMode;

public:
                     CExecutionPolicy(void)
     {
      m_maxRetries=3;
      m_slippagePoints=10;
      m_executionTimeoutMs=5000;
      m_retryDelayMs=500;
      m_fillingMode=ORDER_FILLING_IOC;
      m_enableExecution=false;
      m_dryRunMode=false;
      m_mockExecution=false;
      m_simulationMode=false;
     }

   int               MaxRetries(void) const { return m_maxRetries; }
   int               SlippagePoints(void) const { return m_slippagePoints; }
   int               ExecutionTimeoutMs(void) const { return m_executionTimeoutMs; }
   int               RetryDelayMs(void) const { return m_retryDelayMs; }
   int               FillingMode(void) const { return m_fillingMode; }
   bool              EnableExecution(void) const { return m_enableExecution; }
   bool              DryRunMode(void) const { return m_dryRunMode; }
   bool              MockExecution(void) const { return m_mockExecution; }
   bool              SimulationMode(void) const { return m_simulationMode; }

   void              SetMaxRetries(const int value) { m_maxRetries=value; }
   void              SetSlippagePoints(const int value) { m_slippagePoints=value; }
   void              SetExecutionTimeoutMs(const int value) { m_executionTimeoutMs=value; }
   void              SetRetryDelayMs(const int value) { m_retryDelayMs=value; }
   void              SetFillingMode(const int value) { m_fillingMode=value; }
   void              SetEnableExecution(const bool value) { m_enableExecution=value; }
   void              SetDryRunMode(const bool value) { m_dryRunMode=value; }
   void              SetMockExecution(const bool value) { m_mockExecution=value; }
   void              SetSimulationMode(const bool value) { m_simulationMode=value; }

   bool              ShouldExecuteLive(void) const
     {
      return m_enableExecution && !m_dryRunMode && !m_mockExecution && !m_simulationMode;
     }

   bool              IsRetryAllowed(const int attemptIndex) const
     {
      return attemptIndex<m_maxRetries;
     }
  };

#endif
