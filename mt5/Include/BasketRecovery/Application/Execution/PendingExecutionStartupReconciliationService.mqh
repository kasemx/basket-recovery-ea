#ifndef BRE_APP_PENDING_EXECUTION_STARTUP_RECONCILIATION_SERVICE_MQH
#define BRE_APP_PENDING_EXECUTION_STARTUP_RECONCILIATION_SERVICE_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionLifecycleService.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionReconciliationHydrator.mqh>
#include <BasketRecovery/Application/Execution/ExecutionReconciliationResolver.mqh>
#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>
#include <BasketRecovery/Application/Ports/IBrokerPositionReader.mqh>
#include <BasketRecovery/Application/Ports/IBrokerExecutionHistoryReader.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionQuery.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionTransitionRules.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionCorrelationState.mqh>
#include <BasketRecovery/Domain/Execution/ReconciliationEvidencePolicy.mqh>
#include <BasketRecovery/Domain/Execution/BrokerExecutionVolumePolicy.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateRegistry.mqh>
#include <BasketRecovery/Application/Execution/ProfitCloseFilledPendingCompletionService.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>

#define BRE_FALSE_REJECTED_STARTUP_RECONCILE_BUILD_MARKER "S8C_FALSE_REJECTED_STARTUP_RECONCILE_V3"
#define BRE_FALSE_REJECTED_HISTORY_EVIDENCE_BUILD_MARKER "S8C_FALSE_REJECTED_HISTORY_EVIDENCE_V3"

class IPendingExecutionFillNotifier
  {
public:
   virtual          ~IPendingExecutionFillNotifier(void) {}
   virtual void      OnBrokerFillConfirmed(const string executionRequestId,const string completionPath="")=0;
  };

struct SFalseRejectedHistoryEvidence
  {
   ulong             dealId;
   double            fillVolume;
   string            comment;
  };

class CPendingExecutionStartupReconciliationService
  {
private:
   static void       LogFalseRejectedCandidateRejected(const string reason)
     {
      Print("false_rejected_history_reconcile_candidate=false");
      Print("false_rejected_history_reconcile_reason=",reason);
     }

   static void       LogFalseRejectedCandidateAccepted(const CPendingExecutionEntry &entry,
                                                       const SFalseRejectedHistoryEvidence &evidence,
                                                       const ulong selectedOrderId,
                                                       const ulong selectedPositionId)
     {
      Print("false_rejected_history_reconcile_candidate=true");
      Print("false_rejected_history_reconcile_execution_request_id=",entry.ExecutionRequestId());
      Print("false_rejected_history_reconcile_ticket=",
            IntegerToString((long)entry.BrokerCorrelation().PositionTicket()));
      Print("false_rejected_history_reconcile_deal_id=",IntegerToString((long)evidence.dealId));
      Print("false_rejected_history_reconcile_comment=",evidence.comment);
      Print("false_rejected_history_reconcile_evidence=exact_comment_ticket_order_deal_out_volume_time");
      Print("history_reconcile_selected_deal_id=",IntegerToString((long)evidence.dealId));
      Print("history_reconcile_selected_order_id=",IntegerToString((long)selectedOrderId));
      Print("history_reconcile_selected_position_id=",IntegerToString((long)selectedPositionId));
     }

   static bool       FillVolumeMeetsRequested(const double fillVolume,const double requestedVolume)
     {
      if(fillVolume<=0.0)
         return false;
      if(requestedVolume<=0.0)
         return true;
      return CBrokerExecutionVolumePolicy::NormalizeVolume(fillVolume)>=
             CBrokerExecutionVolumePolicy::NormalizeVolume(requestedVolume)-0.0000001;
     }

   static datetime   ResolvePendingCreatedAtAnchor(const CPendingExecutionEntry &entry)
     {
      return CReconciliationEvidencePolicy::ReconciliationAnchorUtc(entry);
     }

   static long       ResolveExpectedCloseDealTypeFromEnvelopeCloseDirection(const ENUM_BRE_TRADE_DIRECTION closeDirection)
     {
      switch(closeDirection)
        {
         case BRE_DIRECTION_BUY:
            return DEAL_TYPE_BUY;
         case BRE_DIRECTION_SELL:
            return DEAL_TYPE_SELL;
         default:
            return -1;
        }
     }

   static bool       TryResolveEnvelopeCloseDirection(IPendingExecutionStore *store,
                                                      const CPendingExecutionEntry &entry,
                                                      ENUM_BRE_TRADE_DIRECTION &closeDirectionOut)
     {
      closeDirectionOut=BRE_DIRECTION_NONE;
      if(store==NULL || entry.IdempotencyKey()=="")
         return false;

      CResult<CBrokerSubmissionEnvelope> envelopeResult=store.FindEnvelopeByIdempotencyKey(entry.IdempotencyKey());
      if(envelopeResult.IsFail())
         return false;

      CBrokerSubmissionEnvelope envelope;
      if(!envelopeResult.TryGetValue(envelope))
         return false;

      closeDirectionOut=envelope.Direction();
      return closeDirectionOut!=BRE_DIRECTION_NONE;
     }

   static void       PrintHistoryReconcileEnvelopeContext(IPendingExecutionStore *store,
                                                          const CPendingExecutionEntry &entry,
                                                          const datetime pendingCreatedAtAnchor)
     {
      ENUM_BRE_TRADE_DIRECTION closeDirection=BRE_DIRECTION_NONE;
      bool hasEnvelope=TryResolveEnvelopeCloseDirection(store,entry,closeDirection);
      long expectedDealType=ResolveExpectedCloseDealTypeFromEnvelopeCloseDirection(closeDirection);

      Print("history_reconcile_envelope_close_direction=",
            hasEnvelope ? CTradeDirectionHelper::ToString(closeDirection) : "UNAVAILABLE");
      Print("history_reconcile_expected_close_deal_type=",
            expectedDealType>=0 ? IntegerToString(expectedDealType) : "UNAVAILABLE");
      Print("history_reconcile_pending_created_at_anchor=",IntegerToString((long)pendingCreatedAtAnchor));
      Print("history_reconcile_persisted_broker_order_id=",
            IntegerToString((long)entry.BrokerCorrelation().BrokerOrderId()));
     }

   static bool       IsDealIdSeen(const ulong &seenDealIds[],const ulong dealId)
     {
      for(int i=0;i<ArraySize(seenDealIds);i++)
        {
         if(seenDealIds[i]==dealId)
            return true;
        }
      return false;
     }

   static void       RememberDealId(ulong &seenDealIds[],const ulong dealId)
     {
      int size=ArraySize(seenDealIds);
      ArrayResize(seenDealIds,size+1);
      seenDealIds[size]=dealId;
     }

   static bool       PassesSafetySelectionEvidence(const CPendingExecutionEntry &entry,
                                                   const ulong dealTicket,
                                                   const string expectedComment,
                                                   const ulong targetTicket,
                                                   const ulong persistedBrokerOrderId,
                                                   const datetime pendingCreatedAtAnchor)
     {
      if(dealTicket==0 || !HistoryDealSelect(dealTicket))
         return false;

      string dealComment=HistoryDealGetString(dealTicket,DEAL_COMMENT);
      if(dealComment!=expectedComment)
         return false;

      ulong positionId=(ulong)HistoryDealGetInteger(dealTicket,DEAL_POSITION_ID);
      if(positionId!=targetTicket)
         return false;

      if(HistoryDealGetInteger(dealTicket,DEAL_ENTRY)!=DEAL_ENTRY_OUT)
         return false;

      double dealVolume=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
      if(!FillVolumeMeetsRequested(dealVolume,entry.RequestedVolume()))
         return false;

      if(persistedBrokerOrderId==0)
         return false;

      ulong orderId=(ulong)HistoryDealGetInteger(dealTicket,DEAL_ORDER);
      if(orderId!=persistedBrokerOrderId)
         return false;

      datetime dealTime=(datetime)HistoryDealGetInteger(dealTicket,DEAL_TIME);
      if(pendingCreatedAtAnchor>0 && dealTime<pendingCreatedAtAnchor)
         return false;

      return true;
     }

   static bool       PassesCurrentFourFilterEvidence(const CPendingExecutionEntry &entry,
                                                     const ulong dealTicket,
                                                     const string expectedComment,
                                                     const ulong targetTicket)
     {
      if(dealTicket==0 || !HistoryDealSelect(dealTicket))
         return false;

      string dealComment=HistoryDealGetString(dealTicket,DEAL_COMMENT);
      if(dealComment!=expectedComment)
         return false;

      ulong positionId=(ulong)HistoryDealGetInteger(dealTicket,DEAL_POSITION_ID);
      if(positionId!=targetTicket)
         return false;

      if(HistoryDealGetInteger(dealTicket,DEAL_ENTRY)!=DEAL_ENTRY_OUT)
         return false;

      if(entry.Symbol()!="")
        {
         string dealSymbol=HistoryDealGetString(dealTicket,DEAL_SYMBOL);
         if(dealSymbol!=entry.Symbol())
            return false;
        }

      double dealVolume=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
      if(!FillVolumeMeetsRequested(dealVolume,entry.RequestedVolume()))
         return false;

      return true;
     }

   static void       PrintHistoryReconcileCandidateRow(const CPendingExecutionEntry &entry,
                                                       const ulong dealTicket,
                                                       const string expectedComment,
                                                       const ulong targetTicket,
                                                       const ulong persistedBrokerOrderId,
                                                       const datetime pendingCreatedAtAnchor)
     {
      if(!HistoryDealSelect(dealTicket))
         return;

      string dealComment=HistoryDealGetString(dealTicket,DEAL_COMMENT);
      ulong positionId=(ulong)HistoryDealGetInteger(dealTicket,DEAL_POSITION_ID);
      ulong orderId=(ulong)HistoryDealGetInteger(dealTicket,DEAL_ORDER);
      long dealEntry=HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
      long dealType=HistoryDealGetInteger(dealTicket,DEAL_TYPE);
      double dealVolume=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
      datetime dealTime=(datetime)HistoryDealGetInteger(dealTicket,DEAL_TIME);

      bool exactCommentMatch=(dealComment==expectedComment);
      bool exactTicketMatch=(positionId==targetTicket);
      bool dealOutMatch=(dealEntry==DEAL_ENTRY_OUT);
      bool volumeMatch=FillVolumeMeetsRequested(dealVolume,entry.RequestedVolume());
      bool orderMatch=(persistedBrokerOrderId>0 && orderId==persistedBrokerOrderId);
      bool afterPendingCreatedAt=(pendingCreatedAtAnchor<=0 || dealTime>=pendingCreatedAtAnchor);

      Print("history_reconcile_candidate_deal_id=",IntegerToString((long)dealTicket));
      Print("history_reconcile_candidate_order_id=",IntegerToString((long)orderId));
      Print("history_reconcile_candidate_position_id=",IntegerToString((long)positionId));
      Print("history_reconcile_candidate_entry=",IntegerToString(dealEntry));
      Print("history_reconcile_candidate_type=",IntegerToString(dealType));
      Print("history_reconcile_candidate_volume=",DoubleToString(dealVolume,8));
      Print("history_reconcile_candidate_comment=",dealComment);
      Print("history_reconcile_candidate_time=",IntegerToString((long)dealTime));
      Print("history_reconcile_candidate_exact_comment_match=",exactCommentMatch?"true":"false");
      Print("history_reconcile_candidate_exact_ticket_match=",exactTicketMatch?"true":"false");
      Print("history_reconcile_candidate_deal_out_match=",dealOutMatch?"true":"false");
      Print("history_reconcile_candidate_volume_match=",volumeMatch?"true":"false");
      Print("history_reconcile_candidate_order_match=",orderMatch?"true":"false");
      Print("history_reconcile_candidate_after_pending_created_at=",afterPendingCreatedAt?"true":"false");
     }

   static void       PrintHistoryReconcileCandidateSummary(const int matchCount)
     {
      Print("history_reconcile_candidate_count=",IntegerToString(matchCount));
      if(matchCount>1)
         Print("history_reconcile_ambiguity_reason=ambiguous_exact_deal_match");
      else if(matchCount==0)
         Print("history_reconcile_ambiguity_reason=no_exact_deal_match");
      else
         Print("history_reconcile_ambiguity_reason=none");
     }

   static bool       TryFindFalseRejectedHistoryEvidence(IPendingExecutionStore *store,
                                                         const CPendingExecutionEntry &entry,
                                                         SFalseRejectedHistoryEvidence &evidenceOut,
                                                         string &reasonOut,
                                                         ulong &selectedOrderIdOut,
                                                         ulong &selectedPositionIdOut)
     {
      evidenceOut.dealId=0;
      evidenceOut.fillVolume=0.0;
      evidenceOut.comment="";
      reasonOut="";
      selectedOrderIdOut=0;
      selectedPositionIdOut=0;

      Print("false_rejected_history_evidence_build_marker=",BRE_FALSE_REJECTED_HISTORY_EVIDENCE_BUILD_MARKER);
      Print("history_reconcile_target_execution_request_id=",entry.ExecutionRequestId());

      if(entry.IntentType()!=BRE_EXEC_INTENT_CLOSE_POSITION)
        {
         reasonOut="not_close_position";
         return false;
        }

      string expectedComment=entry.BrokerComment();
      if(expectedComment=="")
        {
         reasonOut="missing_broker_comment";
         return false;
        }

      ulong targetTicket=entry.BrokerCorrelation().PositionTicket();
      if(targetTicket==0)
        {
         reasonOut="missing_target_ticket";
         return false;
        }

      ulong persistedBrokerOrderId=entry.BrokerCorrelation().BrokerOrderId();
      datetime pendingCreatedAtAnchor=ResolvePendingCreatedAtAnchor(entry);
      PrintHistoryReconcileEnvelopeContext(store,entry,pendingCreatedAtAnchor);

      datetime nowUtc=TimeCurrent();
      datetime fromUtc=0;
      datetime toUtc=0;
      CReconciliationEvidencePolicy::ResolveHistorySelectWindow(entry,nowUtc,604800,86400,fromUtc,toUtc);
      if(!HistorySelect(fromUtc,toUtc))
        {
         reasonOut="history_query_unavailable";
         return false;
        }

      ulong seenDealIds[];
      ulong uniqueCandidateDealIds[];
      bool duplicateIgnored=false;
      int deals=(int)HistoryDealsTotal();
      for(int i=deals-1;i>=0;i--)
        {
         ulong dealTicket=HistoryDealGetTicket(i);
         if(!PassesCurrentFourFilterEvidence(entry,dealTicket,expectedComment,targetTicket))
            continue;

         PrintHistoryReconcileCandidateRow(entry,dealTicket,expectedComment,targetTicket,
                                           persistedBrokerOrderId,pendingCreatedAtAnchor);

         if(IsDealIdSeen(seenDealIds,dealTicket))
           {
            Print("history_reconcile_duplicate_deal_ignored=true");
            Print("history_reconcile_duplicate_deal_id=",IntegerToString((long)dealTicket));
            duplicateIgnored=true;
            continue;
           }

         RememberDealId(seenDealIds,dealTicket);
         RememberDealId(uniqueCandidateDealIds,dealTicket);
        }

      int uniqueCandidateCount=ArraySize(uniqueCandidateDealIds);
      Print("history_reconcile_duplicate_deal_ignored=",duplicateIgnored?"true":"false");
      Print("history_reconcile_unique_candidate_count=",IntegerToString(uniqueCandidateCount));
      PrintHistoryReconcileCandidateSummary(uniqueCandidateCount);

      if(uniqueCandidateCount==0)
        {
         reasonOut="no_exact_deal_match";
         return false;
        }
      if(uniqueCandidateCount>1)
        {
         reasonOut="ambiguous_exact_deal_match";
         return false;
        }

      ulong matchedDealId=uniqueCandidateDealIds[0];
      if(!PassesSafetySelectionEvidence(entry,matchedDealId,expectedComment,targetTicket,
                                        persistedBrokerOrderId,pendingCreatedAtAnchor))
        {
         reasonOut="safety_selection_failed";
         return false;
        }

      if(!HistoryDealSelect(matchedDealId))
        {
         reasonOut="deal_not_in_history";
         return false;
        }

      selectedOrderIdOut=(ulong)HistoryDealGetInteger(matchedDealId,DEAL_ORDER);
      selectedPositionIdOut=(ulong)HistoryDealGetInteger(matchedDealId,DEAL_POSITION_ID);
      evidenceOut.dealId=matchedDealId;
      evidenceOut.fillVolume=HistoryDealGetDouble(matchedDealId,DEAL_VOLUME);
      evidenceOut.comment=HistoryDealGetString(matchedDealId,DEAL_COMMENT);
      return true;
     }

   static bool       ForceRejectedToReconciling(IPendingExecutionStore *store,
                                                CPendingExecutionRegistry *registry,
                                                CPendingExecutionLifecycleService *lifecycle,
                                                CPendingExecutionEntry &entry,
                                                const SFalseRejectedHistoryEvidence &evidence)
     {
      if(registry==NULL || lifecycle==NULL)
         return false;

      ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus=entry.Status();
      if(fromStatus!=BRE_TRADE_EXEC_STATUS_REJECTED)
         return false;

      entry.SetStatus(BRE_TRADE_EXEC_STATUS_RECONCILING);
      entry.SetCorrelationState(BRE_PENDING_CORRELATION_RECONCILING);

      CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
      broker.SetBrokerDealId(evidence.dealId);
      entry.SetBrokerCorrelation(broker);

      registry.Upsert(entry);
      if(store!=NULL)
         store.SaveEntryState(entry);
      lifecycle.OnRegistryEntryUpdated(entry,fromStatus);
      return true;
     }

   static void       LogProfitCloseCompletionOutcome(const string executionRequestId,
                                                     IPendingExecutionFillNotifier *fillNotifier,
                                                     CManualProfitCloseCandidateRegistry *candidateRegistry)
     {
      if(fillNotifier==NULL)
        {
         Print("profit_close_completion_notifier_invoked=false");
         Print("profit_close_completion_result=NOT_ATTEMPTED");
         Print("profit_close_completion_reason=Fill notifier unavailable");
         return;
        }

      bool hasCandidate=false;
      if(candidateRegistry!=NULL)
        {
         CManualProfitCloseCandidateEntry candidateEntry;
         hasCandidate=candidateRegistry.TryGetByExecutionRequestId(executionRequestId,candidateEntry);
        }

      fillNotifier.OnBrokerFillConfirmed(executionRequestId,"startup");
      Print("profit_close_completion_notifier_invoked=true");

      if(candidateRegistry==NULL)
        {
         Print("profit_close_completion_result=NOT_ATTEMPTED");
         Print("profit_close_completion_reason=Candidate registry unavailable for completion probe");
         return;
        }

      if(!hasCandidate)
        {
         Print("profit_close_completion_result=CANDIDATE_NOT_FOUND");
         Print("profit_close_completion_reason=Candidate registry entry unavailable");
         return;
        }

      Print("profit_close_completion_result=COMPLETED");
      Print("profit_close_completion_reason=");
     }

   static bool       TryCompleteFilledProfitCloseFromPendingStartup(const CPendingExecutionEntry &entry,
                                                                    IBasketRepository *basketRepository,
                                                                    IClock *clock=NULL,
                                                                    IUniqueIdGenerator *idGenerator=NULL)
     {
      SProfitClosePersistedCompletionOutcome outcome;
      return CProfitCloseFilledPendingCompletionService::TryCompleteFilledProfitCloseFromPending(entry,
                                                                                                 basketRepository,
                                                                                                 outcome,
                                                                                                 clock,
                                                                                                 idGenerator,
                                                                                                 "startup_persisted_pending");
     }

   static bool       TryRecoverFalseRejectedEntry(IPendingExecutionStore *store,
                                                  CPendingExecutionRegistry *registry,
                                                  CPendingExecutionLifecycleService *lifecycle,
                                                  IPendingExecutionFillNotifier *fillNotifier,
                                                  CPendingExecutionEntry &entry,
                                                  CManualProfitCloseCandidateRegistry *candidateRegistry=NULL,
                                                  IBasketRepository *basketRepository=NULL,
                                                  IClock *clock=NULL,
                                                  IUniqueIdGenerator *idGenerator=NULL)
     {
      if(entry.Status()!=BRE_TRADE_EXEC_STATUS_REJECTED)
         return false;
      if(entry.IntentType()!=BRE_EXEC_INTENT_CLOSE_POSITION)
         return false;

      SFalseRejectedHistoryEvidence evidence;
      string reason="";
      ulong selectedOrderId=0;
      ulong selectedPositionId=0;
      if(!TryFindFalseRejectedHistoryEvidence(store,entry,evidence,reason,selectedOrderId,selectedPositionId))
        {
         LogFalseRejectedCandidateRejected(reason);
         return false;
        }

      LogFalseRejectedCandidateAccepted(entry,evidence,selectedOrderId,selectedPositionId);

      if(!ForceRejectedToReconciling(store,registry,lifecycle,entry,evidence))
         return false;

      if(!lifecycle.MarkFilled(entry.ExecutionRequestId(),evidence.fillVolume))
         return false;

      Print("pending_execution_transition=FILLED");
      Print("pending_execution_id=",entry.ExecutionRequestId());

      LogProfitCloseCompletionOutcome(entry.ExecutionRequestId(),fillNotifier,candidateRegistry);

      TryCompleteFilledProfitCloseFromPendingStartup(entry,basketRepository,clock,idGenerator);

      return true;
     }

   static bool       ApplyResolvedStatus(CPendingExecutionLifecycleService *lifecycle,
                                         IPendingExecutionFillNotifier *fillNotifier,
                                         CPendingExecutionEntry &entry,
                                         const ENUM_BRE_TRADE_EXECUTION_STATUS resolved,
                                         const double matchedVolume)
     {
      if(resolved==BRE_TRADE_EXEC_STATUS_FILLED)
        {
         ENUM_BRE_TRADE_EXECUTION_STATUS priorStatus=entry.Status();
         if(!lifecycle.MarkFilled(entry.ExecutionRequestId(),matchedVolume))
            return false;
         if(fillNotifier!=NULL && priorStatus!=BRE_TRADE_EXEC_STATUS_FILLED)
            fillNotifier.OnBrokerFillConfirmed(entry.ExecutionRequestId(),"startup");
         return true;
        }

      if(resolved==BRE_TRADE_EXEC_STATUS_REJECTED)
         return lifecycle.MarkRejected(entry.ExecutionRequestId());

      if(resolved==BRE_TRADE_EXEC_STATUS_TIMED_OUT)
         return lifecycle.MarkTimedOut(entry.ExecutionRequestId());

      if(resolved==BRE_TRADE_EXEC_STATUS_CANCELLED)
         return lifecycle.MarkCancelled(entry.ExecutionRequestId());

      if(resolved==BRE_TRADE_EXEC_STATUS_FAILED)
         return lifecycle.MarkFailed(entry.ExecutionRequestId());

      if(resolved==BRE_TRADE_EXEC_STATUS_RECONCILED)
         return lifecycle.MarkReconciled(entry.ExecutionRequestId());

      if(resolved==BRE_TRADE_EXEC_STATUS_UNKNOWN || resolved==BRE_TRADE_EXEC_STATUS_RECONCILING)
         return lifecycle.MarkUnknownReconciling(entry.ExecutionRequestId());

      if(resolved==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED)
        {
         ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus=entry.Status();
         entry.SetFilledVolume(matchedVolume);
         entry.SetStatus(BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED);
         lifecycle.OnRegistryEntryUpdated(entry,fromStatus);
         return true;
        }

      return false;
     }

   static bool       ReconcileEntry(CPendingExecutionLifecycleService *lifecycle,
                                    IBrokerPositionReader *positionReader,
                                    IBrokerExecutionHistoryReader *historyReader,
                                    IPendingExecutionFillNotifier *fillNotifier,
                                    CPendingExecutionEntry &entry,
                                    const datetime nowUtc)
     {
      if(lifecycle==NULL)
         return false;

      ENUM_BRE_TRADE_EXECUTION_STATUS status=entry.Status();
      if(CPendingExecutionQuery::IsTerminalStatus(status))
         return false;

      if(status==BRE_TRADE_EXEC_STATUS_QUEUED || status==BRE_TRADE_EXEC_STATUS_CREATED)
         return false;

      double matchedVolume=0.0;
      ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
         CExecutionReconciliationResolver::Resolve(entry,positionReader,matchedVolume,historyReader,nowUtc);

      return ApplyResolvedStatus(lifecycle,fillNotifier,entry,resolved,matchedVolume);
     }

public:
   static int        ReconcilePersistedEntries(IPendingExecutionStore *store,
                                               CPendingExecutionRegistry *registry,
                                               CPendingExecutionLifecycleService *lifecycle,
                                               IBrokerPositionReader *positionReader,
                                               IPendingExecutionFillNotifier *fillNotifier=NULL,
                                               IBrokerExecutionHistoryReader *historyReader=NULL,
                                               const datetime nowUtc=0,
                                               CManualProfitCloseCandidateRegistry *candidateRegistry=NULL,
                                               IBasketRepository *basketRepository=NULL,
                                               IClock *clock=NULL,
                                               IUniqueIdGenerator *idGenerator=NULL)
     {
      if(store==NULL || registry==NULL || lifecycle==NULL)
         return 0;

      Print("false_rejected_startup_reconcile_build_marker=",BRE_FALSE_REJECTED_STARTUP_RECONCILE_BUILD_MARKER);

      CPendingExecutionEntry entries[];
      int count=store.RestoreEntries(entries);
      int reconciled=0;
      datetime effectiveNow=(nowUtc>0 ? nowUtc : TimeCurrent());

      for(int i=0;i<count;i++)
        {
         CPendingExecutionReconciliationHydrator::TryHydrate(entries[i],store);
         registry.Upsert(entries[i]);

         if(entries[i].Status()==BRE_TRADE_EXEC_STATUS_REJECTED &&
            entries[i].IntentType()==BRE_EXEC_INTENT_CLOSE_POSITION)
           {
            if(TryRecoverFalseRejectedEntry(store,registry,lifecycle,fillNotifier,entries[i],
                                            candidateRegistry,basketRepository,clock,idGenerator))
              {
               reconciled++;
               continue;
              }
           }

         if(entries[i].Status()==BRE_TRADE_EXEC_STATUS_FILLED &&
            entries[i].IntentType()==BRE_EXEC_INTENT_CLOSE_POSITION)
           {
            if(TryCompleteFilledProfitCloseFromPendingStartup(entries[i],basketRepository,clock,idGenerator))
               reconciled++;
            continue;
           }

         if(ReconcileEntry(lifecycle,positionReader,historyReader,fillNotifier,entries[i],effectiveNow))
            reconciled++;
        }

      return reconciled;
     }
  };

#endif
