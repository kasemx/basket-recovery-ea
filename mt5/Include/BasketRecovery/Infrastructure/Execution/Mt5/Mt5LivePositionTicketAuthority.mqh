#ifndef BRE_INF_MT5_LIVE_POSITION_TICKET_AUTHORITY_MQH
#define BRE_INF_MT5_LIVE_POSITION_TICKET_AUTHORITY_MQH

#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualProfitCloseCandidateEntry.mqh>

class CMt5LivePositionTicketAuthority
  {
public:
   static ENUM_BRE_TRADE_DIRECTION ResolveBreDirection(const long positionType)
     {
      if(positionType==POSITION_TYPE_BUY)
         return BRE_DIRECTION_BUY;
      if(positionType==POSITION_TYPE_SELL)
         return BRE_DIRECTION_SELL;
      return BRE_DIRECTION_NONE;
     }

   static ENUM_BRE_TRADE_DIRECTION CloseDirectionForPositionType(const long positionType)
     {
      return CManualProfitCloseCandidateEntry::CloseDirectionForPosition(ResolveBreDirection(positionType));
     }

   static ENUM_ORDER_TYPE CloseOrderTypeForPositionType(const long positionType)
     {
      if(positionType==POSITION_TYPE_BUY)
         return ORDER_TYPE_SELL;
      if(positionType==POSITION_TYPE_SELL)
         return ORDER_TYPE_BUY;
      return (ENUM_ORDER_TYPE)-1;
     }

   static string     PositionTypeLabel(const long positionType)
     {
      if(positionType==POSITION_TYPE_BUY)
         return "POSITION_TYPE_BUY";
      if(positionType==POSITION_TYPE_SELL)
         return "POSITION_TYPE_SELL";
      return "POSITION_TYPE_UNKNOWN";
     }

   static string     OrderTypeLabel(const ENUM_ORDER_TYPE orderType)
     {
      if(orderType==ORDER_TYPE_BUY)
         return "ORDER_TYPE_BUY";
      if(orderType==ORDER_TYPE_SELL)
         return "ORDER_TYPE_SELL";
      return "ORDER_TYPE_UNKNOWN";
     }

   static bool       TryResolveByTicket(const ulong ticket,
                                        string &outSymbol,
                                        long &outPositionType,
                                        ENUM_BRE_TRADE_DIRECTION &outPositionDirection,
                                        double &outVolume,
                                        string &failureReason)
     {
      failureReason="";
      outSymbol="";
      outPositionType=0;
      outPositionDirection=BRE_DIRECTION_NONE;
      outVolume=0.0;

      if(ticket==0)
        {
         failureReason="Ticket is required";
         return false;
        }

      if(!PositionSelectByTicket(ticket))
        {
         failureReason="Live position not found for ticket";
         return false;
        }

      outSymbol=PositionGetString(POSITION_SYMBOL);
      outPositionType=(long)PositionGetInteger(POSITION_TYPE);
      outVolume=PositionGetDouble(POSITION_VOLUME);
      outPositionDirection=ResolveBreDirection(outPositionType);
      if(outPositionDirection==BRE_DIRECTION_NONE)
        {
         failureReason="Live position type is not BUY or SELL";
         return false;
        }
      return true;
     }

   static bool       TryResolvePlanningFieldsByTicket(const ulong ticket,
                                                      string &outSymbol,
                                                      long &outPositionType,
                                                      ENUM_BRE_TRADE_DIRECTION &outPositionDirection,
                                                      double &outVolume,
                                                      double &outEntryPrice,
                                                      double &outFloatingProfitUsd,
                                                      datetime &outOpenTimeUtc,
                                                      string &failureReason)
     {
      failureReason="";
      outEntryPrice=0.0;
      outFloatingProfitUsd=0.0;
      outOpenTimeUtc=0;

      if(!TryResolveByTicket(ticket,outSymbol,outPositionType,outPositionDirection,outVolume,failureReason))
         return false;

      if(!PositionSelectByTicket(ticket))
        {
         failureReason="Live position not found for ticket";
         return false;
        }

      outEntryPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      outFloatingProfitUsd=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      outOpenTimeUtc=(datetime)PositionGetInteger(POSITION_TIME);
      return true;
     }
  };

#endif
