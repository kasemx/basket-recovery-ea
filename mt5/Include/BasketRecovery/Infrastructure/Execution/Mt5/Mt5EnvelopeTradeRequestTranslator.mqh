#ifndef BRE_INF_MT5_ENVELOPE_TRADE_REQUEST_TRANSLATOR_MQH
#define BRE_INF_MT5_ENVELOPE_TRADE_REQUEST_TRANSLATOR_MQH

#include <BasketRecovery/Domain/Execution/BrokerSubmissionEnvelope.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/BrokerMarketDealFillingModeResolver.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5LivePositionTicketAuthority.mqh>

class CMt5EnvelopeTradeRequestTranslator
  {
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

      if(!CBrokerMarketDealFillingModeResolver::TryApplyToMarketDealRequest(envelope.Symbol(),request,errorMessage))
        {
         errorMessage="Filling mode resolution failed: "+errorMessage;
         return false;
        }
      return true;
     }

   bool              TryTranslateCloseMarketDeal(const CBrokerSubmissionEnvelope &envelope,
                                                 const double bid,
                                                 const double ask,
                                                 const int slippagePoints,
                                                 MqlTradeRequest &request,
                                                 string &errorMessage) const
     {
      errorMessage="";
      if(envelope.IntentType()!=BRE_EXEC_INTENT_CLOSE_POSITION)
        {
         errorMessage="Only CLOSE_POSITION market deals are supported";
         return false;
        }
      if(envelope.Ticket()==0)
        {
         errorMessage="Ticket is required for ticket-bound close";
         return false;
        }
      if(envelope.Direction()==BRE_DIRECTION_NONE)
        {
         errorMessage="Close direction is required";
         return false;
        }
      if(envelope.RequestedVolume()<=0.0)
        {
         errorMessage="Requested close volume must be positive";
         return false;
        }

      ENUM_ORDER_TYPE closeOrderType=(ENUM_ORDER_TYPE)-1;
      if(PositionSelectByTicket(envelope.Ticket()))
        {
         long livePositionType=(long)PositionGetInteger(POSITION_TYPE);
         closeOrderType=CMt5LivePositionTicketAuthority::CloseOrderTypeForPositionType(livePositionType);
        }

      if(closeOrderType!=(ENUM_ORDER_TYPE)-1)
        {
         ENUM_BRE_TRADE_DIRECTION liveCloseDirection=BRE_DIRECTION_NONE;
         if(closeOrderType==ORDER_TYPE_SELL)
            liveCloseDirection=BRE_DIRECTION_SELL;
         else if(closeOrderType==ORDER_TYPE_BUY)
            liveCloseDirection=BRE_DIRECTION_BUY;

         if(envelope.Direction()!=BRE_DIRECTION_NONE &&
            liveCloseDirection!=BRE_DIRECTION_NONE &&
            envelope.Direction()!=liveCloseDirection)
           {
            errorMessage="Envelope close direction does not oppose live position type";
            return false;
           }
        }
      else if(envelope.Direction()==BRE_DIRECTION_SELL)
         closeOrderType=ORDER_TYPE_SELL;
      else if(envelope.Direction()==BRE_DIRECTION_BUY)
         closeOrderType=ORDER_TYPE_BUY;
      else
        {
         errorMessage="Close direction is required";
         return false;
        }

      ZeroMemory(request);
      request.action=TRADE_ACTION_DEAL;
      request.position=envelope.Ticket();
      request.symbol=envelope.Symbol();
      request.volume=envelope.RequestedVolume();
      request.deviation=(ulong)slippagePoints;
      request.magic=(ulong)envelope.MagicNumber();
      request.comment=envelope.BrokerComment();
      request.type_time=ORDER_TIME_GTC;
      request.type=closeOrderType;

      if(closeOrderType==ORDER_TYPE_SELL)
         request.price=(envelope.RequestedPrice()>0.0) ? envelope.RequestedPrice() : bid;
      else
         request.price=(envelope.RequestedPrice()>0.0) ? envelope.RequestedPrice() : ask;

      if(!CBrokerMarketDealFillingModeResolver::TryApplyToMarketDealRequest(envelope.Symbol(),request,errorMessage))
        {
         errorMessage="Filling mode resolution failed: "+errorMessage;
         return false;
        }
      return true;
     }
  };

#endif
