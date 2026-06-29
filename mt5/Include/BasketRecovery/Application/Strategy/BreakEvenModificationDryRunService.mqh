#ifndef BRE_APP_BREAK_EVEN_MODIFICATION_DRY_RUN_SERVICE_MQH
#define BRE_APP_BREAK_EVEN_MODIFICATION_DRY_RUN_SERVICE_MQH

#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Application/Strategy/BreakEvenModificationEventBuffer.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenCandidate.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenModificationAudit.mqh>
#include <BasketRecovery/Domain/Strategy/Services/BreakEvenStopPriceValidator.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>

class CBreakEvenModificationDryRunService
  {
private:
   IPositionSnapshotStore               *m_snapshotStore;
   CPendingExecutionRegistry            *m_pendingRegistry;
   CBreakEvenModificationEventBuffer    *m_eventBuffer;
   int                                   m_quoteStaleThresholdMs;
   bool                                  m_enabled;

   string            BuildModificationIdempotencyKey(const CBasketId &basketId,
                                                     const string ruleId,
                                                     const ulong quoteSequence) const
     {
      return "break-even-modification:"+basketId.Value()+":rule:"+ruleId+":q:"+IntegerToString((long)quoteSequence);
     }

   string            BuildExecutionRequestId(const CBasketId &basketId,
                                             const string ruleId,
                                             const ulong quoteSequence) const
     {
      return "be-modify:"+basketId.Value()+":"+ruleId+":"+IntegerToString((long)quoteSequence);
     }

   bool              IsNoChangeRequired(const ENUM_BRE_TRADE_DIRECTION direction,
                                        const double currentStopLoss,
                                        const double proposedStopLoss) const
     {
      if(currentStopLoss<=0.0)
         return false;
      if(direction==BRE_DIRECTION_BUY)
         return currentStopLoss>=proposedStopLoss;
      if(direction==BRE_DIRECTION_SELL)
         return currentStopLoss<=proposedStopLoss;
      return false;
     }

   ENUM_BRE_EVENT_TYPE ResolveEventType(const CBreakEvenStopLossModificationRequest &request) const
     {
      switch(request.Status())
        {
         case BRE_BREAK_EVEN_MOD_REQ_DRY_RUN_READY:
            return BRE_EVENT_BREAK_EVEN_MODIFICATION_DRY_RUN_READY;
         case BRE_BREAK_EVEN_MOD_REQ_NO_CHANGE_REQUIRED:
            return BRE_EVENT_BREAK_EVEN_MODIFICATION_NO_CHANGE;
         case BRE_BREAK_EVEN_MOD_REQ_INVALID:
            return BRE_EVENT_BREAK_EVEN_MODIFICATION_INVALID;
         case BRE_BREAK_EVEN_MOD_REQ_BLOCKED:
            return BRE_EVENT_BREAK_EVEN_MODIFICATION_BLOCKED;
         default:
            return BRE_EVENT_BREAK_EVEN_MODIFICATION_BLOCKED;
        }
     }

   void              Emit(const CBasketAggregate &basket,
                          const CBreakEvenModificationAudit &audit,
                          const CRecoveryRiskGateInput &gateInput) const
     {
      if(m_eventBuffer==NULL)
         return;

      CBreakEvenStopLossModificationRequest request=audit.Request();
      if(request.Status()==BRE_BREAK_EVEN_MOD_REQ_NONE)
         return;

      ENUM_BRE_EVENT_TYPE eventType=ResolveEventType(request);
      CBreakEvenModificationDomainEvent event=CBreakEvenModificationDomainEvent::Create(eventType,
                                                                                        basket.Id(),
                                                                                        gateInput.CorrelationKey(),
                                                                                        request.CreatedUtc(),
                                                                                        audit,
                                                                                        request.QuoteSequence());
      m_eventBuffer.TryEmit(event);
     }

   CBreakEvenStopLossModificationRequest BuildFailedRequest(const CBasketAggregate &basket,
                                                            const CBreakEvenCandidate &candidate,
                                                            const CRecoveryRiskGateInput &gateInput,
                                                            const string idempotencyKey,
                                                            const ENUM_BRE_BREAK_EVEN_MODIFICATION_REQUEST_STATUS status,
                                                            const ENUM_BRE_BREAK_EVEN_MODIFICATION_FAILURE_REASON reason) const
     {
      ulong tickets[];
      double priorStops[];
      ENUM_BRE_BREAK_EVEN_TICKET_MODIFICATION_STATUS ticketStates[];
      ArrayResize(tickets,0);
      ArrayResize(priorStops,0);
      ArrayResize(ticketStates,0);

      CBreakEvenCandidateAudit candidateAudit=candidate.Audit();
      return CBreakEvenStopLossModificationRequest::Create(BuildExecutionRequestId(basket.Id(),
                                                                                candidateAudit.RuleId(),
                                                                                candidateAudit.QuoteSequence()),
                                                           basket.Id(),
                                                           basket.StrategyProfileHash(),
                                                           basket.Version(),
                                                           candidateAudit.QuoteSequence(),
                                                           gateInput.CorrelationKey(),
                                                           idempotencyKey,
                                                           basket.Symbol(),
                                                           basket.Direction(),
                                                           tickets,
                                                           priorStops,
                                                           ticketStates,
                                                           candidateAudit.ProposedStopLoss(),
                                                           candidateAudit.WeightedAverageEntry(),
                                                           candidateAudit.TotalActiveVolume(),
                                                           candidateAudit.RuleId(),
                                                           candidateAudit.TriggerType(),
                                                           candidateAudit.TriggerValue(),
                                                           candidateAudit.PriceCalculation().SpreadComponent(),
                                                           candidateAudit.PriceCalculation().SafetyBufferComponent(),
                                                           candidateAudit.RecoveryDisableRecommended(),
                                                           candidateAudit.LockRecommended(),
                                                           gateInput.TimestampUtc(),
                                                           true,
                                                           candidate.IdempotencyKey(),
                                                           status,
                                                           reason);
     }

   CBreakEvenStopLossModificationRequest BuildAndEmitFailed(const CBasketAggregate &basket,
                                                            const CBreakEvenCandidate &candidate,
                                                            const CRecoveryRiskGateInput &gateInput,
                                                            const string idempotencyKey,
                                                            const ENUM_BRE_BREAK_EVEN_MODIFICATION_REQUEST_STATUS status,
                                                            const ENUM_BRE_BREAK_EVEN_MODIFICATION_FAILURE_REASON reason,
                                                            const bool lifecycleActive,
                                                            const bool candidateDue,
                                                            const bool breakEvenInactive,
                                                            const bool quoteSequenceMatched,
                                                            const bool quoteFresh,
                                                            const bool noPendingExecution,
                                                            const bool profileBindingMatched,
                                                            const bool snapshotConsistent,
                                                            const bool stopValidationPassed,
                                                            const bool idempotencyPassed,
                                                            const bool dryRunAuthorized,
                                                            const bool accountEligible,
                                                            const bool allOrNothingSatisfied)
     {
      CBreakEvenStopLossModificationRequest failed=BuildFailedRequest(basket,candidate,gateInput,idempotencyKey,status,reason);
      CBreakEvenModificationAudit audit=CBreakEvenModificationAudit::Create(failed,
                                                                            lifecycleActive,candidateDue,breakEvenInactive,
                                                                            quoteSequenceMatched,quoteFresh,noPendingExecution,
                                                                            profileBindingMatched,snapshotConsistent,
                                                                            stopValidationPassed,idempotencyPassed,
                                                                            dryRunAuthorized,accountEligible,
                                                                            allOrNothingSatisfied);
      Emit(basket,audit,gateInput);
      return failed;
     }

public:
                     CBreakEvenModificationDryRunService(IPositionSnapshotStore *snapshotStore,
                                                         CPendingExecutionRegistry *pendingRegistry,
                                                         CBreakEvenModificationEventBuffer *eventBuffer,
                                                         const int quoteStaleThresholdMs=5000,
                                                         const bool enabled=false)
     {
      m_snapshotStore=snapshotStore;
      m_pendingRegistry=pendingRegistry;
      m_eventBuffer=eventBuffer;
      m_quoteStaleThresholdMs=quoteStaleThresholdMs;
      m_enabled=enabled;
     }

   void              SetEnabled(const bool enabled) { m_enabled=enabled; }
   bool              Enabled(void) const { return m_enabled; }

   CBreakEvenStopLossModificationRequest EvaluateDryRun(const CBasketAggregate &basket,
                                                        const CBreakEvenCandidate &candidate,
                                                        const CRecoveryRiskGateInput &gateInput)
     {
      string ruleId=candidate.RuleId();
      ulong quoteSequence=candidate.Audit().QuoteSequence();
      string idempotencyKey=BuildModificationIdempotencyKey(basket.Id(),ruleId,quoteSequence);

      bool lifecycleActive=(basket.LifecycleState()==BRE_STATE_ACTIVE);
      bool candidateDue=candidate.Status()==BRE_BREAK_EVEN_CANDIDATE_DUE;
      bool breakEvenInactive=!basket.ModeFlags().BreakEvenActive();
      bool quoteSequenceMatched=gateInput.HasQuote() && gateInput.QuoteSequence()==quoteSequence;
      int staleThreshold=gateInput.HasQuote() ? gateInput.QuoteStaleThresholdMs() : m_quoteStaleThresholdMs;
      bool quoteFresh=gateInput.HasQuote() &&
                      (staleThreshold<=0 || gateInput.Quote().FreshnessAgeMs()<=staleThreshold);
      bool noPendingExecution=!(m_pendingRegistry!=NULL &&
                                CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(*m_pendingRegistry,basket.Id()));
      bool profileBindingMatched=(candidate.Audit().StrategyProfileHash()==basket.StrategyProfileHash());
      bool versionMatched=(candidate.Audit().BasketVersion()==basket.Version());
      bool idempotencyPassed=!(m_eventBuffer!=NULL && m_eventBuffer.HasSeenIdempotencyKey(idempotencyKey));
      bool dryRunAuthorized=m_enabled;
      bool accountEligible=gateInput.HasQuote() && gateInput.Quote().Symbol()==basket.Symbol();

      if(!dryRunAuthorized)
         return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                   BRE_BREAK_EVEN_MOD_REQ_BLOCKED,
                                   BRE_BREAK_EVEN_MOD_FAIL_DRY_RUN_DISABLED,
                                   lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                   noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                   idempotencyPassed,dryRunAuthorized,accountEligible,false);

      if(!candidateDue)
         return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                   BRE_BREAK_EVEN_MOD_REQ_INVALID,BRE_BREAK_EVEN_MOD_FAIL_CANDIDATE_NOT_DUE,
                                   lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                   noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                   idempotencyPassed,dryRunAuthorized,accountEligible,false);
      if(!lifecycleActive)
         return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                   BRE_BREAK_EVEN_MOD_REQ_BLOCKED,BRE_BREAK_EVEN_MOD_FAIL_BASKET_NOT_ACTIVE,
                                   lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                   noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                   idempotencyPassed,dryRunAuthorized,accountEligible,false);
      if(!breakEvenInactive)
         return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                   BRE_BREAK_EVEN_MOD_REQ_BLOCKED,BRE_BREAK_EVEN_MOD_FAIL_BREAK_EVEN_ALREADY_ACTIVE,
                                   lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                   noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                   idempotencyPassed,dryRunAuthorized,accountEligible,false);
      if(!quoteSequenceMatched)
         return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                   BRE_BREAK_EVEN_MOD_REQ_BLOCKED,BRE_BREAK_EVEN_MOD_FAIL_QUOTE_SEQUENCE_MISMATCH,
                                   lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                   noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                   idempotencyPassed,dryRunAuthorized,accountEligible,false);
      if(!quoteFresh)
         return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                   BRE_BREAK_EVEN_MOD_REQ_BLOCKED,BRE_BREAK_EVEN_MOD_FAIL_STALE_QUOTE,
                                   lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                   noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                   idempotencyPassed,dryRunAuthorized,accountEligible,false);
      if(!noPendingExecution)
         return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                   BRE_BREAK_EVEN_MOD_REQ_BLOCKED,BRE_BREAK_EVEN_MOD_FAIL_PENDING_EXECUTION,
                                   lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                   noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                   idempotencyPassed,dryRunAuthorized,accountEligible,false);
      if(!profileBindingMatched)
         return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                   BRE_BREAK_EVEN_MOD_REQ_INVALID,BRE_BREAK_EVEN_MOD_FAIL_PROFILE_HASH_MISMATCH,
                                   lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                   noPendingExecution,false,false,false,
                                   idempotencyPassed,dryRunAuthorized,accountEligible,false);
      if(!versionMatched)
         return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                   BRE_BREAK_EVEN_MOD_REQ_INVALID,BRE_BREAK_EVEN_MOD_FAIL_BASKET_VERSION_MISMATCH,
                                   lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                   noPendingExecution,false,false,false,
                                   idempotencyPassed,dryRunAuthorized,accountEligible,false);
      if(!idempotencyPassed)
        {
         CBreakEvenStopLossModificationRequest duplicate;
         return duplicate;
        }
      if(!accountEligible)
         return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                   BRE_BREAK_EVEN_MOD_REQ_BLOCKED,BRE_BREAK_EVEN_MOD_FAIL_ACCOUNT_NOT_ELIGIBLE,
                                   lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                   noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                   idempotencyPassed,dryRunAuthorized,accountEligible,false);

      CPositionSnapshot *snapshot=m_snapshotStore!=NULL ? m_snapshotStore.Get(basket.Id()) : NULL;
      if(snapshot==NULL || snapshot.EntryCount()<=0)
         return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                   BRE_BREAK_EVEN_MOD_REQ_INVALID,BRE_BREAK_EVEN_MOD_FAIL_EMPTY_TICKET_SNAPSHOT,
                                   lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                   noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                   idempotencyPassed,dryRunAuthorized,accountEligible,false);

      ulong tickets[];
      double priorStops[];
      ENUM_BRE_BREAK_EVEN_TICKET_MODIFICATION_STATUS ticketStates[];
      int count=0;
      ArrayResize(tickets,0);
      ArrayResize(priorStops,0);
      ArrayResize(ticketStates,0);

      for(int i=0;i<snapshot.EntryCount();i++)
        {
         CPositionSnapshotEntry entry;
         if(!snapshot.EntryAt(i,entry))
            continue;
         if(entry.Status()!=BRE_POSITION_SNAPSHOT_OPEN)
            continue;
         if(entry.BasketId().Value()!=basket.Id().Value())
            return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                      BRE_BREAK_EVEN_MOD_REQ_INVALID,BRE_BREAK_EVEN_MOD_FAIL_MISSING_TICKET,
                                      lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                      noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                      idempotencyPassed,dryRunAuthorized,accountEligible,false);
         if(entry.Symbol()!=basket.Symbol())
            return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                      BRE_BREAK_EVEN_MOD_REQ_INVALID,BRE_BREAK_EVEN_MOD_FAIL_SYMBOL_MISMATCH,
                                      lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                      noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                      idempotencyPassed,dryRunAuthorized,accountEligible,false);
         if(entry.Direction()!=basket.Direction())
            return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                      BRE_BREAK_EVEN_MOD_REQ_INVALID,BRE_BREAK_EVEN_MOD_FAIL_DIRECTION_MISMATCH,
                                      lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                      noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                      idempotencyPassed,dryRunAuthorized,accountEligible,false);
         if(entry.Ticket()==0 || entry.Volume()<=0.0)
            return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                      BRE_BREAK_EVEN_MOD_REQ_INVALID,BRE_BREAK_EVEN_MOD_FAIL_UNSAFE_TICKET,
                                      lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                      noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                      idempotencyPassed,dryRunAuthorized,accountEligible,false);

         for(int d=0;d<count;d++)
           {
            if(tickets[d]==entry.Ticket())
               return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                         BRE_BREAK_EVEN_MOD_REQ_INVALID,BRE_BREAK_EVEN_MOD_FAIL_DUPLICATE_TICKET,
                                         lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                         noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                         idempotencyPassed,dryRunAuthorized,accountEligible,false);
           }

         ArrayResize(tickets,count+1);
         ArrayResize(priorStops,count+1);
         ArrayResize(ticketStates,count+1);
         tickets[count]=entry.Ticket();
         priorStops[count]=entry.StopLoss();
         ticketStates[count]=IsNoChangeRequired(basket.Direction(),entry.StopLoss(),candidate.Audit().ProposedStopLoss())
                             ? BRE_BREAK_EVEN_TICKET_MOD_NO_CHANGE_REQUIRED
                             : BRE_BREAK_EVEN_TICKET_MOD_APPLY_REQUIRED;
         count++;
        }

      if(count<=0)
         return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                   BRE_BREAK_EVEN_MOD_REQ_INVALID,BRE_BREAK_EVEN_MOD_FAIL_EMPTY_TICKET_SNAPSHOT,
                                   lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                   noPendingExecution,profileBindingMatched && versionMatched,false,false,
                                   idempotencyPassed,dryRunAuthorized,accountEligible,false);

      CBreakEvenStopPriceValidation stopValidation=CBreakEvenStopPriceValidator::Validate(basket.Direction(),
                                                                                          basket.Direction()==BRE_DIRECTION_BUY ? gateInput.Quote().Bid() : gateInput.Quote().Ask(),
                                                                                          candidate.Audit().ProposedStopLoss(),
                                                                                          gateInput.Quote().Point(),
                                                                                          gateInput.Quote().Constraints());
      if(!stopValidation.Valid())
         return BuildAndEmitFailed(basket,candidate,gateInput,idempotencyKey,
                                   BRE_BREAK_EVEN_MOD_REQ_INVALID,BRE_BREAK_EVEN_MOD_FAIL_INVALID_STOP_PRICE,
                                   lifecycleActive,candidateDue,breakEvenInactive,quoteSequenceMatched,quoteFresh,
                                   noPendingExecution,profileBindingMatched && versionMatched,true,false,
                                   idempotencyPassed,dryRunAuthorized,accountEligible,false);

      ENUM_BRE_BREAK_EVEN_MODIFICATION_REQUEST_STATUS finalStatus=BRE_BREAK_EVEN_MOD_REQ_DRY_RUN_READY;
      if(count>0)
        {
         int noChangeCount=0;
         for(int c=0;c<count;c++)
           {
            if(ticketStates[c]==BRE_BREAK_EVEN_TICKET_MOD_NO_CHANGE_REQUIRED)
               noChangeCount++;
           }
         if(noChangeCount==count)
            finalStatus=BRE_BREAK_EVEN_MOD_REQ_NO_CHANGE_REQUIRED;
        }

      CBreakEvenCandidateAudit candidateAudit=candidate.Audit();
      CBreakEvenStopLossModificationRequest request=
         CBreakEvenStopLossModificationRequest::Create(BuildExecutionRequestId(basket.Id(),
                                                                               candidateAudit.RuleId(),
                                                                               candidateAudit.QuoteSequence()),
                                                       basket.Id(),
                                                       basket.StrategyProfileHash(),
                                                       basket.Version(),
                                                       candidateAudit.QuoteSequence(),
                                                       gateInput.CorrelationKey(),
                                                       idempotencyKey,
                                                       basket.Symbol(),
                                                       basket.Direction(),
                                                       tickets,
                                                       priorStops,
                                                       ticketStates,
                                                       candidateAudit.ProposedStopLoss(),
                                                       candidateAudit.WeightedAverageEntry(),
                                                       candidateAudit.TotalActiveVolume(),
                                                       candidateAudit.RuleId(),
                                                       candidateAudit.TriggerType(),
                                                       candidateAudit.TriggerValue(),
                                                       candidateAudit.PriceCalculation().SpreadComponent(),
                                                       candidateAudit.PriceCalculation().SafetyBufferComponent(),
                                                       candidateAudit.RecoveryDisableRecommended(),
                                                       candidateAudit.LockRecommended(),
                                                       gateInput.TimestampUtc(),
                                                       true,
                                                       candidate.IdempotencyKey(),
                                                       finalStatus,
                                                       BRE_BREAK_EVEN_MOD_FAIL_NONE);

      CBreakEvenModificationAudit audit=CBreakEvenModificationAudit::Create(request,
                                                                            lifecycleActive,candidateDue,breakEvenInactive,
                                                                            quoteSequenceMatched,quoteFresh,noPendingExecution,
                                                                            profileBindingMatched && versionMatched,true,true,
                                                                            idempotencyPassed,dryRunAuthorized,accountEligible,true);
      Emit(basket,audit,gateInput);
      return request;
     }
  };

#endif
