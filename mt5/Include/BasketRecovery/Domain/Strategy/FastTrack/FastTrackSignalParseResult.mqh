#ifndef BRE_DOMAIN_FAST_TRACK_SIGNAL_PARSE_RESULT_MQH
#define BRE_DOMAIN_FAST_TRACK_SIGNAL_PARSE_RESULT_MQH

#include <BasketRecovery/Domain/Strategy/FastTrack/FastTrackSignalTypes.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

struct SFastTrackSignalParseResult
  {
   bool                                  valid;
   ENUM_BRE_FAST_TRACK_SIGNAL_KIND       signal_kind;
   ENUM_BRE_FAST_TRACK_PARSE_FAILURE_REASON failure_reason;
   string                                failure_detail;
   string                                symbol;
   ENUM_BRE_TRADE_DIRECTION              direction;
   double                                entry_range_low;
   double                                entry_range_high;
   double                                hard_stop_loss;
   double                                take_profit_levels[];
   int                                   take_profit_count;
   bool                                  runner_enabled;

   void                                  Reset(void)
     {
      valid=false;
      signal_kind=BRE_FAST_TRACK_SIGNAL_NONE;
      failure_reason=BRE_FAST_TRACK_PARSE_OK;
      failure_detail="";
      symbol="";
      direction=BRE_DIRECTION_NONE;
      entry_range_low=0.0;
      entry_range_high=0.0;
      hard_stop_loss=0.0;
      ArrayResize(take_profit_levels,0);
      take_profit_count=0;
      runner_enabled=false;
     }

   void                                  Fail(const ENUM_BRE_FAST_TRACK_PARSE_FAILURE_REASON reason,
                                                const string detail="")
     {
      valid=false;
      failure_reason=reason;
      failure_detail=detail;
     }

   void                                  SucceedSeed(const string symbolValue,
                                                     const ENUM_BRE_TRADE_DIRECTION directionValue)
     {
      valid=true;
      signal_kind=BRE_FAST_TRACK_SIGNAL_SEED;
      failure_reason=BRE_FAST_TRACK_PARSE_OK;
      failure_detail="";
      symbol=symbolValue;
      direction=directionValue;
     }

   void                                  SucceedDetails(const string symbolValue,
                                                        const ENUM_BRE_TRADE_DIRECTION directionValue,
                                                        const double rangeLow,
                                                        const double rangeHigh,
                                                        const double stopLoss,
                                                        const double &takeProfits[],
                                                        const int takeProfitCount,
                                                        const bool runnerEnabled)
     {
      valid=true;
      signal_kind=BRE_FAST_TRACK_SIGNAL_DETAILS;
      failure_reason=BRE_FAST_TRACK_PARSE_OK;
      failure_detail="";
      symbol=symbolValue;
      direction=directionValue;
      entry_range_low=rangeLow;
      entry_range_high=rangeHigh;
      hard_stop_loss=stopLoss;
      take_profit_count=takeProfitCount;
      ArrayResize(take_profit_levels,takeProfitCount);
      for(int i=0;i<takeProfitCount;i++)
         take_profit_levels[i]=takeProfits[i];
      runner_enabled=runnerEnabled;
     }
  };

#endif
