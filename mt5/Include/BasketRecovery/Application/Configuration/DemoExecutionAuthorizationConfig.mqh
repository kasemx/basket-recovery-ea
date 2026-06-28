#ifndef BRE_APP_DEMO_EXECUTION_AUTHORIZATION_CONFIG_MQH
#define BRE_APP_DEMO_EXECUTION_AUTHORIZATION_CONFIG_MQH

#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>

class CDemoExecutionAuthorizationConfig
  {
private:
   ENUM_BRE_EXECUTION_RUNTIME_MODE m_executionRuntimeMode;
   bool                            m_enableLiveDemoExecution;
   bool                            m_requireManualDemoAuthorization;
   bool                            m_globalExecutionKillSwitch;
   bool                            m_basketExecutionKillSwitch;
   string                          m_basketExecutionKillSwitchBasketId;
   int                             m_maxAuthorizedRequestsPerSession;
   int                             m_authorizationTokenExpirySeconds;
   double                          m_maxManualDemoOpenVolume;
   int                             m_manualRecoveryCandidateExpirySeconds;
   int                             m_maxRecoverySubmissionsPerSession;

public:
                     CDemoExecutionAuthorizationConfig(void)
     {
      m_executionRuntimeMode=BRE_EXEC_RUNTIME_DISABLED;
      m_enableLiveDemoExecution=false;
      m_requireManualDemoAuthorization=true;
      m_globalExecutionKillSwitch=false;
      m_basketExecutionKillSwitch=false;
      m_basketExecutionKillSwitchBasketId="";
      m_maxAuthorizedRequestsPerSession=1;
      m_authorizationTokenExpirySeconds=300;
      m_maxManualDemoOpenVolume=0.01;
      m_manualRecoveryCandidateExpirySeconds=30;
      m_maxRecoverySubmissionsPerSession=1;
     }

   ENUM_BRE_EXECUTION_RUNTIME_MODE ExecutionRuntimeMode(void) const { return m_executionRuntimeMode; }
   bool              EnableLiveDemoExecution(void) const { return m_enableLiveDemoExecution; }
   bool              RequireManualDemoAuthorization(void) const { return m_requireManualDemoAuthorization; }
   bool              GlobalExecutionKillSwitch(void) const { return m_globalExecutionKillSwitch; }
   bool              BasketExecutionKillSwitch(void) const { return m_basketExecutionKillSwitch; }
   string            BasketExecutionKillSwitchBasketId(void) const { return m_basketExecutionKillSwitchBasketId; }
   int               MaxAuthorizedRequestsPerSession(void) const { return m_maxAuthorizedRequestsPerSession; }
   int               AuthorizationTokenExpirySeconds(void) const { return m_authorizationTokenExpirySeconds; }
   double            MaxManualDemoOpenVolume(void) const { return m_maxManualDemoOpenVolume; }
   int               ManualRecoveryCandidateExpirySeconds(void) const { return m_manualRecoveryCandidateExpirySeconds; }
   int               MaxRecoverySubmissionsPerSession(void) const { return m_maxRecoverySubmissionsPerSession; }

   void              SetExecutionRuntimeMode(const ENUM_BRE_EXECUTION_RUNTIME_MODE value) { m_executionRuntimeMode=value; }
   void              SetEnableLiveDemoExecution(const bool value) { m_enableLiveDemoExecution=value; }
   void              SetRequireManualDemoAuthorization(const bool value) { m_requireManualDemoAuthorization=value; }
   void              SetGlobalExecutionKillSwitch(const bool value) { m_globalExecutionKillSwitch=value; }
   void              SetBasketExecutionKillSwitch(const bool value) { m_basketExecutionKillSwitch=value; }
   void              SetBasketExecutionKillSwitchBasketId(const string value) { m_basketExecutionKillSwitchBasketId=value; }
   void              SetMaxAuthorizedRequestsPerSession(const int value) { m_maxAuthorizedRequestsPerSession=value; }
   void              SetAuthorizationTokenExpirySeconds(const int value) { m_authorizationTokenExpirySeconds=value; }
   void              SetMaxManualDemoOpenVolume(const double value) { m_maxManualDemoOpenVolume=value; }
   void              SetManualRecoveryCandidateExpirySeconds(const int value) { m_manualRecoveryCandidateExpirySeconds=value; }
   void              SetMaxRecoverySubmissionsPerSession(const int value) { m_maxRecoverySubmissionsPerSession=value; }

   void              ApplyDefaultOff(void)
     {
      m_executionRuntimeMode=BRE_EXEC_RUNTIME_DISABLED;
      m_enableLiveDemoExecution=false;
      m_requireManualDemoAuthorization=true;
      m_globalExecutionKillSwitch=false;
      m_basketExecutionKillSwitch=false;
      m_basketExecutionKillSwitchBasketId="";
      m_maxAuthorizedRequestsPerSession=1;
      m_authorizationTokenExpirySeconds=300;
      m_maxManualDemoOpenVolume=0.01;
      m_manualRecoveryCandidateExpirySeconds=30;
      m_maxRecoverySubmissionsPerSession=1;
     }
  };

#endif
