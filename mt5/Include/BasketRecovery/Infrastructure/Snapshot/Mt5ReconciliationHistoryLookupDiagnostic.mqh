#ifndef BRE_INF_MT5_RECONCILIATION_HISTORY_LOOKUP_DIAGNOSTIC_MQH
#define BRE_INF_MT5_RECONCILIATION_HISTORY_LOOKUP_DIAGNOSTIC_MQH

#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/ReconciliationEvidencePolicy.mqh>
#include <BasketRecovery/Domain/Execution/BrokerCommentStamp.mqh>
#include <BasketRecovery/Domain/Execution/BrokerExecutionFingerprintCandidatePolicy.mqh>
#include <BasketRecovery/Domain/Execution/BrokerHistoricalOrderEvidencePolicy.mqh>
#include <BasketRecovery/Domain/Execution/BrokerExecutionVolumePolicy.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>

class CMt5ReconciliationHistoryLookupDiagnostic
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

   static bool       DealIntentMatchesEntry(const long dealEntryType,const CPendingExecutionEntry &entry)
     {
      if(entry.IntentType()==BRE_EXEC_INTENT_OPEN_POSITION)
         return dealEntryType==DEAL_ENTRY_IN || dealEntryType==DEAL_ENTRY_INOUT;
      if(entry.IntentType()==BRE_EXEC_INTENT_CLOSE_POSITION ||
         entry.IntentType()==BRE_EXEC_INTENT_REDUCE_POSITION)
         return dealEntryType==DEAL_ENTRY_OUT || dealEntryType==DEAL_ENTRY_INOUT;
      return true;
     }

   static string     DealEntryLabel(const long dealEntry)
     {
      if(dealEntry==DEAL_ENTRY_IN) return "IN";
      if(dealEntry==DEAL_ENTRY_OUT) return "OUT";
      if(dealEntry==DEAL_ENTRY_INOUT) return "INOUT";
      return "OTHER";
     }

   static string     OrderStateLabel(const long orderState)
     {
      if(orderState==ORDER_STATE_FILLED) return "FILLED";
      if(orderState==ORDER_STATE_PARTIAL) return "PARTIAL";
      if(orderState==ORDER_STATE_CANCELED) return "CANCELED";
      if(orderState==ORDER_STATE_REJECTED) return "REJECTED";
      if(orderState==ORDER_STATE_EXPIRED) return "EXPIRED";
      if(orderState==ORDER_STATE_STARTED) return "STARTED";
      return "OTHER";
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

   static ulong      FindCorrelatedDealTicket(const ulong orderTicket)
     {
      if(orderTicket==0)
         return 0;
      int deals=(int)HistoryDealsTotal();
      for(int i=deals-1;i>=0;i--)
        {
         ulong dealTicket=HistoryDealGetTicket(i);
         if(dealTicket==0 || !HistoryDealSelect(dealTicket))
            continue;
         if((ulong)HistoryDealGetInteger(dealTicket,DEAL_ORDER)==orderTicket)
            return dealTicket;
        }
      return 0;
     }

   static bool       TryKnownFixtureIds(const string executionRequestId,ulong &orderIdOut,ulong &dealIdOut)
     {
      orderIdOut=0;
      dealIdOut=0;
      if(executionRequestId=="sprint6g-req-001")
        {
         orderIdOut=1505820684;
         dealIdOut=1283464504;
         return true;
        }
      if(executionRequestId=="recovery-manual:375360093-3A70-2EF6")
        {
         orderIdOut=1506292323;
         dealIdOut=1283878782;
         return true;
        }
      return false;
     }

   static void       WriteLine(const int handle,const string line)
     {
      if(handle!=INVALID_HANDLE)
         FileWriteString(handle,line+"\r\n");
      Print(line);
     }

   static bool       StampValidForEntry(const string comment,const CPendingExecutionEntry &entry)
     {
      CBrokerCommentStampParsed parsed;
      if(!CBrokerCommentStamp::TryParse(comment,parsed))
         return false;
      if(entry.CorrelationToken()!="" && parsed.CorrelationToken()!=entry.CorrelationToken())
         return false;
      return true;
     }

public:
   static void       TraceRecord(const int reportHandle,
                                 const CPendingExecutionEntry &entry,
                                 const datetime nowUtc,
                                 const int windowSecondsBefore=604800,
                                 const int windowSecondsAfter=86400,
                                 const int fingerprintSecondsAfter=600)
     {
      datetime lookupFrom=0;
      datetime lookupTo=0;
      CReconciliationEvidencePolicy::ResolveHistorySelectWindow(entry,nowUtc,
                                                                windowSecondsBefore,
                                                                windowSecondsAfter,
                                                                lookupFrom,lookupTo);

      datetime tightFrom=0;
      datetime tightTo=0;
      CBrokerExecutionFingerprintCandidatePolicy::ResolveTightWindow(entry,fingerprintSecondsAfter,tightFrom,tightTo);

      datetime anchor=CReconciliationEvidencePolicy::ReconciliationAnchorUtc(entry);
      long filterMagic=entry.BrokerCorrelation().MagicNumber();
      string filterSymbol=entry.Symbol();
      double filterVolume=entry.RequestedVolume();
      string filterDirection=TradeExecutionIntentLabel(entry.IntentType());

      WriteLine(reportHandle,"history_diag.execution_request_id="+entry.ExecutionRequestId());
      WriteLine(reportHandle,"history_diag.created_timestamp="+IntegerToString((long)entry.CreatedAtUtc()));
      WriteLine(reportHandle,"history_diag.prepared_timestamp="+IntegerToString((long)entry.PreparedAtUtc()));
      WriteLine(reportHandle,"history_diag.submitted_timestamp="+IntegerToString((long)entry.SubmittedAtUtc()));
      WriteLine(reportHandle,"history_diag.reconciliation_anchor="+IntegerToString((long)anchor));
      WriteLine(reportHandle,"history_diag.lookup_start="+IntegerToString((long)lookupFrom));
      WriteLine(reportHandle,"history_diag.lookup_end="+IntegerToString((long)lookupTo));
      WriteLine(reportHandle,"history_diag.fingerprint_window_start="+IntegerToString((long)tightFrom));
      WriteLine(reportHandle,"history_diag.fingerprint_window_end="+IntegerToString((long)tightTo));
      WriteLine(reportHandle,"history_diag.filter_symbol="+filterSymbol);
      WriteLine(reportHandle,"history_diag.filter_magic="+IntegerToString(filterMagic));
      WriteLine(reportHandle,"history_diag.filter_volume="+DoubleToString(filterVolume,8));
      WriteLine(reportHandle,"history_diag.filter_direction="+filterDirection);
      WriteLine(reportHandle,"history_diag.persisted_broker_order_id="+IntegerToString((long)entry.BrokerCorrelation().BrokerOrderId()));
      WriteLine(reportHandle,"history_diag.persisted_broker_deal_id="+IntegerToString((long)entry.BrokerCorrelation().BrokerDealId()));

      ulong fixtureOrderId=0;
      ulong fixtureDealId=0;
      if(TryKnownFixtureIds(entry.ExecutionRequestId(),fixtureOrderId,fixtureDealId))
        {
         WriteLine(reportHandle,"history_diag.fixture_broker_order_id="+IntegerToString((long)fixtureOrderId));
         WriteLine(reportHandle,"history_diag.fixture_broker_deal_id="+IntegerToString((long)fixtureDealId));
        }

      HistorySelect(0,lookupTo);
      bool historySelected=HistorySelect(lookupFrom,lookupTo);
      WriteLine(reportHandle,"history_diag.history_select_from="+IntegerToString((long)lookupFrom));
      WriteLine(reportHandle,"history_diag.history_select_to="+IntegerToString((long)lookupTo));
      WriteLine(reportHandle,"history_diag.history_select_ok="+(historySelected?"true":"false"));

      int rawDeals=(int)HistoryDealsTotal();
      int rawOrders=(int)HistoryOrdersTotal();
      WriteLine(reportHandle,"history_diag.stage_raw_deals="+IntegerToString(rawDeals));
      WriteLine(reportHandle,"history_diag.stage_raw_orders="+IntegerToString(rawOrders));

      datetime earliestDeal=0;
      datetime latestDeal=0;
      int afterSymbol=0;
      int afterDirection=0;
      int afterVolume=0;
      int afterMagic=0;
      int afterTimestamp=0;
      int afterFingerprint=0;

      ulong directionSurvivorTicket=0;
      string directionSurvivorVolumeReason="";

      ulong probeOrderId=(entry.BrokerCorrelation().BrokerOrderId()>0 ?
                          entry.BrokerCorrelation().BrokerOrderId() :
                          fixtureOrderId);
      ulong probeDealId=(entry.BrokerCorrelation().BrokerDealId()>0 ?
                         entry.BrokerCorrelation().BrokerDealId() :
                         fixtureDealId);

      bool knownDealVisible=false;
      bool knownOrderVisible=false;

      int orderAfterSymbol=0;
      int orderAfterMagic=0;
      int orderAfterDirection=0;
      int orderAfterVolume=0;
      int orderAfterFilledState=0;
      int orderAfterTimestamp=0;
      int orderAfterFingerprint=0;
      int orderCandidateIndex=0;

      for(int o=0;o<rawOrders;o++)
        {
         ulong orderTicket=HistoryOrderGetTicket(o);
         if(orderTicket==probeOrderId)
            knownOrderVisible=true;
         if(orderTicket==0 || !HistoryOrderSelect(orderTicket))
            continue;

         string orderSymbol=HistoryOrderGetString(orderTicket,ORDER_SYMBOL);
         long orderMagic=HistoryOrderGetInteger(orderTicket,ORDER_MAGIC);
         long orderType=HistoryOrderGetInteger(orderTicket,ORDER_TYPE);
         long orderState=HistoryOrderGetInteger(orderTicket,ORDER_STATE);
         datetime orderSetup=(datetime)HistoryOrderGetInteger(orderTicket,ORDER_TIME_SETUP);
         datetime orderDone=(datetime)HistoryOrderGetInteger(orderTicket,ORDER_TIME_DONE);
         datetime orderEvidence=(orderDone>0 ? orderDone : orderSetup);
         double initialVolume=HistoryOrderGetDouble(orderTicket,ORDER_VOLUME_INITIAL);
         double currentVolume=HistoryOrderGetDouble(orderTicket,ORDER_VOLUME_CURRENT);
         double executedVolume=CBrokerHistoricalOrderEvidencePolicy::ComputeExecutedVolume(
            orderState,initialVolume,currentVolume);
         string orderComment=HistoryOrderGetString(orderTicket,ORDER_COMMENT);
         ulong linkedDeal=FindCorrelatedDealTicket(orderTicket);
         bool stampValid=StampValidForEntry(orderComment,entry);
         bool stateProvesFill=CBrokerHistoricalOrderEvidencePolicy::OrderStateProvesFill(orderState);
         bool stateProvesPartial=CBrokerHistoricalOrderEvidencePolicy::OrderStateProvesPartialFill(orderState);
         bool symbolMatch=SymbolsEquivalent(filterSymbol,orderSymbol);
         bool magicMatch=(filterMagic<=0 || orderMagic==filterMagic);
         bool directionMatch=CBrokerHistoricalOrderEvidencePolicy::OrderTypeMatchesIntent(orderType,entry.IntentType());
         bool volumeMatch=CBrokerExecutionVolumePolicy::VolumesEquivalent(executedVolume,filterVolume);
         bool timestampMatch=(orderEvidence>=tightFrom && orderEvidence<=tightTo);

         SFingerprintOrderCandidate orderCandidate;
         orderCandidate.time=orderEvidence;
         orderCandidate.symbol=orderSymbol;
         orderCandidate.magic=orderMagic;
         orderCandidate.orderType=orderType;
         orderCandidate.orderState=orderState;
         orderCandidate.executedVolume=executedVolume;

         bool fingerprintMatch=CBrokerHistoricalOrderEvidencePolicy::IsOrderFingerprintCandidate(
            entry,orderCandidate,tightFrom,tightTo);

         string rejectReason="accepted";
         if(!symbolMatch) rejectReason="symbol_mismatch";
         else if(!magicMatch) rejectReason="magic_mismatch";
         else if(!directionMatch) rejectReason="direction_mismatch";
         else if(CBrokerHistoricalOrderEvidencePolicy::OrderStateIsTerminalNonFill(orderState))
            rejectReason="terminal_non_fill_state="+OrderStateLabel(orderState);
         else if(!stateProvesFill && !stateProvesPartial) rejectReason="order_state_not_executable="+OrderStateLabel(orderState);
         else if(executedVolume<=0.0) rejectReason="executed_volume_zero";
         else if(!volumeMatch) rejectReason=CBrokerExecutionVolumePolicy::VolumeMismatchReason(executedVolume,filterVolume);
         else if(!timestampMatch) rejectReason="outside_bounded_timestamp_window";
         else if(!fingerprintMatch) rejectReason="fingerprint_policy_rejected";

         if(symbolMatch || magicMatch || stampValid || orderTicket==probeOrderId)
           {
            orderCandidateIndex++;
            WriteLine(reportHandle,"history_diag.order_candidate["+IntegerToString(orderCandidateIndex)+"]="
                                  +"ticket="+IntegerToString((long)orderTicket)
                                  +" | time_setup="+IntegerToString((long)orderSetup)
                                  +" | time_done="+IntegerToString((long)orderDone)
                                  +" | order_type="+IntegerToString(orderType)
                                  +" | order_state="+OrderStateLabel(orderState)
                                  +" | symbol="+orderSymbol
                                  +" | magic="+IntegerToString(orderMagic)
                                  +" | stamp_valid="+(stampValid?"true":"false")
                                  +" | comment_present="+(orderComment!=""?"true":"false")
                                  +" | initial_volume="+DoubleToString(initialVolume,8)
                                  +" | current_volume="+DoubleToString(currentVolume,8)
                                  +" | executed_volume="+DoubleToString(executedVolume,8)
                                  +" | linked_deal_ticket="+IntegerToString((long)linkedDeal)
                                  +" | state_proves_fill="+(stateProvesFill?"true":"false")
                                  +" | decision="+rejectReason);
           }

         if(!symbolMatch) continue;
         orderAfterSymbol++;
         if(!magicMatch) continue;
         orderAfterMagic++;
         if(!directionMatch) continue;
         orderAfterDirection++;
         if(executedVolume<=0.0) continue;
         if(!volumeMatch) continue;
         orderAfterVolume++;
         if(!stateProvesFill && !stateProvesPartial) continue;
         orderAfterFilledState++;
         if(!timestampMatch) continue;
         orderAfterTimestamp++;
         if(!fingerprintMatch) continue;
         orderAfterFingerprint++;
        }

      for(int i=0;i<rawDeals;i++)
        {
         ulong dealTicket=HistoryDealGetTicket(i);
         if(dealTicket==0 || !HistoryDealSelect(dealTicket))
            continue;

         datetime dealTime=(datetime)HistoryDealGetInteger(dealTicket,DEAL_TIME);
         if(earliestDeal==0 || dealTime<earliestDeal)
            earliestDeal=dealTime;
         if(latestDeal==0 || dealTime>latestDeal)
            latestDeal=dealTime;

         if(dealTicket==probeDealId)
            knownDealVisible=true;

         string dealSymbol=HistoryDealGetString(dealTicket,DEAL_SYMBOL);
         long dealMagic=ResolveHistoryDealMagic(dealTicket);
         double dealVolume=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
         long dealEntry=HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
         long dealType=HistoryDealGetInteger(dealTicket,DEAL_TYPE);
         ulong linkedOrder=(ulong)HistoryDealGetInteger(dealTicket,DEAL_ORDER);

         if(!SymbolsEquivalent(filterSymbol,dealSymbol))
            continue;
         afterSymbol++;

         if(!DealIntentMatchesEntry(dealEntry,entry))
            continue;
         afterDirection++;
         directionSurvivorTicket=dealTicket;

         if(!CBrokerExecutionVolumePolicy::VolumesEquivalent(dealVolume,filterVolume))
           {
            directionSurvivorVolumeReason=CBrokerExecutionVolumePolicy::VolumeMismatchReason(dealVolume,filterVolume);
            WriteLine(reportHandle,"history_diag.deal_direction_survivor="
                                  +"ticket="+IntegerToString((long)dealTicket)
                                  +" | entry="+DealEntryLabel(dealEntry)
                                  +" | type="+IntegerToString(dealType)
                                  +" | volume="+DoubleToString(dealVolume,8)
                                  +" | magic="+IntegerToString(dealMagic)
                                  +" | linked_order="+IntegerToString((long)linkedOrder)
                                  +" | deal_time="+IntegerToString((long)dealTime)
                                  +" | volume_mismatch_reason="+directionSurvivorVolumeReason);
            continue;
           }
         afterVolume++;

         if(filterMagic>0 && dealMagic!=filterMagic)
            continue;
         afterMagic++;

         if(dealTime<tightFrom || dealTime>tightTo)
            continue;
         afterTimestamp++;

         SFingerprintDealCandidate candidate;
         candidate.time=dealTime;
         candidate.symbol=dealSymbol;
         candidate.magic=dealMagic;
         candidate.volume=dealVolume;
         candidate.entryType=dealEntry;
         candidate.dealType=dealType;
         if(CBrokerExecutionFingerprintCandidatePolicy::IsDealFingerprintCandidate(entry,candidate,tightFrom,tightTo))
            afterFingerprint++;
        }

      WriteLine(reportHandle,"history_diag.earliest_deal_time="+IntegerToString((long)earliestDeal));
      WriteLine(reportHandle,"history_diag.latest_deal_time="+IntegerToString((long)latestDeal));
      WriteLine(reportHandle,"history_diag.known_deal_visible="+(knownDealVisible?"true":"false"));
      WriteLine(reportHandle,"history_diag.known_order_visible="+(knownOrderVisible?"true":"false"));
      WriteLine(reportHandle,"history_diag.stage_after_symbol="+IntegerToString(afterSymbol));
      WriteLine(reportHandle,"history_diag.stage_after_direction="+IntegerToString(afterDirection));
      WriteLine(reportHandle,"history_diag.stage_after_volume="+IntegerToString(afterVolume));
      WriteLine(reportHandle,"history_diag.stage_after_magic="+IntegerToString(afterMagic));
      WriteLine(reportHandle,"history_diag.stage_after_timestamp="+IntegerToString(afterTimestamp));
      WriteLine(reportHandle,"history_diag.stage_after_fingerprint="+IntegerToString(afterFingerprint));
      WriteLine(reportHandle,"history_diag.order_stage_after_symbol="+IntegerToString(orderAfterSymbol));
      WriteLine(reportHandle,"history_diag.order_stage_after_magic="+IntegerToString(orderAfterMagic));
      WriteLine(reportHandle,"history_diag.order_stage_after_direction="+IntegerToString(orderAfterDirection));
      WriteLine(reportHandle,"history_diag.order_stage_after_volume="+IntegerToString(orderAfterVolume));
      WriteLine(reportHandle,"history_diag.order_stage_after_filled_state="+IntegerToString(orderAfterFilledState));
      WriteLine(reportHandle,"history_diag.order_stage_after_timestamp="+IntegerToString(orderAfterTimestamp));
      WriteLine(reportHandle,"history_diag.order_stage_after_fingerprint="+IntegerToString(orderAfterFingerprint));
      WriteLine(reportHandle,"history_diag.fingerprint_eligible="+
                (CBrokerExecutionFingerprintCandidatePolicy::IsEligibleForFingerprintScan(entry)?"true":"false"));
      WriteLine(reportHandle,"history_diag.order_fingerprint_eligible="+
                (CBrokerHistoricalOrderEvidencePolicy::IsEligibleForOrderFingerprintScan(entry)?"true":"false"));
     }
  };

#endif
