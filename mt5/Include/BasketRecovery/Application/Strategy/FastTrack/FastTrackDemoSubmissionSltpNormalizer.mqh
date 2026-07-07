#ifndef BRE_APP_FAST_TRACK_DEMO_SUBMISSION_SLTP_NORMALIZER_MQH
#define BRE_APP_FAST_TRACK_DEMO_SUBMISSION_SLTP_NORMALIZER_MQH

#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackDemoSubmissionTypes.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

struct SFastTrackDemoSubmissionSltpOutcome
  {
   bool              valid;
   double            normalized_stop_loss;
   double            broker_take_profit;
   int               additional_tp_count;
   string            failure_detail;

   void              Reset(void)
     {
      valid=false;
      normalized_stop_loss=0.0;
      broker_take_profit=0.0;
      additional_tp_count=0;
      failure_detail="";
     }
  };

class CFastTrackDemoSubmissionSltpNormalizer
  {
private:
   static double     NormalizePrice(const double price,const double tickSize)
     {
      if(tickSize<=0.0)
         return price;
      return MathRound(price/tickSize)*tickSize;
     }

   static bool       IsValidTakeProfitLevel(const double level)
     {
      return level>0.0 && level!=EMPTY_VALUE;
     }

public:
   static SFastTrackDemoSubmissionSltpOutcome TryNormalize(const ENUM_BRE_TRADE_DIRECTION direction,
                                                           const double rawStopLoss,
                                                           const double &takeProfits[],
                                                           const int takeProfitCount,
                                                           const SFastTrackDemoSubmissionEnvironment &environment)
     {
      SFastTrackDemoSubmissionSltpOutcome outcome;
      outcome.Reset();

      if(rawStopLoss<=0.0)
        {
         outcome.failure_detail="STOP_LOSS_REQUIRED";
         return outcome;
        }
      if(takeProfitCount<=0)
        {
         outcome.failure_detail="TAKE_PROFIT_REQUIRED";
         return outcome;
        }

      const double bid=environment.symbol_bid;
      const double ask=environment.symbol_ask;
      if(bid<=0.0 || ask<=0.0)
        {
         outcome.failure_detail="MARKET_PRICE_UNAVAILABLE";
         return outcome;
        }

      const double point=environment.symbol_point>0.0 ? environment.symbol_point : environment.symbol_tick_size;
      const double minDistance=environment.symbol_stops_level*point;
      const double entryPrice=(direction==BRE_DIRECTION_BUY) ? ask : bid;

      double normalizedSl=NormalizePrice(rawStopLoss,environment.symbol_tick_size);
      if(direction==BRE_DIRECTION_BUY)
        {
         if(normalizedSl<=0.0 || normalizedSl>=entryPrice-minDistance)
           {
            outcome.failure_detail="STOP_LOSS_STOPS_LEVEL_VIOLATION";
            return outcome;
           }
        }
      else if(direction==BRE_DIRECTION_SELL)
        {
         if(normalizedSl<=0.0 || normalizedSl<=entryPrice+minDistance)
           {
            outcome.failure_detail="STOP_LOSS_STOPS_LEVEL_VIOLATION";
            return outcome;
           }
        }
      else
        {
         outcome.failure_detail="DIRECTION_INVALID";
         return outcome;
        }

      double brokerTp=0.0;
      int additionalCount=0;
      for(int i=0;i<takeProfitCount;i++)
        {
         if(!IsValidTakeProfitLevel(takeProfits[i]))
            continue;
         const double normalizedTp=NormalizePrice(takeProfits[i],environment.symbol_tick_size);
         if(direction==BRE_DIRECTION_BUY)
           {
            if(normalizedTp<=entryPrice+minDistance)
               continue;
           }
         else
           {
            if(normalizedTp>=entryPrice-minDistance)
               continue;
           }
         if(brokerTp<=0.0)
           {
            brokerTp=normalizedTp;
            continue;
           }
         additionalCount++;
        }

      if(brokerTp<=0.0)
        {
         outcome.failure_detail="BROKER_TAKE_PROFIT_STOPS_LEVEL_VIOLATION";
         return outcome;
        }

      outcome.valid=true;
      outcome.normalized_stop_loss=normalizedSl;
      outcome.broker_take_profit=brokerTp;
      outcome.additional_tp_count=additionalCount;
      return outcome;
     }
  };

#endif
