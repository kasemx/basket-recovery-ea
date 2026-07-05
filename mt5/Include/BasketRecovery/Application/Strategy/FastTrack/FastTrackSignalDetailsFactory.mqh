#ifndef BRE_APP_FAST_TRACK_SIGNAL_DETAILS_FACTORY_MQH
#define BRE_APP_FAST_TRACK_SIGNAL_DETAILS_FACTORY_MQH

#include <BasketRecovery/Domain/Strategy/FastTrack/FastTrackSignalParseResult.mqh>
#include <BasketRecovery/Domain/ValueObjects/SignalDetails.mqh>
#include <BasketRecovery/Shared/Types/Price.mqh>

class CFastTrackSignalDetailsFactory
  {
public:
   static CSignalDetails FromParseResult(const SFastTrackSignalParseResult &parsed)
     {
      CSignalDetails details;
      if(!parsed.valid || parsed.signal_kind!=BRE_FAST_TRACK_SIGNAL_DETAILS)
         return details;

      details.SetHasDetails(true);
      details.SetRangeLow(CPrice(parsed.entry_range_low));
      details.SetRangeHigh(CPrice(parsed.entry_range_high));
      details.SetStopLoss(CPrice(parsed.hard_stop_loss));
      if(parsed.take_profit_count>0)
         details.SetTp1(CPrice(parsed.take_profit_levels[0]));
      if(parsed.take_profit_count>1)
         details.SetTp2(CPrice(parsed.take_profit_levels[1]));
      if(parsed.take_profit_count>2)
         details.SetTp3(CPrice(parsed.take_profit_levels[2]));
      if(parsed.take_profit_count>3)
         details.SetTp4(CPrice(parsed.take_profit_levels[3]));
      details.SetTpOpen(parsed.runner_enabled);
      return details;
     }
  };

#endif
