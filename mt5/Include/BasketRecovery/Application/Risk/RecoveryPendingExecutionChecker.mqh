#ifndef BRE_APP_RECOVERY_PENDING_EXECUTION_CHECKER_MQH
#define BRE_APP_RECOVERY_PENDING_EXECUTION_CHECKER_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionLifecycleService.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>

class CRecoveryPendingExecutionChecker
  {
public:
   static bool       HasUnresolvedForBasket(const CPendingExecutionRegistry &registry,const CBasketId &basketId)
     {
      return CPendingExecutionLifecycleService::HasUnresolvedPendingExecution(registry,basketId);
     }
  };

#endif
