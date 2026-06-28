#ifndef BRE_DOMAIN_RECOVERY_STEP_STATE_BUILDER_MQH
#define BRE_DOMAIN_RECOVERY_STEP_STATE_BUILDER_MQH

#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryStepState.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryTriggerEvaluator.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Enums/TradeRole.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>

class CRecoveryStepStateBuilder
  {
public:
   static CRecoveryStepState BuildFromEntries(const ENUM_BRE_TRADE_DIRECTION direction,
                                              const double signalRangeLow,
                                              const double signalRangeHigh,
                                              const CPositionSnapshotEntry &entries[],
                                              const int entryCount)
     {
      int lastAcceptedStepIndex=0;
      double lastTriggerReferencePrice=0.0;
      double priorRecoveryVolume=0.0;

      for(int i=0;i<entryCount;i++)
        {
         if(entries[i].Status()!=BRE_POSITION_SNAPSHOT_OPEN)
            continue;
         if(entries[i].Role()!=BRE_TRADE_ROLE_RECOVERY)
            continue;
         int stepIndex=entries[i].RecoveryStepIndex();
         if(stepIndex>lastAcceptedStepIndex)
           {
            lastAcceptedStepIndex=stepIndex;
            lastTriggerReferencePrice=entries[i].EntryPrice();
            priorRecoveryVolume=entries[i].Volume();
           }
        }

      if(lastAcceptedStepIndex<=0)
         lastTriggerReferencePrice=CRecoveryTriggerEvaluator::InitialBasketReferencePrice(direction,signalRangeLow,signalRangeHigh);

      return CRecoveryStepState::Create(lastAcceptedStepIndex,lastTriggerReferencePrice,priorRecoveryVolume);
     }
  };

#endif
