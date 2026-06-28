#ifndef BRE_APP_EXECUTION_AUTHORIZATION_POLICY_MQH
#define BRE_APP_EXECUTION_AUTHORIZATION_POLICY_MQH

#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationScope.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>

class CExecutionAuthorizationPolicy
  {
public:
   static ENUM_BRE_EXECUTION_AUTHORIZATION_SCOPE DefaultRuntimeScope(void)
     {
      return BRE_AUTH_SCOPE_LIVE_DISABLED;
     }

   static bool       AllowsFutureSubmissionAuthorization(const CDemoExecutionAuthorizationConfig &config)
     {
      if(config.GlobalExecutionKillSwitch())
         return false;
      if(!config.EnableLiveDemoExecution())
         return false;
      return config.ExecutionRuntimeMode()==BRE_EXEC_RUNTIME_DEMO_AUTHORIZATION;
     }

   static ENUM_BRE_EXECUTION_AUTHORIZATION_SCOPE ResolveScope(const CDemoExecutionAuthorizationConfig &config)
     {
      if(!AllowsFutureSubmissionAuthorization(config))
         return BRE_AUTH_SCOPE_LIVE_DISABLED;
      return BRE_AUTH_SCOPE_DEMO_SINGLE_REQUEST;
     }

   static bool       PassesDailyLossPlaceholder(void) { return true; }
   static bool       PassesMaxConcurrentPlaceholder(void) { return true; }

   static bool       IsBasketKillSwitchActive(const CDemoExecutionAuthorizationConfig &config,
                                              const string basketIdValue)
     {
      if(!config.BasketExecutionKillSwitch())
         return false;
      if(config.BasketExecutionKillSwitchBasketId()=="")
         return true;
      return config.BasketExecutionKillSwitchBasketId()==basketIdValue;
     }
  };

#endif
