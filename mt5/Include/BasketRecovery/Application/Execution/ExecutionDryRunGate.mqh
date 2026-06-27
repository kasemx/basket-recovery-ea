#ifndef BRE_APP_EXECUTION_DRY_RUN_GATE_MQH
#define BRE_APP_EXECUTION_DRY_RUN_GATE_MQH

#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionResult.mqh>

class CExecutionDryRunGate
  {
public:
   static bool       IsDryRunRouteEnabled(const ENUM_BRE_EXECUTION_RUNTIME_MODE mode,
                                          const bool enableExecutionDryRun)
     {
      return mode==BRE_EXEC_RUNTIME_MT5_DRY_RUN && enableExecutionDryRun;
     }

   static bool       IsMt5DryRunExecutorActive(const ENUM_BRE_EXECUTION_RUNTIME_MODE mode)
     {
      return mode==BRE_EXEC_RUNTIME_MT5_DRY_RUN;
     }

   static CTradeExecutionResult BuildDisabledRejection(const datetime completedAtUtc)
     {
      CTradeExecutionResult result=CTradeExecutionResult::Rejected(BRE_EXEC_FAIL_EXECUTION_DISABLED,
                                                                   "Execution disabled | requires MT5_DRY_RUN and EnableExecutionDryRun");
      result.SetCompletedAtUtc(completedAtUtc);
      return result;
     }
  };

#endif
