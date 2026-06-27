#ifndef BRE_APP_SUBMISSION_GATEWAY_COMPOSITION_GUARD_MQH
#define BRE_APP_SUBMISSION_GATEWAY_COMPOSITION_GUARD_MQH

#include <BasketRecovery/Application/Execution/Ports/ISubmissionGateway.mqh>

class CSubmissionGatewayCompositionGuard
  {
public:
   static bool       AllowsProductionAutoWire(const int executionMode,const ISubmissionGateway *gateway)
     {
      if(gateway==NULL)
         return false;
      if(gateway.IsSimulated())
         return false;
      return executionMode>0;
     }

   static bool       BlocksBootstrapRegistration(const ISubmissionGateway *gateway)
     {
      if(gateway==NULL)
         return false;
      return gateway.IsSimulated();
     }

   static bool       RequiresExplicitExecutionModeGate(const ISubmissionGateway *gateway)
     {
      return gateway!=NULL;
     }
  };

#endif
