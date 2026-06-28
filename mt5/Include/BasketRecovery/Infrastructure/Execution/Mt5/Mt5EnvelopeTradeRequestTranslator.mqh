#ifndef BRE_INF_MT5_ENVELOPE_TRADE_REQUEST_TRANSLATOR_MQH
#define BRE_INF_MT5_ENVELOPE_TRADE_REQUEST_TRANSLATOR_MQH

#include <BasketRecovery/Domain/Execution/BrokerSubmissionEnvelope.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CMt5EnvelopeTradeRequestTranslator
  {
private:
   ENUM_ORDER_TYPE_FILLING ResolveFillingMode(const string symbol) const
     {
      int filling=(int)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
         return ORDER_FILLING_IOC;
      if((filling & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
         return ORDER_FILLING_FOK;
      return ORDER_FILLING_RETURN;
     }

public:
   bool              TryTranslateOpenMarketDeal(const CBrokerSubmissionEnvelope &envelope,
                                                const double bid,
                                                const double ask,
                                                const int slippagePoints,
                                                MqlTradeRequest &request,
                                                string &errorMessage) const
     {
      errorMessage="";
      if(envelope.IntentType()!=BRE_EXEC_INTENT_OPEN_POSITION)
        {
         errorMessage="Only OPEN_POSITION market deals are supported";
         return false;
        }
      if(envelope.Direction()==BRE_DIRECTION_NONE)
        {
         errorMessage="Direction is required for open";
         return false;
        }
      if(envelope.RequestedVolume()<=0.0)
        {
         errorMessage="Requested volume must be positive";
         return false;
        }

      ZeroMemory(request);
      request.action=TRADE_ACTION_DEAL;
      request.symbol=envelope.Symbol();
      request.volume=envelope.RequestedVolume();
      request.deviation=(ulong)slippagePoints;
      request.magic=(ulong)envelope.MagicNumber();
      request.comment=envelope.BrokerComment();
      request.type_filling=ResolveFillingMode(envelope.Symbol());
      request.type_time=ORDER_TIME_GTC;
      request.sl=envelope.RequestedStopLoss();
      request.tp=envelope.RequestedTakeProfit();

      if(envelope.Direction()==BRE_DIRECTION_BUY)
        {
         request.type=ORDER_TYPE_BUY;
         request.price=(envelope.RequestedPrice()>0.0) ? envelope.RequestedPrice() : ask;
        }
      else
        {
         request.type=ORDER_TYPE_SELL;
         request.price=(envelope.RequestedPrice()>0.0) ? envelope.RequestedPrice() : bid;
        }
      return true;
     }
  };

#endif
