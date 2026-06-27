#ifndef BRE_INF_MT5_MARKET_DATA_PROVIDER_MQH
#define BRE_INF_MT5_MARKET_DATA_PROVIDER_MQH

#include <BasketRecovery/Application/Ports/IMarketDataProvider.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CMt5MarketDataProvider : public IMarketDataProvider
  {
private:
   IClock *m_clock;

   ENUM_BRE_TRADING_SESSION_STATUS ResolveSessionStatus(const string symbol) const
     {
      if(!SymbolSelect(symbol,true))
         return BRE_TRADING_SESSION_CLOSED;

      long tradeMode=SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
      if(tradeMode==SYMBOL_TRADE_MODE_DISABLED)
         return BRE_TRADING_SESSION_CLOSED;

      return BRE_TRADING_SESSION_OPEN;
     }

   CSymbolTradingConstraints ReadConstraints(const string symbol) const
     {
      return CSymbolTradingConstraints::Create((int)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                               (int)SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL),
                                               SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN),
                                               SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX),
                                               SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP));
     }

   int               ComputeSpreadPoints(const string symbol,const double bid,const double ask) const
     {
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      if(point<=0.0)
         return 0;
      return (int)MathRound((ask-bid)/point);
     }

   int               ComputeFreshnessAgeMs(const datetime tickTimeUtc) const
     {
      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : TimeCurrent();
      if(tickTimeUtc<=0 || nowUtc<=tickTimeUtc)
         return 0;
      return (int)((nowUtc-tickTimeUtc)*1000);
     }

public:
                     CMt5MarketDataProvider(IClock *clock)
     {
      m_clock=clock;
     }

   virtual CResult<CMarketQuote> TryGetQuote(const string symbol) const
     {
      if(symbol=="")
         return CResult<CMarketQuote>::Fail(BRE_ERR_SYMBOL_UNAVAILABLE,"Symbol is empty");

      if(!SymbolSelect(symbol,true))
         return CResult<CMarketQuote>::Fail(BRE_ERR_SYMBOL_UNAVAILABLE,"Symbol unavailable");

      MqlTick tick;
      if(!SymbolInfoTick(symbol,tick))
         return CResult<CMarketQuote>::Fail(BRE_ERR_SYMBOL_UNAVAILABLE,"Symbol tick unavailable");

      if(tick.bid<=0.0 || tick.ask<=0.0)
         return CResult<CMarketQuote>::Fail(BRE_ERR_SYMBOL_UNAVAILABLE,"Quote prices unavailable");

      datetime timestampUtc=(datetime)tick.time;
      CMarketQuote quote=CMarketQuote::Create(symbol,
                                              tick.bid,
                                              tick.ask,
                                              ComputeSpreadPoints(symbol,tick.bid,tick.ask),
                                              SymbolInfoDouble(symbol,SYMBOL_POINT),
                                              (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS),
                                              SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE),
                                              SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE),
                                              timestampUtc,
                                              ComputeFreshnessAgeMs(timestampUtc),
                                              ResolveSessionStatus(symbol),
                                              ReadConstraints(symbol));
      return CResult<CMarketQuote>::Ok(quote);
     }

   virtual CResult<CMarketContextSnapshot> TryGetMarketSnapshot(const string symbol) const
     {
      CResult<CMarketQuote> quoteResult=TryGetQuote(symbol);
      if(quoteResult.IsFail())
         return CResult<CMarketContextSnapshot>::Fail(quoteResult.ErrorCode(),quoteResult.ErrorMessage());

      CMarketQuote quote;
      quoteResult.TryGetValue(quote);
      return CResult<CMarketContextSnapshot>::Ok(CMarketContextSnapshot::Create(quote));
     }

   virtual CResult<CAccountContextSnapshot> TryGetAccountSnapshot(void) const
     {
      long login=AccountInfoInteger(ACCOUNT_LOGIN);
      bool tradeAllowed=(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)>0 &&
                         AccountInfoInteger(ACCOUNT_TRADE_EXPERT)>0);
      CAccountContextSnapshot snapshot=CAccountContextSnapshot::Create(login,
                                                                       AccountInfoDouble(ACCOUNT_BALANCE),
                                                                       AccountInfoDouble(ACCOUNT_EQUITY),
                                                                       AccountInfoDouble(ACCOUNT_MARGIN),
                                                                       AccountInfoDouble(ACCOUNT_MARGIN_FREE),
                                                                       tradeAllowed);
      return CResult<CAccountContextSnapshot>::Ok(snapshot);
     }

   virtual void      RefreshCachedQuotes(const string &symbols[],const int symbolCount)
     {
      for(int i=0;i<symbolCount;i++)
        {
         if(symbols[i]!="")
            SymbolSelect(symbols[i],true);
        }
     }
  };

#endif
