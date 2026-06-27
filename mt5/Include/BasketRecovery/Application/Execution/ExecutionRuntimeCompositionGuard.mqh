#ifndef BRE_APP_EXECUTION_RUNTIME_COMPOSITION_GUARD_MQH
#define BRE_APP_EXECUTION_RUNTIME_COMPOSITION_GUARD_MQH

class CExecutionRuntimeCompositionGuard
  {
public:
   static bool       AllowsLegacyTradeRequestExecutorInCompositionRoot(void)
     {
      return false;
     }

   static bool       RequiresUnifiedTradeExecutorPort(void)
     {
      return true;
     }
  };

#endif
