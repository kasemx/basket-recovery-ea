#ifndef BRE_APP_MARKET_CONTEXT_REFRESH_SERVICE_MQH
#define BRE_APP_MARKET_CONTEXT_REFRESH_SERVICE_MQH

#include <BasketRecovery/Application/Ports/IMarketDataProvider.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>

class CMarketContextRefreshService
  {
private:
   IMarketDataProvider *m_marketData;
   IBasketRepository   *m_repository;
   int                  m_intervalMs;
   int                  m_maxSymbolsPerCycle;
   ulong                m_lastRunTickMs;
   int                  m_nextBasketIndex;

   bool              IsDue(void) const
     {
      if(m_intervalMs<=0)
         return true;
      return ((ulong)GetTickCount()-m_lastRunTickMs)>=(ulong)m_intervalMs;
     }

   bool              SymbolExists(const string symbol,const string &symbols[],const int count) const
     {
      for(int i=0;i<count;i++)
        {
         if(symbols[i]==symbol)
            return true;
        }
      return false;
     }

public:
                     CMarketContextRefreshService(IMarketDataProvider *marketData,
                                                  IBasketRepository *repository,
                                                  const int intervalMs=1000,
                                                  const int maxSymbolsPerCycle=8)
     {
      m_marketData=marketData;
      m_repository=repository;
      m_intervalMs=intervalMs;
      m_maxSymbolsPerCycle=maxSymbolsPerCycle;
      m_lastRunTickMs=0;
      m_nextBasketIndex=0;
     }

   int               RunIfDue(void)
     {
      if(!IsDue() || m_marketData==NULL || m_repository==NULL)
         return 0;

      CBasketAggregate baskets[];
      int basketCount=m_repository.LoadAll(baskets);
      if(basketCount<=0)
        {
         m_lastRunTickMs=(ulong)GetTickCount();
         return 0;
        }

      string symbols[];
      int symbolCount=0;
      int scanned=0;
      while(symbolCount<m_maxSymbolsPerCycle && scanned<basketCount)
        {
         if(m_nextBasketIndex>=basketCount)
            m_nextBasketIndex=0;

         CBasketAggregate basket=baskets[m_nextBasketIndex];
         m_nextBasketIndex++;
         scanned++;

         if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
            continue;

         string symbol=basket.Symbol();
         if(symbol=="" || SymbolExists(symbol,symbols,symbolCount))
            continue;

         ArrayResize(symbols,symbolCount+1);
         symbols[symbolCount]=symbol;
         symbolCount++;
        }

      if(symbolCount>0)
         m_marketData.RefreshCachedQuotes(symbols,symbolCount);

      m_lastRunTickMs=(ulong)GetTickCount();
      return symbolCount;
     }
  };

#endif
