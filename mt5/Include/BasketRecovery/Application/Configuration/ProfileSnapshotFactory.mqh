#ifndef BASKET_RECOVERY_APPLICATION_PROFILE_SNAPSHOT_FACTORY_MQH
#define BASKET_RECOVERY_APPLICATION_PROFILE_SNAPSHOT_FACTORY_MQH

#include <BasketRecovery/Domain/Configuration/ProfileBundle.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>

class CProfileSnapshotFactory
  {
public:
   static CProfileSnapshot FromBundle(const CProfileBundle &bundle,const IClock &clock)
     {
      return CProfileSnapshot::Create(bundle.ProfileName(),
                                    bundle.Risk(),
                                    bundle.Recovery(),
                                    bundle.TakeProfit(),
                                    bundle.BreakEven(),
                                    bundle.Execution(),
                                    CUtcTime(clock.Now()));
     }
  };

#endif
