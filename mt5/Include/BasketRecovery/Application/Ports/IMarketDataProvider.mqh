#ifndef BRE_APP_IMARKET_DATA_PROVIDER_MQH
#define BRE_APP_IMARKET_DATA_PROVIDER_MQH

#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Market/MarketContextSnapshot.mqh>
#include <BasketRecovery/Domain/Market/AccountContextSnapshot.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class IMarketDataProvider
  {
public:
   virtual          ~IMarketDataProvider(void) {}
   virtual CResult<CMarketQuote> TryGetQuote(const string symbol) const=0;
   virtual CResult<CMarketContextSnapshot> TryGetMarketSnapshot(const string symbol) const=0;
   virtual CResult<CAccountContextSnapshot> TryGetAccountSnapshot(void) const=0;
   virtual void      RefreshCachedQuotes(const string &symbols[],const int symbolCount)=0;
  };

#endif
