#ifndef BRE_DOMAIN_BROKER_HISTORICAL_ORDER_EVIDENCE_POLICY_MQH
#define BRE_DOMAIN_BROKER_HISTORICAL_ORDER_EVIDENCE_POLICY_MQH

#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/BrokerCommentStamp.mqh>
#include <BasketRecovery/Domain/Execution/BrokerExecutionVolumePolicy.mqh>
#include <BasketRecovery/Domain/Execution/BrokerExecutionFingerprintCandidatePolicy.mqh>
#include <BasketRecovery/Domain/Execution/ReconciliationEvidencePolicy.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

struct SFingerprintOrderCandidate
  {
   datetime time;
   string   symbol;
   long     magic;
   long     orderType;
   long     orderState;
   double   executedVolume;
  };

class CBrokerHistoricalOrderEvidencePolicy
  {
private:
   static string     NormalizeSymbolKey(const string symbol)
     {
      string key=symbol;
      StringToUpper(key);
      while(StringLen(key)>0)
        {
         ushort last=(ushort)StringGetCharacter(key,StringLen(key)-1);
         if(last=='.' || last=='m' || last=='M')
            key=StringSubstr(key,0,StringLen(key)-1);
         else
            break;
        }
      return key;
     }

   static bool       SymbolsEquivalent(const string left,const string right)
     {
      if(left=="" || right=="")
         return true;
      if(left==right)
         return true;
      return NormalizeSymbolKey(left)==NormalizeSymbolKey(right);
     }

   static bool       StampMatchesEntry(const string orderComment,const CPendingExecutionEntry &entry)
     {
      CBrokerCommentStampParsed parsed;
      if(!CBrokerCommentStamp::TryParse(orderComment,parsed))
         return false;
      if(entry.CorrelationToken()!="" && parsed.CorrelationToken()!=entry.CorrelationToken())
         return false;
      if(entry.BrokerComment()!="" && parsed.FullComment()!=entry.BrokerComment())
        {
         if(StringFind(entry.BrokerComment(),parsed.CorrelationToken())<0)
            return false;
        }
      return true;
     }

public:
   static bool       OrderStateProvesFill(const long orderState)
     {
      return orderState==ORDER_STATE_FILLED;
     }

   static bool       OrderStateProvesPartialFill(const long orderState)
     {
      return orderState==ORDER_STATE_PARTIAL;
     }

   static bool       OrderStateIsTerminalNonFill(const long orderState)
     {
      return orderState==ORDER_STATE_CANCELED ||
             orderState==ORDER_STATE_REJECTED ||
             orderState==ORDER_STATE_EXPIRED;
     }

   static double     ComputeExecutedVolume(const long orderState,
                                           const double initialVolume,
                                           const double currentVolume)
     {
      if(initialVolume<=0.0)
         return 0.0;
      if(OrderStateProvesFill(orderState))
         return CBrokerExecutionVolumePolicy::NormalizeVolume(initialVolume);
      if(OrderStateProvesPartialFill(orderState) || orderState==ORDER_STATE_STARTED)
         return CBrokerExecutionVolumePolicy::NormalizeVolume(initialVolume-currentVolume);
      return 0.0;
     }

   static bool       OrderTypeMatchesIntent(const long orderType,
                                            const ENUM_BRE_TRADE_EXECUTION_INTENT intent,
                                            const ENUM_BRE_TRADE_DIRECTION direction=BRE_DIRECTION_NONE)
     {
      if(intent==BRE_EXEC_INTENT_OPEN_POSITION)
        {
         if(direction==BRE_DIRECTION_BUY)
            return orderType==ORDER_TYPE_BUY;
         if(direction==BRE_DIRECTION_SELL)
            return orderType==ORDER_TYPE_SELL;
         return orderType==ORDER_TYPE_BUY || orderType==ORDER_TYPE_SELL;
        }
      if(intent==BRE_EXEC_INTENT_CLOSE_POSITION || intent==BRE_EXEC_INTENT_REDUCE_POSITION)
        {
         if(direction==BRE_DIRECTION_BUY)
            return orderType==ORDER_TYPE_BUY;
         if(direction==BRE_DIRECTION_SELL)
            return orderType==ORDER_TYPE_SELL;
         return orderType==ORDER_TYPE_BUY || orderType==ORDER_TYPE_SELL;
        }
      return true;
     }

   static bool       IsEligibleForOrderFingerprintScan(const CPendingExecutionEntry &entry)
     {
      long magic=entry.BrokerCorrelation().MagicNumber();
      if(magic<=0 || entry.RequestedVolume()<=0.0)
         return false;
      return CReconciliationEvidencePolicy::ReconciliationAnchorUtc(entry)>0;
     }

   static bool       IsEligibleForStampedOrderScan(const CPendingExecutionEntry &entry)
     {
      if(entry.CorrelationToken()=="" || !CBrokerCommentStamp::ValidateChecksum(entry.BrokerComment()))
         return false;
      return IsEligibleForOrderFingerprintScan(entry);
     }

   static bool       IsOrderFingerprintCandidate(const CPendingExecutionEntry &entry,
                                                 const SFingerprintOrderCandidate &candidate,
                                                 const datetime tightFrom,
                                                 const datetime tightTo,
                                                 const ENUM_BRE_TRADE_DIRECTION direction=BRE_DIRECTION_NONE)
     {
      if(candidate.time<tightFrom || candidate.time>tightTo)
         return false;
      if(!SymbolsEquivalent(entry.Symbol(),candidate.symbol))
         return false;
      if(entry.BrokerCorrelation().MagicNumber()!=candidate.magic)
         return false;
      if(!OrderStateProvesFill(candidate.orderState))
         return false;
      if(!CBrokerExecutionVolumePolicy::VolumesEquivalent(candidate.executedVolume,entry.RequestedVolume()))
         return false;
      if(!OrderTypeMatchesIntent(candidate.orderType,entry.IntentType(),direction))
         return false;
      return true;
     }

   static bool       IsStampedFilledOrderCandidate(const CPendingExecutionEntry &entry,
                                                   const SFingerprintOrderCandidate &candidate,
                                                   const string orderComment,
                                                   const datetime tightFrom,
                                                   const datetime tightTo,
                                                   const ENUM_BRE_TRADE_DIRECTION direction=BRE_DIRECTION_NONE)
     {
      if(!StampMatchesEntry(orderComment,entry))
         return false;
      return IsOrderFingerprintCandidate(entry,candidate,tightFrom,tightTo,direction);
     }

   static int        CountMatchingOrderCandidates(const CPendingExecutionEntry &entry,
                                                  const SFingerprintOrderCandidate &candidates[],
                                                  const int fingerprintSecondsAfter,
                                                  const bool requireStamp,
                                                  string &comments[],
                                                  const ENUM_BRE_TRADE_DIRECTION direction=BRE_DIRECTION_NONE)
     {
      if(requireStamp)
        {
         if(!IsEligibleForStampedOrderScan(entry))
            return -1;
        }
      else if(!IsEligibleForOrderFingerprintScan(entry))
         return -1;

      datetime tightFrom=0;
      datetime tightTo=0;
      CBrokerExecutionFingerprintCandidatePolicy::ResolveTightWindow(entry,fingerprintSecondsAfter,tightFrom,tightTo);

      int matchCount=0;
      for(int i=0;i<ArraySize(candidates);i++)
        {
         if(requireStamp)
           {
            if(IsStampedFilledOrderCandidate(entry,candidates[i],comments[i],tightFrom,tightTo,direction))
               matchCount++;
           }
         else if(IsOrderFingerprintCandidate(entry,candidates[i],tightFrom,tightTo,direction))
           {
            matchCount++;
           }
        }
      return matchCount;
     }
  };

#endif
