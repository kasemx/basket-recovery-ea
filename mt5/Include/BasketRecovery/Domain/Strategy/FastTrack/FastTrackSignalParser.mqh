#ifndef BRE_DOMAIN_FAST_TRACK_SIGNAL_PARSER_MQH
#define BRE_DOMAIN_FAST_TRACK_SIGNAL_PARSER_MQH

#include <BasketRecovery/Domain/Strategy/FastTrack/FastTrackSignalParseResult.mqh>
#include <BasketRecovery/Domain/Strategy/FastTrack/FastTrackSignalTextUtils.mqh>
#include <BasketRecovery/Domain/Strategy/FastTrack/FastTrackSignalDetailsValidator.mqh>

class CFastTrackSignalParser
  {
private:
   static bool       TryParseSeedHeader(const string header,
                                        string &symbolOut,
                                        ENUM_BRE_TRADE_DIRECTION &directionOut,
                                        string &failureDetail)
     {
      string text=CFastTrackSignalTextUtils::Trim(header);
      StringToLower(text);
      if(StringFind(text," now")<0)
        {
         failureDetail="Seed message must end with 'now'";
         return false;
        }

      string parts[];
      int count=StringSplit(text,' ',parts);
      if(count<3)
        {
         failureDetail="Seed message format must be '<symbol> <buy|sell> now'";
         return false;
        }

      if(!CFastTrackSignalTextUtils::TryResolveSymbolAlias(parts[0],symbolOut))
        {
         failureDetail="Unsupported symbol alias";
         return false;
        }

      if(!CFastTrackSignalTextUtils::TryResolveDirectionToken(parts[1],directionOut))
        {
         failureDetail="Direction must be buy or sell";
         return false;
        }

      if(parts[count-1]!="now")
        {
         failureDetail="Seed message must end with 'now'";
         return false;
        }

      return true;
     }

   static bool       TryParseDetailsHeader(const string header,
                                             string &symbolOut,
                                             ENUM_BRE_TRADE_DIRECTION &directionOut,
                                             double &rangeLowOut,
                                             double &rangeHighOut,
                                             string &failureDetail)
     {
      string text=CFastTrackSignalTextUtils::Trim(header);
      string lowerText=text;
      StringToLower(lowerText);

      int nowPos=CFastTrackSignalTextUtils::FindNowMarkerPosition(lowerText);
      if(nowPos<0)
        {
         failureDetail="Details header must contain 'now' before entry range";
         return false;
        }

      string prefix=StringSubstr(text,0,nowPos);
      int nowTokenLength=(StringFind(lowerText," now ",nowPos)==nowPos) ? 5 : 4;
      string suffix=CFastTrackSignalTextUtils::Trim(StringSubstr(text,nowPos+nowTokenLength));

      string prefixLower=StringSubstr(lowerText,0,nowPos);
      string prefixParts[];
      if(StringSplit(prefixLower,' ',prefixParts)<2)
        {
         failureDetail="Details header must start with '<symbol> <buy|sell>'";
         return false;
        }

      if(!CFastTrackSignalTextUtils::TryResolveSymbolAlias(prefixParts[0],symbolOut))
        {
         failureDetail="Unsupported symbol alias";
         return false;
        }

      if(!CFastTrackSignalTextUtils::TryResolveDirectionToken(prefixParts[1],directionOut))
        {
         failureDetail="Direction must be buy or sell";
         return false;
        }

      if(!CFastTrackSignalTextUtils::TryParseRangePair(suffix,rangeLowOut,rangeHighOut,failureDetail))
         return false;

      return true;
     }

public:
   static SFastTrackSignalParseResult ParseSeed(const string message)
     {
      SFastTrackSignalParseResult result;
      result.Reset();

      string text=CFastTrackSignalTextUtils::Trim(message);
      if(text=="")
        {
         result.Fail(BRE_FAST_TRACK_PARSE_EMPTY_MESSAGE);
         return result;
        }

      string symbol="";
      ENUM_BRE_TRADE_DIRECTION direction=BRE_DIRECTION_NONE;
      string failureDetail="";
      if(!TryParseSeedHeader(text,symbol,direction,failureDetail))
        {
         result.Fail(BRE_FAST_TRACK_PARSE_INVALID_SEED_FORMAT,failureDetail);
         return result;
        }

      result.SucceedSeed(symbol,direction);
      return result;
     }

   static SFastTrackSignalParseResult ParseDetails(const string message)
     {
      SFastTrackSignalParseResult result;
      result.Reset();

      string text=CFastTrackSignalTextUtils::Trim(message);
      if(text=="")
        {
         result.Fail(BRE_FAST_TRACK_PARSE_EMPTY_MESSAGE);
         return result;
        }

      string lines[];
      int lineCount=CFastTrackSignalTextUtils::SplitLines(text,lines);
      if(lineCount<=0)
        {
         result.Fail(BRE_FAST_TRACK_PARSE_EMPTY_MESSAGE);
         return result;
        }

      string symbol="";
      ENUM_BRE_TRADE_DIRECTION direction=BRE_DIRECTION_NONE;
      double rangeLow=0.0;
      double rangeHigh=0.0;
      string failureDetail="";
      if(!TryParseDetailsHeader(lines[0],symbol,direction,rangeLow,rangeHigh,failureDetail))
        {
         ENUM_BRE_FAST_TRACK_PARSE_FAILURE_REASON reason=
            StringFind(failureDetail,"alias")>=0 ? BRE_FAST_TRACK_PARSE_UNKNOWN_SYMBOL :
            StringFind(failureDetail,"Direction")>=0 ? BRE_FAST_TRACK_PARSE_UNKNOWN_DIRECTION :
            BRE_FAST_TRACK_PARSE_MISSING_ENTRY_RANGE;
         result.Fail(reason,failureDetail);
         return result;
        }

      double stopLoss=0.0;
      bool hasStopLoss=false;
      double takeProfits[];
      int takeProfitCount=0;
      bool runnerEnabled=false;

      for(int i=1;i<lineCount;i++)
        {
         string line=CFastTrackSignalTextUtils::Trim(lines[i]);
         if(line=="")
            continue;

         string key=line;
         string value="";
         int colonPos=StringFind(line,":");
         if(colonPos>=0)
           {
            key=CFastTrackSignalTextUtils::Trim(StringSubstr(line,0,colonPos));
            value=CFastTrackSignalTextUtils::Trim(StringSubstr(line,colonPos+1));
           }

         StringToUpper(key);
         if(key=="SL")
           {
            if(!CFastTrackSignalTextUtils::TryParseDoubleToken(value,stopLoss))
              {
               result.Fail(BRE_FAST_TRACK_PARSE_INVALID_NUMBER,"Stop loss value is invalid");
               return result;
              }
            hasStopLoss=true;
            continue;
           }

         if(key=="TP")
           {
            string normalizedValue=value;
            StringToLower(normalizedValue);
            if(normalizedValue=="open")
              {
               runnerEnabled=true;
               continue;
              }
            double tpValue=0.0;
            if(!CFastTrackSignalTextUtils::TryParseDoubleToken(value,tpValue))
              {
               result.Fail(BRE_FAST_TRACK_PARSE_INVALID_NUMBER,"Take-profit value is invalid");
               return result;
              }
            ArrayResize(takeProfits,takeProfitCount+1);
            takeProfits[takeProfitCount]=tpValue;
            takeProfitCount++;
            continue;
           }
        }

      if(!hasStopLoss)
        {
         result.Fail(BRE_FAST_TRACK_PARSE_MISSING_STOP_LOSS);
         return result;
        }

      ENUM_BRE_FAST_TRACK_PARSE_FAILURE_REASON geometryReason=BRE_FAST_TRACK_PARSE_OK;
      if(!CFastTrackSignalDetailsValidator::ValidateGeometry(direction,rangeLow,rangeHigh,stopLoss,
                                                             takeProfits,takeProfitCount,
                                                             geometryReason,failureDetail))
        {
         result.Fail(geometryReason,failureDetail);
         return result;
        }

      result.SucceedDetails(symbol,direction,rangeLow,rangeHigh,stopLoss,takeProfits,takeProfitCount,runnerEnabled);
      return result;
     }
  };

#endif
