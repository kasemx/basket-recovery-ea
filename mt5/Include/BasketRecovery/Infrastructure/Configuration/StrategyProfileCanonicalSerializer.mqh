#ifndef BRE_INF_STRATEGY_PROFILE_CANONICAL_SER_MQH
#define BRE_INF_STRATEGY_PROFILE_CANONICAL_SER_MQH

#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfileSnapshot.mqh>
#include <BasketRecovery/Shared/Utils/Crc32.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

class CStrategyProfileCanonicalSerializer
  {
public:
   static string     ComputeHash(const string canonicalJson)
     {
      if(canonicalJson=="")
         return "";
      return CCrc32::ToHex(CCrc32::Compute(canonicalJson));
     }

   static CStrategyProfileSnapshot CreateSnapshot(const CStrategyProfile &profile,
                                                    const string canonicalJson,
                                                    const CUtcTime &boundAtUtc)
     {
      string hash=ComputeHash(canonicalJson);
      return CStrategyProfileSnapshot::Create(profile,canonicalJson,hash,boundAtUtc);
     }
  };

#endif
