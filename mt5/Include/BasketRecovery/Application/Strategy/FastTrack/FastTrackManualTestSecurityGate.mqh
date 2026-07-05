#ifndef BRE_APP_FAST_TRACK_MANUAL_TEST_SECURITY_GATE_MQH
#define BRE_APP_FAST_TRACK_MANUAL_TEST_SECURITY_GATE_MQH

#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackManualTestTypes.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>

class CFastTrackManualTestSecurityGate
  {
public:
   static bool       AllowsSeedOrderExecution(const SFastTrackManualTestInputs &inputs,string &blockReasonOut)
     {
      blockReasonOut="";
      if(inputs.observer_only_startup_isolation)
        {
         blockReasonOut="OBSERVER_ONLY_STARTUP_ISOLATION";
         return false;
        }
      if(inputs.global_execution_kill_switch)
        {
         blockReasonOut="GLOBAL_EXECUTION_KILL_SWITCH";
         return false;
        }
      if(!inputs.enable_live_demo_execution)
        {
         blockReasonOut="LIVE_DEMO_EXECUTION_DISABLED";
         return false;
        }
      if(!inputs.allow_demo_seed_execution)
        {
         blockReasonOut="FAST_TRACK_DEMO_SEED_EXECUTION_DISABLED";
         return false;
        }
      if(inputs.execution_mode!=(int)BRE_EXEC_RUNTIME_DEMO_MANUAL_SUBMISSION)
        {
         blockReasonOut="EXECUTION_MODE_NOT_DEMO_MANUAL_SUBMISSION";
         return false;
        }
      if(inputs.seed_order_count!=1)
        {
         blockReasonOut="SEED_ORDER_COUNT_NOT_ONE";
         return false;
        }
      if(inputs.seed_lot<=0.0)
        {
         blockReasonOut="SEED_LOT_INVALID";
         return false;
        }
      return true;
     }

   static bool       RequiresAuditOnly(const SFastTrackManualTestInputs &inputs)
     {
      string blockReason="";
      return !AllowsSeedOrderExecution(inputs,blockReason);
     }
  };

#endif
