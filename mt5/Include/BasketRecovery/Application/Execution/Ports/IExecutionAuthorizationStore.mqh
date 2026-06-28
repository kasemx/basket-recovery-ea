#ifndef BRE_APP_PORTS_IEXECUTION_AUTHORIZATION_STORE_MQH
#define BRE_APP_PORTS_IEXECUTION_AUTHORIZATION_STORE_MQH

#include <BasketRecovery/Domain/Execution/ManualDemoExecutionAuthorization.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class IExecutionAuthorizationStore
  {
public:
   virtual          ~IExecutionAuthorizationStore(void) {}
   virtual CVoidResult Save(const CManualDemoExecutionAuthorization &record)=0;
   virtual bool      TryGetByTokenHash(const string tokenHash,CManualDemoExecutionAuthorization &record) const=0;
   virtual int         RestoreRecords(CManualDemoExecutionAuthorization &records[]) const=0;
   virtual CVoidResult Clear(void)=0;
  };

#endif
