#ifndef BRE_DOMAIN_FAST_TRACK_SEED_BASKET_MATCHER_MQH
#define BRE_DOMAIN_FAST_TRACK_SEED_BASKET_MATCHER_MQH

#include <BasketRecovery/Domain/Strategy/FastTrack/FastTrackSignalParseResult.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

struct SFastTrackSeedBasketRecord
  {
   string                    basket_id;
   string                    symbol;
   ENUM_BRE_TRADE_DIRECTION  direction;
   datetime                  seed_received_at;

   static SFastTrackSeedBasketRecord Create(const string basketId,
                                            const string symbolValue,
                                            const ENUM_BRE_TRADE_DIRECTION directionValue,
                                            const datetime receivedAt)
     {
      SFastTrackSeedBasketRecord record;
      record.basket_id=basketId;
      record.symbol=symbolValue;
      record.direction=directionValue;
      record.seed_received_at=receivedAt;
      return record;
     }
  };

struct SFastTrackDetailsMatchOutcome
  {
   ENUM_BRE_FAST_TRACK_DETAILS_MATCH_RESULT result;
   string                                   matched_basket_id;
   string                                   detail;

   static SFastTrackDetailsMatchOutcome Create(const ENUM_BRE_FAST_TRACK_DETAILS_MATCH_RESULT resultValue,
                                               const string matchedBasketId="",
                                               const string detailValue="")
     {
      SFastTrackDetailsMatchOutcome outcome;
      outcome.result=resultValue;
      outcome.matched_basket_id=matchedBasketId;
      outcome.detail=detailValue;
      return outcome;
     }
  };

class CFastTrackSeedBasketMatcher
  {
private:
   static bool       IsExpired(const SFastTrackSeedBasketRecord &record,
                               const datetime nowUtc,
                               const int seedTimeoutSeconds)
     {
      if(seedTimeoutSeconds<=0)
         return false;
      return (nowUtc-record.seed_received_at)>seedTimeoutSeconds;
     }

   static bool       MatchesCandidate(const SFastTrackSeedBasketRecord &record,
                                      const SFastTrackSignalParseResult &details,
                                      const datetime nowUtc,
                                      const int seedTimeoutSeconds)
     {
      if(record.symbol!=details.symbol)
         return false;
      if(record.direction!=details.direction)
         return false;
      if(IsExpired(record,nowUtc,seedTimeoutSeconds))
         return false;
      return true;
     }

public:
   static SFastTrackDetailsMatchOutcome MatchDetails(const SFastTrackSignalParseResult &details,
                                                     const SFastTrackSeedBasketRecord &records[],
                                                     const int recordCount,
                                                     const datetime nowUtc,
                                                     const int seedTimeoutSeconds)
     {
      if(!details.valid || details.signal_kind!=BRE_FAST_TRACK_SIGNAL_DETAILS)
         return SFastTrackDetailsMatchOutcome::Create(BRE_FAST_TRACK_MATCH_NONE,"","Details parse result is invalid");

      int eligibleCount=0;
      string eligibleBasketId="";
      bool hasExpiredCandidate=false;

      for(int i=0;i<recordCount;i++)
        {
         if(records[i].symbol!=details.symbol)
            continue;
         if(records[i].direction!=details.direction)
            continue;
         if(IsExpired(records[i],nowUtc,seedTimeoutSeconds))
           {
            hasExpiredCandidate=true;
            continue;
           }
         eligibleCount++;
         eligibleBasketId=records[i].basket_id;
        }

      if(eligibleCount==0)
        {
         if(hasExpiredCandidate)
            return SFastTrackDetailsMatchOutcome::Create(BRE_FAST_TRACK_MATCH_EXPIRED_SEED,"","Seed timeout elapsed");
         return SFastTrackDetailsMatchOutcome::Create(BRE_FAST_TRACK_MATCH_NO_CANDIDATE,"","No waiting seed basket");
        }

      if(eligibleCount>1)
         return SFastTrackDetailsMatchOutcome::Create(BRE_FAST_TRACK_MATCH_AMBIGUOUS_DETAILS_MATCH,"",
                                                      "Multiple seed baskets share symbol and direction");

      return SFastTrackDetailsMatchOutcome::Create(BRE_FAST_TRACK_MATCH_OK,eligibleBasketId);
     }
  };

#endif
