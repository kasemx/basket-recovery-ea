#ifndef BRE_APP_IBROKER_EXECUTION_HISTORY_READER_MQH
#define BRE_APP_IBROKER_EXECUTION_HISTORY_READER_MQH

#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/BrokerExecutionHistoryCorrelation.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class IBrokerExecutionHistoryReader
  {
public:
   virtual          ~IBrokerExecutionHistoryReader(void) {}
   virtual CResult<bool> CorrelateExecutionHistory(const CPendingExecutionEntry &entry,
                                                   CBrokerExecutionHistoryCorrelation &outCorrelation) const=0;
  };

#endif
