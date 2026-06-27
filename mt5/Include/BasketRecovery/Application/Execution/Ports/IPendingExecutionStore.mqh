#ifndef BRE_APP_IPENDING_EXECUTION_STORE_MQH
#define BRE_APP_IPENDING_EXECUTION_STORE_MQH

#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionEnvelope.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class IPendingExecutionStore
  {
public:
   virtual          ~IPendingExecutionStore(void) {}
   virtual CVoidResult SavePreparedState(const CPendingExecutionEntry &entry,
                                         const CBrokerSubmissionEnvelope &envelope)=0;
   virtual CResult<CBrokerSubmissionEnvelope> FindEnvelopeByIdempotencyKey(const string idempotencyKey) const=0;
   virtual int         RestoreEntries(CPendingExecutionEntry &entries[]) const=0;
   virtual CVoidResult Clear(void)=0;
  };

#endif
