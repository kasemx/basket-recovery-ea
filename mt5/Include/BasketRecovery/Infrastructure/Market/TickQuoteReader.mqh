#ifndef BRE_INF_TICK_QUOTE_READER_MQH
#define BRE_INF_TICK_QUOTE_READER_MQH

#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class CTickQuoteReader
  {
private:
   static double     ResolveTickValue(const string symbol)
     {
      double tickValue=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
      if(tickValue>0.0)
         return tickValue;

      tickValue=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_PROFIT);
      if(tickValue>0.0)
         return tickValue;

      double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tickSize<=0.0)
         tickSize=SymbolInfoDouble(symbol,SYMBOL_POINT);
      double contractSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE);
      if(tickSize>0.0 && contractSize>0.0)
        {
         tickValue=tickSize*contractSize;
         if(tickValue>0.0)
            return tickValue;
        }

      if(tickSize<=0.0)
         return 0.0;

      double bid=SymbolInfoDouble(symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
      if(bid<=0.0 || ask<=0.0)
         return 0.0;

      double volumeMin=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      if(volumeMin<=0.0)
         volumeMin=1.0;

      double profitBuy=0.0;
      if(OrderCalcProfit(ORDER_TYPE_BUY,symbol,volumeMin,bid,bid+tickSize,profitBuy))
        {
         double absProfit=MathAbs(profitBuy);
         if(absProfit>0.0)
            return absProfit/volumeMin;
        }

      double profitSell=0.0;
      if(OrderCalcProfit(ORDER_TYPE_SELL,symbol,volumeMin,ask,ask-tickSize,profitSell))
        {
         double absProfit=MathAbs(profitSell);
         if(absProfit>0.0)
            return absProfit/volumeMin;
        }

      return 0.0;
     }

public:
   static CResult<CMarketQuote> ReadOnce(const string symbol)
     {
      if(symbol=="")
         return CResult<CMarketQuote>::Fail(BRE_ERR_SYMBOL_UNAVAILABLE,"Symbol is empty");

      if(!SymbolSelect(symbol,true))
         return CResult<CMarketQuote>::Fail(BRE_ERR_SYMBOL_UNAVAILABLE,"Symbol unavailable");

      MqlTick tick;
      if(!SymbolInfoTick(symbol,tick))
         return CResult<CMarketQuote>::Fail(BRE_ERR_SYMBOL_UNAVAILABLE,"Tick unavailable");

      if(tick.bid<=0.0 || tick.ask<=0.0)
         return CResult<CMarketQuote>::Fail(BRE_ERR_SYMBOL_UNAVAILABLE,"Tick prices unavailable");

      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      int spreadPoints=0;
      if(point>0.0)
         spreadPoints=(int)MathRound((tick.ask-tick.bid)/point);

      CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(
         (int)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL),
         (int)SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL),
         SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN),
         SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX),
         SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP));

      long tradeMode=SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
      ENUM_BRE_TRADING_SESSION_STATUS sessionStatus=BRE_TRADING_SESSION_OPEN;
      if(tradeMode==SYMBOL_TRADE_MODE_DISABLED)
         sessionStatus=BRE_TRADING_SESSION_CLOSED;

      CMarketQuote quote=CMarketQuote::Create(symbol,
                                              tick.bid,
                                              tick.ask,
                                              spreadPoints,
                                              point,
                                              (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS),
                                              SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE),
                                              ResolveTickValue(symbol),
                                              (datetime)tick.time,
                                              0,
                                              sessionStatus,
                                              constraints);
      return CResult<CMarketQuote>::Ok(quote);
     }

   static ulong      QuoteSequence(const MqlTick &tick)
     {
      return ((ulong)tick.time_msc<<16)^((ulong)tick.volume & 0xFFFF);
     }
  };

#endif
