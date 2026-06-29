#ifndef BRE_DOMAIN_BROKER_EXECUTION_FINGERPRINT_CANDIDATE_POLICY_MQH
#define BRE_DOMAIN_BROKER_EXECUTION_FINGERPRINT_CANDIDATE_POLICY_MQH

#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/BrokerCommentStamp.mqh>
#include <BasketRecovery/Domain/Execution/BrokerExecutionVolumePolicy.mqh>
#include <BasketRecovery/Domain/Execution/ReconciliationEvidencePolicy.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>

struct SFingerprintDealCandidate
  {
   datetime time;
   string   symbol;
   long     magic;
   double   volume;
   long     entryType;
   long     dealType;
  };

class CBrokerExecutionFingerprintCandidatePolicy
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

   static bool       VolumesEquivalent(const double left,const double right)
     {
      if(left<=0.0 || right<=0.0)
         return false;
      return MathAbs(NormalizeDouble(left,8)-NormalizeDouble(right,8))<=0.0000001;
     }

   static bool       IsExecutionDealType(const long dealType)
     {
      return dealType==DEAL_TYPE_BUY || dealType==DEAL_TYPE_SELL;
     }

   static bool       DealIntentMatchesEntry(const long dealEntryType,const CPendingExecutionEntry &entry)
     {
      if(entry.IntentType()==BRE_EXEC_INTENT_OPEN_POSITION)
         return dealEntryType==DEAL_ENTRY_IN || dealEntryType==DEAL_ENTRY_INOUT;
      if(entry.IntentType()==BRE_EXEC_INTENT_CLOSE_POSITION ||
         entry.IntentType()==BRE_EXEC_INTENT_REDUCE_POSITION)
         return dealEntryType==DEAL_ENTRY_OUT || dealEntryType==DEAL_ENTRY_INOUT;
      return true;
     }

public:
   static bool       IsEligibleForFingerprintScan(const CPendingExecutionEntry &entry)
     {
      long magic=entry.BrokerCorrelation().MagicNumber();
      if(magic<=0 || entry.RequestedVolume()<=0.0)
         return false;
      if(entry.CorrelationToken()=="" || !CBrokerCommentStamp::ValidateChecksum(entry.BrokerComment()))
         return false;
      return CReconciliationEvidencePolicy::ReconciliationAnchorUtc(entry)>0;
     }

   static void       ResolveTightWindow(const CPendingExecutionEntry &entry,
                                        const int fingerprintSecondsAfter,
                                        datetime &tightFromOut,
                                        datetime &tightToOut)
     {
      datetime anchor=CReconciliationEvidencePolicy::ReconciliationAnchorUtc(entry);
      tightFromOut=anchor-120;
      tightToOut=anchor+(datetime)fingerprintSecondsAfter;
      if(entry.DeadlineUtc()>0)
        {
         datetime deadlineTail=entry.DeadlineUtc()+120;
         if(deadlineTail>tightToOut)
            tightToOut=deadlineTail;
        }
     }

   static bool       IsDealFingerprintCandidate(const CPendingExecutionEntry &entry,
                                                const SFingerprintDealCandidate &candidate,
                                                const datetime tightFrom,
                                                const datetime tightTo)
     {
      if(candidate.time<tightFrom || candidate.time>tightTo)
         return false;
      if(!SymbolsEquivalent(entry.Symbol(),candidate.symbol))
         return false;
      if(entry.BrokerCorrelation().MagicNumber()!=candidate.magic)
         return false;
      if(!CBrokerExecutionVolumePolicy::VolumesEquivalent(candidate.volume,entry.RequestedVolume()))
         return false;
      if(!IsExecutionDealType(candidate.dealType))
         return false;
      if(!DealIntentMatchesEntry(candidate.entryType,entry))
         return false;
      return true;
     }

   static int        CountMatchingCandidates(const CPendingExecutionEntry &entry,
                                             const SFingerprintDealCandidate &candidates[],
                                             const int fingerprintSecondsAfter)
     {
      if(!IsEligibleForFingerprintScan(entry))
         return -1;

      datetime tightFrom=0;
      datetime tightTo=0;
      ResolveTightWindow(entry,fingerprintSecondsAfter,tightFrom,tightTo);

      int matchCount=0;
      for(int i=0;i<ArraySize(candidates);i++)
        {
         if(IsDealFingerprintCandidate(entry,candidates[i],tightFrom,tightTo))
            matchCount++;
        }
      return matchCount;
     }
  };

#endif
