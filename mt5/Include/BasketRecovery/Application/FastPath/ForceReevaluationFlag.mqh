#ifndef BRE_APP_FORCE_REEVALUATION_FLAG_MQH
#define BRE_APP_FORCE_REEVALUATION_FLAG_MQH

#include <BasketRecovery/Application/FastPath/BasketFastState.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>

class CForceReevaluationFlag
  {
public:
   static void       Set(CBasketFastState &state,const bool value)
     {
      state.SetForceReevaluate(value);
     }

   static bool       IsSet(const CBasketFastState &state)
     {
      return state.ForceReevaluate();
     }

   static void       ClearAfterAttempt(CBasketFastState &state)
     {
      state.SetForceReevaluate(false);
     }
  };

#endif
