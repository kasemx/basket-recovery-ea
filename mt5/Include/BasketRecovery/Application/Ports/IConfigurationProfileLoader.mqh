#ifndef BASKET_RECOVERY_APPLICATION_ICONFIGURATION_PROFILE_LOADER_MQH
#define BASKET_RECOVERY_APPLICATION_ICONFIGURATION_PROFILE_LOADER_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileBundle.mqh>

class IConfigurationProfileLoader
  {
public:
   virtual          ~IConfigurationProfileLoader(void) {}
   virtual CResult<CProfileBundle> LoadProfile(const string profileName)=0;
   virtual CResult<CProfileBundle> ResolveForSymbol(const string symbol)=0;
   virtual CVoidResult             Validate(const CProfileBundle &profileBundle)=0;
  };

#endif
