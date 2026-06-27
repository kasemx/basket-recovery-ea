#ifndef BRE_APP_ISUBMISSION_GATEWAY_MQH
#define BRE_APP_ISUBMISSION_GATEWAY_MQH

#include <BasketRecovery/Domain/Execution/BrokerSubmissionEnvelope.mqh>
#include <BasketRecovery/Domain/Execution/SubmissionGatewayResult.mqh>

class ISubmissionGateway
  {
public:
   virtual          ~ISubmissionGateway(void) {}
   virtual CSubmissionGatewayResult Submit(const CBrokerSubmissionEnvelope &envelope)=0;
   virtual bool      IsSimulated(void) const=0;
  };

#endif
