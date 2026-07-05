#ifndef BRE_DOMAIN_FAST_TRACK_SIGNAL_DETAILS_VALIDATOR_MQH
#define BRE_DOMAIN_FAST_TRACK_SIGNAL_DETAILS_VALIDATOR_MQH

#include <BasketRecovery/Domain/Strategy/FastTrack/FastTrackSignalTypes.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CFastTrackSignalDetailsValidator
  {
public:
   static bool       ValidateGeometry(const ENUM_BRE_TRADE_DIRECTION direction,
                                      const double rangeLow,
                                      const double rangeHigh,
                                      const double stopLoss,
                                      const double &takeProfits[],
                                      const int takeProfitCount,
                                      ENUM_BRE_FAST_TRACK_PARSE_FAILURE_REASON &reasonOut,
                                      string &failureDetail)
     {
      reasonOut=BRE_FAST_TRACK_PARSE_OK;
      failureDetail="";

      if(stopLoss<=0.0)
        {
         reasonOut=BRE_FAST_TRACK_PARSE_MISSING_STOP_LOSS;
         failureDetail="Stop loss is required";
         return false;
        }

      if(takeProfitCount<=0)
        {
         reasonOut=BRE_FAST_TRACK_PARSE_MISSING_TAKE_PROFIT;
         failureDetail="At least one take-profit level is required";
         return false;
        }

      if(direction==BRE_DIRECTION_SELL)
        {
         if(stopLoss<=rangeHigh)
           {
            reasonOut=BRE_FAST_TRACK_PARSE_STOP_LOSS_OUT_OF_RANGE;
            failureDetail="SELL stop loss must be above entry range high";
            return false;
           }
         for(int i=0;i<takeProfitCount;i++)
           {
            if(takeProfits[i]>=rangeLow)
              {
               reasonOut=BRE_FAST_TRACK_PARSE_TAKE_PROFIT_OUT_OF_RANGE;
               failureDetail="SELL take-profit levels must be below entry range low";
               return false;
              }
            if(i>0 && takeProfits[i]>=takeProfits[i-1])
              {
               reasonOut=BRE_FAST_TRACK_PARSE_TAKE_PROFIT_NOT_ORDERED;
               failureDetail="SELL take-profit levels must be strictly descending";
               return false;
              }
           }
         return true;
        }

      if(direction==BRE_DIRECTION_BUY)
        {
         if(stopLoss>=rangeLow)
           {
            reasonOut=BRE_FAST_TRACK_PARSE_STOP_LOSS_OUT_OF_RANGE;
            failureDetail="BUY stop loss must be below entry range low";
            return false;
           }
         for(int i=0;i<takeProfitCount;i++)
           {
            if(takeProfits[i]<=rangeHigh)
              {
               reasonOut=BRE_FAST_TRACK_PARSE_TAKE_PROFIT_OUT_OF_RANGE;
               failureDetail="BUY take-profit levels must be above entry range high";
               return false;
              }
            if(i>0 && takeProfits[i]<=takeProfits[i-1])
              {
               reasonOut=BRE_FAST_TRACK_PARSE_TAKE_PROFIT_NOT_ORDERED;
               failureDetail="BUY take-profit levels must be strictly ascending";
               return false;
              }
           }
         return true;
        }

      reasonOut=BRE_FAST_TRACK_PARSE_UNKNOWN_DIRECTION;
      failureDetail="Direction is required";
      return false;
     }
  };

#endif
