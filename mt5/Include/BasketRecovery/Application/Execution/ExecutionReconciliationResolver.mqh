#ifndef BRE_APP_EXECUTION_RECONCILIATION_RESOLVER_MQH
#define BRE_APP_EXECUTION_RECONCILIATION_RESOLVER_MQH

#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionQuery.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionReconciliationTransitionGate.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionPersistedFillEvidence.mqh>
#include <BasketRecovery/Domain/Execution/ReconciliationEvidencePolicy.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionReconciliationReport.mqh>
#include <BasketRecovery/Application/Ports/IBrokerPositionReader.mqh>
#include <BasketRecovery/Application/Ports/IBrokerExecutionHistoryReader.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>

class CExecutionReconciliationResolver
  {
private:
   static bool       QueryCurrentOpenMatch(const CPendingExecutionEntry &entry,
                                           IBrokerPositionReader *positionReader,
                                           double &matchedVolumeOut,
                                           string &openStateOut)
     {
      matchedVolumeOut=0.0;
      openStateOut="position_query_failed";
      if(positionReader==NULL)
         return false;

      CPositionSnapshotEntry positions[];
      CResult<int> readResult=positionReader.ReadOpenPositions(positions,64);
      if(readResult.IsFail())
        {
         openStateOut="position_query_indeterminate";
         return false;
        }

      int count=0;
      readResult.TryGetValue(count);

      ulong ticket=entry.BrokerCorrelation().PositionTicket();
      long magic=entry.BrokerCorrelation().MagicNumber();
      string symbol=entry.Symbol();
      double matchedVolume=0.0;
      bool found=false;

      for(int i=0;i<count;i++)
        {
         if(ticket>0 && positions[i].Ticket()!=ticket)
            continue;
         if(ticket==0 && magic>0 && positions[i].Magic()!=magic)
            continue;
         if(positions[i].Symbol()!=symbol)
            continue;
         found=true;
         matchedVolume+=positions[i].Volume();
        }

      matchedVolumeOut=matchedVolume;
      if(found)
        {
         openStateOut="open_position_match";
         return true;
        }

      openStateOut="open_position_missing";
      return false;
     }

   static CBrokerExecutionHistoryCorrelation QueryHistoryCorrelation(const CPendingExecutionEntry &entry,
                                                                     IBrokerExecutionHistoryReader *historyReader)
     {
      if(historyReader==NULL)
         return CBrokerExecutionHistoryCorrelation::Unavailable("history_reader_unavailable");

      CBrokerExecutionHistoryCorrelation correlation;
      CResult<bool> result=historyReader.CorrelateExecutionHistory(entry,correlation);
      if(result.IsFail())
         return CBrokerExecutionHistoryCorrelation::Unavailable("history_query_failed");
      bool queried=false;
      result.TryGetValue(queried);
      if(!queried)
         return CBrokerExecutionHistoryCorrelation::Unavailable(correlation.Summary());
      return correlation;
     }

   static string     HistoryStateLabel(const CBrokerExecutionHistoryCorrelation &correlation)
     {
      if(!correlation.QueryAvailable())
         return correlation.Summary();
      if(correlation.HasFillEvidence())
         return "historical_fill";
      if(correlation.HasRejectEvidence())
         return "historical_reject";
      if(correlation.HasCancelEvidence())
         return "historical_cancel";
      if(correlation.HasFailureEvidence())
         return "historical_failure";
      if(correlation.HasOpenPendingOrder())
         return "open_pending_order";
      return correlation.Summary();
     }

   static string     ConfidenceForState(const ENUM_BRE_TRADE_EXECUTION_STATUS status,
                                        const bool openMatched,
                                        const CBrokerExecutionHistoryCorrelation &history)
     {
      if(status==BRE_TRADE_EXEC_STATUS_FILLED && (openMatched || history.HasFillEvidence()))
         return "high";
      if(status==BRE_TRADE_EXEC_STATUS_REJECTED && history.HasRejectEvidence())
         return "high";
      if(status==BRE_TRADE_EXEC_STATUS_TIMED_OUT && history.QueryAvailable())
         return "medium";
      if(status==BRE_TRADE_EXEC_STATUS_RECONCILING)
         return "low";
      if(status==BRE_TRADE_EXEC_STATUS_UNKNOWN)
         return "none";
      return "medium";
     }

   static bool       MutationPermittedForState(const CPendingExecutionEntry &entry,
                                               const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus,
                                               const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus)
     {
      if(fromStatus==toStatus)
         return false;
      if(CPendingExecutionQuery::IsTerminalStatus(fromStatus))
         return false;
      if(!CPendingExecutionPersistedFillEvidence::IsTerminalFillMonotonic(fromStatus,toStatus))
         return false;
      if(CPendingExecutionPersistedFillEvidence::BlocksDowngradeToNonFill(entry,toStatus))
         return false;
      return CPendingExecutionReconciliationTransitionGate::CanResolveFromBrokerRead(fromStatus,toStatus);
     }

   static ENUM_BRE_TRADE_EXECUTION_STATUS ResolvePersistedFillState(const CPendingExecutionEntry &entry)
     {
      if(!CPendingExecutionPersistedFillEvidence::HasKnownFill(entry))
         return BRE_TRADE_EXEC_STATUS_NONE;

      if(entry.RequestedVolume()>0.0 && entry.FilledVolume()+0.0000001>=entry.RequestedVolume())
         return BRE_TRADE_EXEC_STATUS_FILLED;
      if(entry.FilledVolume()>0.0)
         return BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED;
      return BRE_TRADE_EXEC_STATUS_FILLED;
     }

   static ENUM_BRE_TRADE_EXECUTION_STATUS Decide(const CPendingExecutionEntry &entry,
                                                 const double openMatchedVolume,
                                                 const bool openMatched,
                                                 const CBrokerExecutionHistoryCorrelation &history,
                                                 const datetime nowUtc)
     {
      ENUM_BRE_TRADE_EXECUTION_STATUS persistedFill=ResolvePersistedFillState(entry);
      if(persistedFill!=BRE_TRADE_EXEC_STATUS_NONE)
         return persistedFill;

      if(openMatched)
        {
         if(entry.RequestedVolume()>0.0 && openMatchedVolume+0.0000001>=entry.RequestedVolume())
            return BRE_TRADE_EXEC_STATUS_FILLED;
         if(openMatchedVolume>0.0)
            return BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED;
         return BRE_TRADE_EXEC_STATUS_UNKNOWN;
        }

      if(history.HasOpenPendingOrder())
         return BRE_TRADE_EXEC_STATUS_UNKNOWN;

      if(history.HasFillEvidence())
        {
         if(entry.RequestedVolume()>0.0 && history.FillVolume()+0.0000001>=entry.RequestedVolume())
            return BRE_TRADE_EXEC_STATUS_FILLED;
         if(history.FillVolume()>0.0)
            return BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED;
         return BRE_TRADE_EXEC_STATUS_FILLED;
        }

      if(history.HasRejectEvidence())
         return BRE_TRADE_EXEC_STATUS_REJECTED;

      if(history.HasCancelEvidence())
         return BRE_TRADE_EXEC_STATUS_CANCELLED;

      if(history.HasFailureEvidence())
         return BRE_TRADE_EXEC_STATUS_FAILED;

      if(history.FingerprintCandidateCount()>1 ||
         history.OrderFilledCandidateCount()>1 ||
         history.Summary()=="fingerprint_ambiguous" ||
         history.Summary()=="stamp_ambiguous" ||
         history.Summary()=="order_fill_ambiguous")
         return BRE_TRADE_EXEC_STATUS_RECONCILING;

      if(history.QueryAvailable())
        {
         if(CReconciliationEvidencePolicy::IsEvidenceWindowElapsed(
               entry,
               nowUtc,
               CReconciliationEvidencePolicy::DefaultEvidenceWindowSecondsAfter()))
            return BRE_TRADE_EXEC_STATUS_TIMED_OUT;
         return BRE_TRADE_EXEC_STATUS_RECONCILING;
        }

      return BRE_TRADE_EXEC_STATUS_RECONCILING;
     }

public:
   static ENUM_BRE_TRADE_EXECUTION_STATUS Resolve(const CPendingExecutionEntry &entry,
                                                  IBrokerPositionReader *positionReader,
                                                  double &matchedVolumeOut,
                                                  IBrokerExecutionHistoryReader *historyReader=NULL,
                                                  const datetime nowUtc=0)
     {
      CExecutionReconciliationReport report;
      return ResolveWithReport(entry,positionReader,matchedVolumeOut,historyReader,nowUtc,report);
     }

   static ENUM_BRE_TRADE_EXECUTION_STATUS ResolveWithReport(const CPendingExecutionEntry &entry,
                                                            IBrokerPositionReader *positionReader,
                                                            double &matchedVolumeOut,
                                                            IBrokerExecutionHistoryReader *historyReader,
                                                            const datetime nowUtc,
                                                            CExecutionReconciliationReport &reportOut)
     {
      matchedVolumeOut=0.0;
      datetime effectiveNow=(nowUtc>0 ? nowUtc : TimeCurrent());

      if(CPendingExecutionPersistedFillEvidence::HasKnownFill(entry))
        {
         matchedVolumeOut=entry.FilledVolume();
         if(matchedVolumeOut<=0.0 && entry.RequestedVolume()>0.0)
            matchedVolumeOut=entry.RequestedVolume();
        }

      double openMatchedVolume=0.0;
      string openState="";
      bool openMatched=QueryCurrentOpenMatch(entry,positionReader,openMatchedVolume,openState);
      if(openMatched)
         matchedVolumeOut=openMatchedVolume;

      CBrokerExecutionHistoryCorrelation history=QueryHistoryCorrelation(entry,historyReader);
      if(!openMatched && history.HasFillEvidence())
         matchedVolumeOut=history.FillVolume();

      ENUM_BRE_TRADE_EXECUTION_STATUS resolved=Decide(entry,openMatchedVolume,openMatched,history,effectiveNow);

      reportOut.SetCurrentOpenState(openState);
      reportOut.SetHistoryCorrelationState(HistoryStateLabel(history));
      reportOut.SetFinalState(resolved);
      reportOut.SetConfidence(ConfidenceForState(resolved,openMatched,history));
      reportOut.SetMutationPermitted(MutationPermittedForState(entry,entry.Status(),resolved));
      reportOut.SetEvidenceMethod(history.EvidenceMethod());
      reportOut.SetFingerprintCandidateCount(history.FingerprintCandidateCount());
      reportOut.SetStampCandidateCount(history.StampCandidateCount());
      reportOut.SetOrderFilledCandidateCount(history.OrderFilledCandidateCount());
      return resolved;
     }
  };

#endif
