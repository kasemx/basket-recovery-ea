#ifndef BRE_INF_MT5_BROKER_EXECUTION_HISTORY_READER_MQH
#define BRE_INF_MT5_BROKER_EXECUTION_HISTORY_READER_MQH

#include <BasketRecovery/Application/Ports/IBrokerExecutionHistoryReader.mqh>
#include <BasketRecovery/Domain/Execution/BrokerCommentStamp.mqh>
#include <BasketRecovery/Domain/Execution/BrokerExecutionFingerprintCandidatePolicy.mqh>
#include <BasketRecovery/Domain/Execution/ReconciliationEvidencePolicy.mqh>
#include <BasketRecovery/Domain/Execution/BrokerExecutionVolumePolicy.mqh>
#include <BasketRecovery/Domain/Execution/BrokerHistoricalOrderEvidencePolicy.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CMt5BrokerExecutionHistoryReader : public IBrokerExecutionHistoryReader
  {
private:
   int               m_windowSecondsBefore;
   int               m_windowSecondsAfter;
   int               m_fingerprintSecondsAfter;

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
      return CBrokerExecutionVolumePolicy::VolumesEquivalent(left,right);
     }

   static bool       IsExecutionDealType(const long dealType)
     {
      return dealType==DEAL_TYPE_BUY || dealType==DEAL_TYPE_SELL;
     }

   bool              HasOpenPendingOrder(const ulong orderId) const
     {
      if(orderId==0)
         return false;
      for(int i=OrdersTotal()-1;i>=0;i--)
        {
         ulong ticket=OrderGetTicket(i);
         if(ticket==orderId)
            return true;
        }
      return false;
     }

   bool              StampMatchesEntry(const string dealComment,const CPendingExecutionEntry &entry) const
     {
      CBrokerCommentStampParsed parsed;
      if(!CBrokerCommentStamp::TryParse(dealComment,parsed))
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

   bool              CommentMatchesEntry(const string comment,const CPendingExecutionEntry &entry) const
     {
      if(StampMatchesEntry(comment,entry))
         return true;
      if(entry.CorrelationToken()!="" && StringFind(comment,entry.CorrelationToken())>=0)
         return true;
      if(entry.BrokerComment()!="" && StringFind(comment,entry.BrokerComment())>=0)
         return true;
      if(StringFind(comment,entry.ExecutionRequestId())>=0)
         return true;
      return false;
     }

   string            ResolveDealComment(const ulong dealTicket) const
     {
      if(dealTicket==0 || !HistoryDealSelect(dealTicket))
         return "";

      string comment=HistoryDealGetString(dealTicket,DEAL_COMMENT);
      if(comment!="")
         return comment;

      ulong orderTicket=(ulong)HistoryDealGetInteger(dealTicket,DEAL_ORDER);
      if(orderTicket==0 || !HistoryOrderSelect(orderTicket))
         return "";

      return HistoryOrderGetString(orderTicket,ORDER_COMMENT);
     }

   bool              DealIntentMatchesEntry(const ulong dealTicket,const CPendingExecutionEntry &entry) const
     {
      if(!HistoryDealSelect(dealTicket))
         return false;
      long dealEntry=HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
      if(entry.IntentType()==BRE_EXEC_INTENT_OPEN_POSITION)
         return dealEntry==DEAL_ENTRY_IN || dealEntry==DEAL_ENTRY_INOUT;
      if(entry.IntentType()==BRE_EXEC_INTENT_CLOSE_POSITION ||
         entry.IntentType()==BRE_EXEC_INTENT_REDUCE_POSITION)
         return dealEntry==DEAL_ENTRY_OUT || dealEntry==DEAL_ENTRY_INOUT;
      return true;
     }

   bool              DealMatchesEntry(const ulong dealTicket,
                                      const CPendingExecutionEntry &entry,
                                      double &matchedVolumeOut,
                                      int &stampCandidateCountOut) const
     {
      if(dealTicket==0 || !HistoryDealSelect(dealTicket))
         return false;

      string symbol=HistoryDealGetString(dealTicket,DEAL_SYMBOL);
      if(!SymbolsEquivalent(entry.Symbol(),symbol))
         return false;

      long magic=entry.BrokerCorrelation().MagicNumber();
      if(magic>0 && ResolveHistoryDealMagic(dealTicket)!=magic)
         return false;

      if(!IsExecutionDealType(HistoryDealGetInteger(dealTicket,DEAL_TYPE)))
         return false;

      string comment=ResolveDealComment(dealTicket);
      ulong dealId=entry.BrokerCorrelation().BrokerDealId();
      if(dealId>0 && dealTicket==dealId)
        {
         double volume=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
         if(volume<=0.0)
            return false;
         matchedVolumeOut+=volume;
         return true;
        }

      if(!CommentMatchesEntry(comment,entry))
         return false;

      stampCandidateCountOut++;

      if(!DealIntentMatchesEntry(dealTicket,entry))
         return false;

      double volume=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
      if(volume<=0.0)
         return false;

      matchedVolumeOut+=volume;
      return true;
     }

   bool              OrderMatchesEntry(const ulong orderTicket,
                                       const CPendingExecutionEntry &entry,
                                       double &matchedVolumeOut,
                                       int &stampCandidateCountOut) const
     {
      if(orderTicket==0 || !HistoryOrderSelect(orderTicket))
         return false;

      string symbol=HistoryOrderGetString(orderTicket,ORDER_SYMBOL);
      if(!SymbolsEquivalent(entry.Symbol(),symbol))
         return false;

      long magic=entry.BrokerCorrelation().MagicNumber();
      if(magic>0 && HistoryOrderGetInteger(orderTicket,ORDER_MAGIC)!=magic)
         return false;

      string comment=HistoryOrderGetString(orderTicket,ORDER_COMMENT);
      if(!CommentMatchesEntry(comment,entry))
         return false;

      stampCandidateCountOut++;

      int deals=(int)HistoryDealsTotal();
      bool foundDeal=false;
      for(int i=deals-1;i>=0;i--)
        {
         ulong dealTicket=HistoryDealGetTicket(i);
         if(dealTicket==0 || !HistoryDealSelect(dealTicket))
            continue;
         if((ulong)HistoryDealGetInteger(dealTicket,DEAL_ORDER)!=orderTicket)
            continue;
         if(!DealIntentMatchesEntry(dealTicket,entry))
            continue;
         double volume=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
         if(volume<=0.0)
            continue;
         matchedVolumeOut+=volume;
         foundDeal=true;
        }

      if(foundDeal)
         return true;

      double initialVolume=HistoryOrderGetDouble(orderTicket,ORDER_VOLUME_INITIAL);
      double currentVolume=HistoryOrderGetDouble(orderTicket,ORDER_VOLUME_CURRENT);
      double filledVolume=initialVolume-currentVolume;
      if(filledVolume>0.0 && VolumesEquivalent(filledVolume,entry.RequestedVolume()))
        {
         matchedVolumeOut+=filledVolume;
         return true;
        }

      return false;
     }

   int               CountBoundedFillFingerprintCandidates(const CPendingExecutionEntry &entry) const
     {
      if(!CBrokerExecutionFingerprintCandidatePolicy::IsEligibleForFingerprintScan(entry))
         return -1;

      datetime tightFrom=0;
      datetime tightTo=0;
      CBrokerExecutionFingerprintCandidatePolicy::ResolveTightWindow(entry,m_fingerprintSecondsAfter,tightFrom,tightTo);

      int matchCount=0;
      int deals=(int)HistoryDealsTotal();
      for(int i=deals-1;i>=0;i--)
        {
         ulong dealTicket=HistoryDealGetTicket(i);
         if(dealTicket==0 || !HistoryDealSelect(dealTicket))
            continue;

         SFingerprintDealCandidate candidate;
         candidate.time=(datetime)HistoryDealGetInteger(dealTicket,DEAL_TIME);
         candidate.symbol=HistoryDealGetString(dealTicket,DEAL_SYMBOL);
         candidate.magic=ResolveHistoryDealMagic(dealTicket);
         candidate.volume=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
         candidate.entryType=HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
         candidate.dealType=HistoryDealGetInteger(dealTicket,DEAL_TYPE);

         if(CBrokerExecutionFingerprintCandidatePolicy::IsDealFingerprintCandidate(
               entry,candidate,tightFrom,tightTo))
            matchCount++;
        }
      return matchCount;
     }

   bool              TryCorrelateBoundedFillFingerprint(const CPendingExecutionEntry &entry,
                                                        const int candidateCount,
                                                        double &matchedVolumeOut) const
     {
      if(candidateCount!=1)
         return false;

      datetime tightFrom=0;
      datetime tightTo=0;
      CBrokerExecutionFingerprintCandidatePolicy::ResolveTightWindow(entry,m_fingerprintSecondsAfter,tightFrom,tightTo);

      int deals=(int)HistoryDealsTotal();
      for(int i=deals-1;i>=0;i--)
        {
         ulong dealTicket=HistoryDealGetTicket(i);
         if(dealTicket==0 || !HistoryDealSelect(dealTicket))
            continue;

         SFingerprintDealCandidate candidate;
         candidate.time=(datetime)HistoryDealGetInteger(dealTicket,DEAL_TIME);
         candidate.symbol=HistoryDealGetString(dealTicket,DEAL_SYMBOL);
         candidate.magic=ResolveHistoryDealMagic(dealTicket);
         candidate.volume=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
         candidate.entryType=HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
         candidate.dealType=HistoryDealGetInteger(dealTicket,DEAL_TYPE);

         if(!CBrokerExecutionFingerprintCandidatePolicy::IsDealFingerprintCandidate(
               entry,candidate,tightFrom,tightTo))
            continue;

         matchedVolumeOut+=candidate.volume;
         return true;
        }
      return false;
     }

   static datetime   ResolveOrderEvidenceTime(const ulong orderTicket)
     {
      if(orderTicket==0 || !HistoryOrderSelect(orderTicket))
         return 0;
      datetime doneTime=(datetime)HistoryOrderGetInteger(orderTicket,ORDER_TIME_DONE);
      if(doneTime>0)
         return doneTime;
      return (datetime)HistoryOrderGetInteger(orderTicket,ORDER_TIME_SETUP);
     }

   static bool       BuildOrderCandidate(const ulong orderTicket,SFingerprintOrderCandidate &candidateOut)
     {
      if(orderTicket==0 || !HistoryOrderSelect(orderTicket))
         return false;
      long state=HistoryOrderGetInteger(orderTicket,ORDER_STATE);
      candidateOut.time=ResolveOrderEvidenceTime(orderTicket);
      candidateOut.symbol=HistoryOrderGetString(orderTicket,ORDER_SYMBOL);
      candidateOut.magic=HistoryOrderGetInteger(orderTicket,ORDER_MAGIC);
      candidateOut.orderType=HistoryOrderGetInteger(orderTicket,ORDER_TYPE);
      candidateOut.orderState=state;
      candidateOut.executedVolume=CBrokerHistoricalOrderEvidencePolicy::ComputeExecutedVolume(
         state,
         HistoryOrderGetDouble(orderTicket,ORDER_VOLUME_INITIAL),
         HistoryOrderGetDouble(orderTicket,ORDER_VOLUME_CURRENT));
      return candidateOut.time>0;
     }

   bool              TryPersistedBrokerOrderFilledEvidence(const ulong orderTicket,
                                                           const CPendingExecutionEntry &entry,
                                                           double &matchedVolumeOut,
                                                           string &evidenceMethodOut) const
     {
      if(orderTicket==0 || entry.BrokerCorrelation().BrokerOrderId()!=orderTicket)
         return false;
      if(!HistoryOrderSelect(orderTicket))
         return false;

      string symbol=HistoryOrderGetString(orderTicket,ORDER_SYMBOL);
      if(!SymbolsEquivalent(entry.Symbol(),symbol))
         return false;

      long magic=entry.BrokerCorrelation().MagicNumber();
      if(magic>0 && HistoryOrderGetInteger(orderTicket,ORDER_MAGIC)!=magic)
         return false;

      long state=HistoryOrderGetInteger(orderTicket,ORDER_STATE);
      if(CBrokerHistoricalOrderEvidencePolicy::OrderStateIsTerminalNonFill(state))
         return false;
      if(!CBrokerHistoricalOrderEvidencePolicy::OrderStateProvesFill(state) &&
         !CBrokerHistoricalOrderEvidencePolicy::OrderStateProvesPartialFill(state))
         return false;

      double executed=CBrokerHistoricalOrderEvidencePolicy::ComputeExecutedVolume(
         state,
         HistoryOrderGetDouble(orderTicket,ORDER_VOLUME_INITIAL),
         HistoryOrderGetDouble(orderTicket,ORDER_VOLUME_CURRENT));
      if(executed<=0.0)
         return false;

      matchedVolumeOut=executed;
      evidenceMethodOut=CBrokerHistoricalOrderEvidencePolicy::OrderStateProvesFill(state) ?
                        "persisted_broker_order_filled" :
                        "persisted_broker_order_partial";
      return true;
     }

   int               CountBoundedFilledOrderCandidates(const CPendingExecutionEntry &entry) const
     {
      if(!CBrokerHistoricalOrderEvidencePolicy::IsEligibleForOrderFingerprintScan(entry))
         return -1;

      datetime tightFrom=0;
      datetime tightTo=0;
      CBrokerExecutionFingerprintCandidatePolicy::ResolveTightWindow(entry,m_fingerprintSecondsAfter,tightFrom,tightTo);

      int matchCount=0;
      int orders=(int)HistoryOrdersTotal();
      for(int i=orders-1;i>=0;i--)
        {
         ulong orderTicket=HistoryOrderGetTicket(i);
         SFingerprintOrderCandidate candidate;
         if(!BuildOrderCandidate(orderTicket,candidate))
            continue;
         if(CBrokerHistoricalOrderEvidencePolicy::IsOrderFingerprintCandidate(
               entry,candidate,tightFrom,tightTo))
            matchCount++;
        }
      return matchCount;
     }

   bool              TryCorrelateBoundedFilledOrderFingerprint(const CPendingExecutionEntry &entry,
                                                               const int candidateCount,
                                                               double &matchedVolumeOut) const
     {
      if(candidateCount!=1)
         return false;

      datetime tightFrom=0;
      datetime tightTo=0;
      CBrokerExecutionFingerprintCandidatePolicy::ResolveTightWindow(entry,m_fingerprintSecondsAfter,tightFrom,tightTo);

      int orders=(int)HistoryOrdersTotal();
      for(int i=orders-1;i>=0;i--)
        {
         ulong orderTicket=HistoryOrderGetTicket(i);
         SFingerprintOrderCandidate candidate;
         if(!BuildOrderCandidate(orderTicket,candidate))
            continue;
         if(!CBrokerHistoricalOrderEvidencePolicy::IsOrderFingerprintCandidate(
               entry,candidate,tightFrom,tightTo))
            continue;
         matchedVolumeOut+=candidate.executedVolume;
         return true;
        }
      return false;
     }

   int               CountStampedFilledOrderCandidates(const CPendingExecutionEntry &entry) const
     {
      if(!CBrokerHistoricalOrderEvidencePolicy::IsEligibleForStampedOrderScan(entry))
         return -1;

      datetime tightFrom=0;
      datetime tightTo=0;
      CBrokerExecutionFingerprintCandidatePolicy::ResolveTightWindow(entry,m_fingerprintSecondsAfter,tightFrom,tightTo);

      int matchCount=0;
      int orders=(int)HistoryOrdersTotal();
      for(int i=orders-1;i>=0;i--)
        {
         ulong orderTicket=HistoryOrderGetTicket(i);
         SFingerprintOrderCandidate candidate;
         if(!BuildOrderCandidate(orderTicket,candidate))
            continue;
         string comment=HistoryOrderGetString(orderTicket,ORDER_COMMENT);
         if(CBrokerHistoricalOrderEvidencePolicy::IsStampedFilledOrderCandidate(
               entry,candidate,comment,tightFrom,tightTo))
            matchCount++;
        }
      return matchCount;
     }

   bool              TryCorrelateUniqueStampedFilledOrder(const CPendingExecutionEntry &entry,
                                                          const int candidateCount,
                                                          double &matchedVolumeOut) const
     {
      if(candidateCount!=1)
         return false;

      datetime tightFrom=0;
      datetime tightTo=0;
      CBrokerExecutionFingerprintCandidatePolicy::ResolveTightWindow(entry,m_fingerprintSecondsAfter,tightFrom,tightTo);

      int orders=(int)HistoryOrdersTotal();
      for(int i=orders-1;i>=0;i--)
        {
         ulong orderTicket=HistoryOrderGetTicket(i);
         SFingerprintOrderCandidate candidate;
         if(!BuildOrderCandidate(orderTicket,candidate))
            continue;
         string comment=HistoryOrderGetString(orderTicket,ORDER_COMMENT);
         if(!CBrokerHistoricalOrderEvidencePolicy::IsStampedFilledOrderCandidate(
               entry,candidate,comment,tightFrom,tightTo))
            continue;
         matchedVolumeOut+=candidate.executedVolume;
         return true;
        }
      return false;
     }

   bool              OrderShowsExplicitReject(const ulong orderId,
                                              const CPendingExecutionEntry &entry) const
     {
      if(orderId==0 || !HistoryOrderSelect(orderId))
         return false;

      string symbol=HistoryOrderGetString(orderId,ORDER_SYMBOL);
      if(!SymbolsEquivalent(entry.Symbol(),symbol))
         return false;

      long state=HistoryOrderGetInteger(orderId,ORDER_STATE);
      if(state!=ORDER_STATE_CANCELED)
         return false;

      double orderVolume=HistoryOrderGetDouble(orderId,ORDER_VOLUME_INITIAL);
      double filledVolume=HistoryOrderGetDouble(orderId,ORDER_VOLUME_CURRENT);
      if(orderVolume>0.0 && filledVolume>0.0)
         return false;

      int deals=HistoryDealsTotal();
      for(int i=deals-1;i>=0;i--)
        {
         ulong dealTicket=HistoryDealGetTicket(i);
         if(dealTicket==0 || !HistoryDealSelect(dealTicket))
            continue;
         if((ulong)HistoryDealGetInteger(dealTicket,DEAL_ORDER)!=orderId)
            continue;
         if(HistoryDealGetDouble(dealTicket,DEAL_VOLUME)>0.0)
            return false;
        }
      return true;
     }

   static long       ResolveHistoryDealMagic(const ulong dealTicket)
     {
      if(dealTicket==0 || !HistoryDealSelect(dealTicket))
         return 0;

      long magic=HistoryDealGetInteger(dealTicket,DEAL_MAGIC);
      if(magic!=0)
         return magic;

      ulong orderTicket=(ulong)HistoryDealGetInteger(dealTicket,DEAL_ORDER);
      if(orderTicket==0 || !HistoryOrderSelect(orderTicket))
         return 0;

      return HistoryOrderGetInteger(orderTicket,ORDER_MAGIC);
     }

   bool              SelectHistoryWindow(const CPendingExecutionEntry &entry) const
     {
      datetime nowUtc=TimeCurrent();
      datetime from=0;
      datetime to=0;
      CReconciliationEvidencePolicy::ResolveHistorySelectWindow(entry,nowUtc,
                                                                m_windowSecondsBefore,
                                                                m_windowSecondsAfter,
                                                                from,to);

      HistorySelect(0,to);
      return HistorySelect(from,to);
     }

public:
                     CMt5BrokerExecutionHistoryReader(const int windowSecondsBefore=604800,
                                                      const int windowSecondsAfter=86400,
                                                      const int fingerprintSecondsAfter=600)
     {
      m_windowSecondsBefore=(windowSecondsBefore<=0 ? 604800 : windowSecondsBefore);
      m_windowSecondsAfter=(windowSecondsAfter<=0 ? 86400 : windowSecondsAfter);
      m_fingerprintSecondsAfter=(fingerprintSecondsAfter<=0 ?
                                 CReconciliationEvidencePolicy::DefaultBoundedFingerprintSecondsAfter() :
                                 fingerprintSecondsAfter);
     }

   virtual CResult<bool> CorrelateExecutionHistory(const CPendingExecutionEntry &entry,
                                                   CBrokerExecutionHistoryCorrelation &outCorrelation) const
     {
      outCorrelation=CBrokerExecutionHistoryCorrelation::Unqueried();

      ulong orderId=entry.BrokerCorrelation().BrokerOrderId();
      if(HasOpenPendingOrder(orderId))
        {
         outCorrelation.SetQueryAvailable(true);
         outCorrelation.SetHasOpenPendingOrder(true);
         outCorrelation.SetEvidenceMethod("open_pending_order");
         outCorrelation.SetSummary("open_pending_order");
         return CResult<bool>::Ok(true);
        }

      bool historySelected=SelectHistoryWindow(entry);
      outCorrelation.SetQueryAvailable(historySelected);
      if(!historySelected)
        {
         outCorrelation.SetSummary("history_query_unavailable");
         return CResult<bool>::Ok(false);
        }

      double matchedVolume=0.0;
      int stampCandidateCount=0;
      string evidenceMethod="none";
      ulong dealId=entry.BrokerCorrelation().BrokerDealId();

      if(dealId>0 && DealMatchesEntry(dealId,entry,matchedVolume,stampCandidateCount))
         evidenceMethod="persisted_broker_deal_id";

      if(matchedVolume<=0.0 && orderId>0)
        {
         if(TryPersistedBrokerOrderFilledEvidence(orderId,entry,matchedVolume,evidenceMethod))
           { /* evidence method assigned by helper */ }
         else
           {
            int deals=(int)HistoryDealsTotal();
            for(int i=deals-1;i>=0;i--)
              {
               ulong dealTicket=HistoryDealGetTicket(i);
               if(dealTicket==0 || !HistoryDealSelect(dealTicket))
                  continue;
               if((ulong)HistoryDealGetInteger(dealTicket,DEAL_ORDER)!=orderId)
                  continue;
               if(DealMatchesEntry(dealTicket,entry,matchedVolume,stampCandidateCount))
                  evidenceMethod="persisted_broker_order_deal";
              }
           }
        }

      int stampedOrderCandidateCount=CountStampedFilledOrderCandidates(entry);
      if(matchedVolume<=0.0 && stampedOrderCandidateCount==1 &&
         TryCorrelateUniqueStampedFilledOrder(entry,stampedOrderCandidateCount,matchedVolume))
        {
         evidenceMethod="historical_stamped_order_filled";
         outCorrelation.SetSummary("historical_stamped_order_filled");
        }
      else if(stampedOrderCandidateCount>1)
        {
         outCorrelation.SetEvidenceMethod("order_fill_ambiguous");
         outCorrelation.SetSummary("order_fill_ambiguous");
        }

      int orderFingerprintCandidateCount=CountBoundedFilledOrderCandidates(entry);
      outCorrelation.SetOrderFilledCandidateCount(orderFingerprintCandidateCount);

      if(matchedVolume<=0.0)
        {
         if(orderFingerprintCandidateCount>1)
           {
            outCorrelation.SetEvidenceMethod("order_fill_ambiguous");
            outCorrelation.SetSummary("order_fill_ambiguous");
           }
         else if(TryCorrelateBoundedFilledOrderFingerprint(entry,orderFingerprintCandidateCount,matchedVolume))
           {
            evidenceMethod="historical_order_fingerprint_fill";
            outCorrelation.SetSummary("historical_order_fingerprint_fill");
           }
        }

      if(matchedVolume<=0.0)
        {
         int orders=(int)HistoryOrdersTotal();
         for(int i=orders-1;i>=0;i--)
           {
            ulong orderTicket=HistoryOrderGetTicket(i);
            if(orderTicket==0)
               continue;
            if(OrderMatchesEntry(orderTicket,entry,matchedVolume,stampCandidateCount))
              {
               if(evidenceMethod=="none")
                  evidenceMethod="order_comment_stamp";
              }
           }
        }

      if(matchedVolume<=0.0)
        {
         int deals=(int)HistoryDealsTotal();
         for(int i=deals-1;i>=0;i--)
           {
            ulong dealTicket=HistoryDealGetTicket(i);
            if(dealTicket==0)
               continue;
            if(DealMatchesEntry(dealTicket,entry,matchedVolume,stampCandidateCount))
              {
               if(evidenceMethod=="none")
                  evidenceMethod="deal_or_order_comment_stamp";
              }
           }
        }

      int fingerprintCandidateCount=CountBoundedFillFingerprintCandidates(entry);
      outCorrelation.SetFingerprintCandidateCount(fingerprintCandidateCount);
      outCorrelation.SetStampCandidateCount(stampCandidateCount);

      if(matchedVolume>0.0 &&
         stampCandidateCount>1 &&
         evidenceMethod!="persisted_broker_deal_id" &&
         evidenceMethod!="persisted_broker_order_filled" &&
         evidenceMethod!="persisted_broker_order_deal")
        {
         matchedVolume=0.0;
         evidenceMethod="stamp_ambiguous";
         outCorrelation.SetSummary("stamp_ambiguous");
        }

      if(matchedVolume<=0.0)
        {
         if(fingerprintCandidateCount>1)
           {
            outCorrelation.SetEvidenceMethod("fingerprint_ambiguous");
            outCorrelation.SetSummary("fingerprint_ambiguous");
           }
         else if(TryCorrelateBoundedFillFingerprint(entry,fingerprintCandidateCount,matchedVolume))
           {
            evidenceMethod="historical_fingerprint_fill";
            outCorrelation.SetSummary("historical_fingerprint_fill");
           }
        }

      if(matchedVolume>0.0)
        {
         outCorrelation.SetHasFillEvidence(true);
         outCorrelation.SetFillVolume(matchedVolume);
         outCorrelation.SetEvidenceMethod(evidenceMethod);
         if(outCorrelation.Summary()=="unqueried")
            outCorrelation.SetSummary("historical_fill");
         return CResult<bool>::Ok(true);
        }

      if(fingerprintCandidateCount>1 || orderFingerprintCandidateCount>1 || stampedOrderCandidateCount>1)
         outCorrelation.SetEvidenceMethod("order_or_fingerprint_ambiguous");
      else if(outCorrelation.EvidenceMethod()=="none")
         outCorrelation.SetEvidenceMethod(evidenceMethod);

      if(OrderShowsExplicitReject(orderId,entry))
        {
         outCorrelation.SetHasRejectEvidence(true);
         outCorrelation.SetEvidenceMethod("historical_order_reject");
         outCorrelation.SetSummary("historical_order_reject");
         return CResult<bool>::Ok(true);
        }

      if(outCorrelation.Summary()=="fingerprint_ambiguous" ||
         outCorrelation.Summary()=="order_fill_ambiguous" ||
         outCorrelation.Summary()=="stamp_ambiguous")
         { /* keep summary */ }
      else if(fingerprintCandidateCount>1)
         outCorrelation.SetSummary("fingerprint_ambiguous");

      outCorrelation.SetSummary(outCorrelation.Summary()=="unqueried" ?
                                "history_no_execution_match" :
                                outCorrelation.Summary());
      return CResult<bool>::Ok(true);
     }
  };

#endif
