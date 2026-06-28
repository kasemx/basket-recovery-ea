#ifndef BRE_APP_EXECUTION_SUBMISSION_PREPARER_MQH
#define BRE_APP_EXECUTION_SUBMISSION_PREPARER_MQH

#include <BasketRecovery/Application/Execution/SubmissionPreparationPolicy.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionCommentCollisionDetector.mqh>
#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Ports/IMarketDataProvider.mqh>
#include <BasketRecovery/Application/Risk/BasketRiskReadModelService.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskValidationResult.mqh>
#include <BasketRecovery/Domain/Execution/BrokerCommentStamp.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRequestFingerprint.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionTransitionGate.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/SubmissionPreparationResult.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>

class CExecutionSubmissionPreparer
  {
private:
   CSubmissionPreparationPolicy   m_policy;
   CSubmissionPreparationValidator m_validator;
   CPendingExecutionRegistry     *m_registry;
   IPendingExecutionStore        *m_store;
   IClock                        *m_clock;
   IPositionSnapshotStore        *m_snapshotStore;
   IMarketDataProvider           *m_marketDataForRisk;
   CRiskValidationResult         m_lastReadOnlyRiskValidation;

   bool              IsEnvelopeReusable(const CBrokerSubmissionEnvelope &envelope,
                                        const CTradeExecutionRequest &request,
                                        const datetime nowUtc) const
     {
      if(envelope.IsExpired(nowUtc))
         return false;
      if(envelope.ExecutionRequestId()!=request.ExecutionRequestId())
         return false;
      if(envelope.IdempotencyKey()!=request.IdempotencyKey())
         return false;
      CExecutionRequestFingerprint current=CExecutionRequestFingerprint::Compute(request);
      return envelope.Fingerprint()==current;
     }

   CSubmissionPreparationResult FailEntry(CPendingExecutionEntry &entry,
                                          const ENUM_BRE_SUBMISSION_PREPARATION_FAILURE_REASON reason,
                                          const string message)
     {
      entry.IncrementPreparationAttemptCount();
      entry.SetLastPreparationFailureReason(reason);
      UpsertEntry(entry);
      return CSubmissionPreparationResult::Fail(reason,message);
     }

   void              UpsertEntry(CPendingExecutionEntry &entry)
     {
      if(m_registry==NULL)
         return;
      m_registry.Upsert(entry);
     }

   CBrokerSubmissionEnvelope BuildEnvelope(const CTradeExecutionRequest &request,
                                           const CBasketAggregate &basket,
                                           const CMarketQuote &quote,
                                           const long magicNumber,
                                           const string brokerComment,
                                           const string correlationToken,
                                           const CExecutionRequestFingerprint &fingerprint,
                                           const datetime nowUtc) const
     {
      CBrokerSubmissionEnvelope envelope;
      envelope.SetExecutionRequestId(request.ExecutionRequestId());
      envelope.SetIdempotencyKey(request.IdempotencyKey());
      envelope.SetBasketId(request.BasketId());
      envelope.SetExpectedBasketVersion((int)request.ExpectedBasketVersion());
      envelope.SetStrategyProfileHash(request.StrategyProfileHash());
      envelope.SetSymbol(request.Symbol());
      envelope.SetIntentType(request.IntentType());
      envelope.SetDirection(request.Direction());
      envelope.SetTicket(request.Ticket());
      envelope.SetRequestedVolume(request.RequestedVolume());
      envelope.SetRequestedPrice(request.RequestedPrice());
      envelope.SetRequestedStopLoss(request.RequestedStopLoss());
      envelope.SetRequestedTakeProfit(request.RequestedTakeProfit());
      envelope.SetMagicNumber(magicNumber);
      envelope.SetBrokerComment(brokerComment);
      envelope.SetCorrelationToken(correlationToken);
      envelope.SetFingerprint(fingerprint);
      envelope.SetQuoteTimestampUtc(quote.TimestampUtc());
      envelope.SetPreparedAtUtc(nowUtc);
      envelope.SetExpirationUtc(nowUtc+m_policy.EnvelopeValiditySeconds());
      return envelope;
     }

   void              ApplyPreparationMetadata(CPendingExecutionEntry &entry,
                                                const CBrokerSubmissionEnvelope &envelope,
                                                const CMarketQuote &quote)
     {
      entry.SetPreparedAtUtc(envelope.PreparedAtUtc());
      entry.SetPreparedQuoteTimestampUtc(envelope.QuoteTimestampUtc());
      entry.SetPreparedBid(quote.Bid());
      entry.SetPreparedAsk(quote.Ask());
      entry.SetBrokerComment(envelope.BrokerComment());
      entry.SetCorrelationToken(envelope.CorrelationToken());
      entry.SetRequestFingerprint(envelope.Fingerprint().Value());
      entry.SetDeadlineUtc(envelope.ExpirationUtc());

      CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
      broker.SetMagicNumber(envelope.MagicNumber());
      broker.SetSymbol(envelope.Symbol());
      broker.SetCommentToken(envelope.CorrelationToken());
      broker.SetRequestFingerprint(envelope.Fingerprint().Value());
      entry.SetBrokerCorrelation(broker);
     }

   void              EvaluateRiskReadOnly(const CTradeExecutionRequest &request,
                                          const CBasketAggregate &basket,
                                          const CMarketQuote &quote)
     {
      if(m_snapshotStore==NULL || m_marketDataForRisk==NULL)
         return;

      CResult<CAccountContextSnapshot> accountResult=m_marketDataForRisk.TryGetAccountSnapshot();
      if(accountResult.IsFail())
         return;

      CAccountContextSnapshot account;
      accountResult.TryGetValue(account);
      m_lastReadOnlyRiskValidation=CBasketRiskReadModelService::TryValidateProposedPositionReadOnly(
         basket,request,quote,account,m_snapshotStore,CRiskCalculationSettings::CreateDefault());
     }

public:
                     CExecutionSubmissionPreparer(const CSubmissionPreparationPolicy &policy,
                                                  CSubmissionPreparationValidator &validator,
                                                  CPendingExecutionRegistry *registry,
                                                  IPendingExecutionStore *store,
                                                  IClock *clock)
     {
      m_policy=policy;
      m_validator=validator;
      m_registry=registry;
      m_store=store;
      m_clock=clock;
      m_snapshotStore=NULL;
      m_marketDataForRisk=NULL;
     }

   void              ConfigureRiskReadModel(IPositionSnapshotStore *snapshotStore,
                                            IMarketDataProvider *marketDataProvider)
     {
      m_snapshotStore=snapshotStore;
      m_marketDataForRisk=marketDataProvider;
     }

   CRiskValidationResult LastReadOnlyRiskValidation(void) const { return m_lastReadOnlyRiskValidation; }

   CSubmissionPreparationResult Prepare(const CTradeExecutionRequest &request,
                                        const CBasketAggregate &basket,
                                        const long magicNumber)
     {
      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : TimeCurrent();

      ENUM_BRE_SUBMISSION_PREPARATION_FAILURE_REASON failureReason=BRE_PREP_FAIL_NONE;
      string failureMessage="";
      if(!m_validator.ValidateSealedRequest(request,failureReason,failureMessage))
         return CSubmissionPreparationResult::Fail(failureReason,failureMessage);

      if(m_store!=NULL)
        {
         CResult<CBrokerSubmissionEnvelope> cached=m_store.FindEnvelopeByIdempotencyKey(request.IdempotencyKey());
         if(cached.IsOk())
           {
            CBrokerSubmissionEnvelope envelope;
            cached.TryGetValue(envelope);
            if(IsEnvelopeReusable(envelope,request,nowUtc))
               return CSubmissionPreparationResult::Ok(envelope,true);
           }
        }

      CMarketQuote quote;
      if(!m_validator.ValidateRequestContext(request,basket,quote,failureReason,failureMessage))
        {
         CPendingExecutionEntry rejectedEntry;
         rejectedEntry.SetExecutionRequestId(request.ExecutionRequestId());
         rejectedEntry.SetIdempotencyKey(request.IdempotencyKey());
         return FailEntry(rejectedEntry,failureReason,failureMessage);
        }

      if(quote.FreshnessAgeMs()>m_policy.QuoteFreshnessMs())
        {
         CPendingExecutionEntry rejectedEntry;
         rejectedEntry.SetExecutionRequestId(request.ExecutionRequestId());
         rejectedEntry.SetIdempotencyKey(request.IdempotencyKey());
         return FailEntry(rejectedEntry,BRE_PREP_FAIL_STALE_QUOTE,"Quote freshness expired for preparation");
        }

      CExecutionRequestFingerprint fingerprint=CExecutionRequestFingerprint::Compute(request);
      string brokerComment=CBrokerCommentStamp::Build(request.ExecutionRequestId(),
                                                      request.IdempotencyKey(),
                                                      request.BasketId(),
                                                      request.IntentType(),
                                                      m_policy.MaxCommentLength());
      string correlationToken=CBrokerCommentStamp::ExtractCorrelationToken(brokerComment);

      CPendingExecutionEntry entry;
      if(m_registry!=NULL && m_registry.TryGetByExecutionRequestId(request.ExecutionRequestId(),entry))
        {
         if(!CBrokerSubmissionTransitionGate::PreparationMaySetStatus(entry.Status()))
           {
            return CSubmissionPreparationResult::Fail(BRE_PREP_FAIL_VALIDATION,"Pending entry status does not allow preparation");
           }
        }
      else
        {
         entry=CPendingExecutionEntry();
         entry.SetExecutionRequestId(request.ExecutionRequestId());
         entry.SetIdempotencyKey(request.IdempotencyKey());
         entry.SetBasketId(request.BasketId());
         entry.SetExpectedBasketVersion((int)request.ExpectedBasketVersion());
         entry.SetStrategyProfileHash(request.StrategyProfileHash());
         entry.SetIntentType(request.IntentType());
         entry.SetSymbol(request.Symbol());
         entry.SetRequestedVolume(request.RequestedVolume());
         entry.SetCreatedAtUtc(nowUtc);
         entry.SetStatus(BRE_TRADE_EXEC_STATUS_CREATED);
        }

      if(m_registry!=NULL)
        {
         if(CPendingExecutionCommentCollisionDetector::HasActiveCommentCollision(*m_registry,brokerComment,request.ExecutionRequestId()))
            return FailEntry(entry,BRE_PREP_FAIL_COMMENT_COLLISION,"Broker comment collision detected");
         if(CPendingExecutionCommentCollisionDetector::HasActiveCorrelationCollision(*m_registry,correlationToken,request.ExecutionRequestId()))
            return FailEntry(entry,BRE_PREP_FAIL_CORRELATION_COLLISION,"Correlation token collision detected");
        }

      if(entry.Status()==BRE_TRADE_EXEC_STATUS_CREATED)
         entry.SetStatus(BRE_TRADE_EXEC_STATUS_QUEUED);

      CBrokerSubmissionEnvelope envelope=BuildEnvelope(request,basket,quote,magicNumber,brokerComment,
                                                         correlationToken,fingerprint,nowUtc);
      entry.IncrementPreparationAttemptCount();
      entry.SetLastPreparationFailureReason(BRE_PREP_FAIL_NONE);
      ApplyPreparationMetadata(entry,envelope,quote);
      EvaluateRiskReadOnly(request,basket,quote);

      UpsertEntry(entry);
      if(m_store!=NULL)
         m_store.SavePreparedState(entry,envelope);

      return CSubmissionPreparationResult::Ok(envelope,false);
     }

   CSubmissionPreparationResult PrepareForValidationSeed(const CTradeExecutionRequest &request,
                                                         const CBasketAggregate &basket,
                                                         const long magicNumber)
     {
      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : TimeCurrent();

      ENUM_BRE_SUBMISSION_PREPARATION_FAILURE_REASON failureReason=BRE_PREP_FAIL_NONE;
      string failureMessage="";
      if(!m_validator.ValidateSealedRequest(request,failureReason,failureMessage))
         return CSubmissionPreparationResult::Fail(failureReason,failureMessage);

      CMarketQuote quote;
      if(!m_validator.ValidateRequestContextForValidationSeed(request,basket,quote,failureReason,failureMessage))
        {
         CPendingExecutionEntry rejectedEntry;
         rejectedEntry.SetExecutionRequestId(request.ExecutionRequestId());
         rejectedEntry.SetIdempotencyKey(request.IdempotencyKey());
         return FailEntry(rejectedEntry,failureReason,failureMessage);
        }

      if(quote.FreshnessAgeMs()>m_policy.QuoteFreshnessMs())
        {
         CPendingExecutionEntry rejectedEntry;
         rejectedEntry.SetExecutionRequestId(request.ExecutionRequestId());
         rejectedEntry.SetIdempotencyKey(request.IdempotencyKey());
         return FailEntry(rejectedEntry,BRE_PREP_FAIL_STALE_QUOTE,"Quote freshness expired for preparation");
        }

      CExecutionRequestFingerprint fingerprint=CExecutionRequestFingerprint::Compute(request);
      string brokerComment=CBrokerCommentStamp::Build(request.ExecutionRequestId(),
                                                      request.IdempotencyKey(),
                                                      request.BasketId(),
                                                      request.IntentType(),
                                                      m_policy.MaxCommentLength());
      string correlationToken=CBrokerCommentStamp::ExtractCorrelationToken(brokerComment);

      CPendingExecutionEntry entry;
      if(m_registry!=NULL && m_registry.TryGetByExecutionRequestId(request.ExecutionRequestId(),entry))
        {
         if(!CBrokerSubmissionTransitionGate::PreparationMaySetStatus(entry.Status()))
           {
            return CSubmissionPreparationResult::Fail(BRE_PREP_FAIL_VALIDATION,"Pending entry status does not allow preparation");
           }
        }
      else
        {
         entry=CPendingExecutionEntry();
         entry.SetExecutionRequestId(request.ExecutionRequestId());
         entry.SetIdempotencyKey(request.IdempotencyKey());
         entry.SetBasketId(request.BasketId());
         entry.SetExpectedBasketVersion((int)request.ExpectedBasketVersion());
         entry.SetStrategyProfileHash(request.StrategyProfileHash());
         entry.SetIntentType(request.IntentType());
         entry.SetSymbol(request.Symbol());
         entry.SetRequestedVolume(request.RequestedVolume());
         entry.SetCreatedAtUtc(nowUtc);
         entry.SetStatus(BRE_TRADE_EXEC_STATUS_CREATED);
        }

      if(m_registry!=NULL)
        {
         if(CPendingExecutionCommentCollisionDetector::HasActiveCommentCollision(*m_registry,brokerComment,request.ExecutionRequestId()))
            return FailEntry(entry,BRE_PREP_FAIL_COMMENT_COLLISION,"Broker comment collision detected");
         if(CPendingExecutionCommentCollisionDetector::HasActiveCorrelationCollision(*m_registry,correlationToken,request.ExecutionRequestId()))
            return FailEntry(entry,BRE_PREP_FAIL_CORRELATION_COLLISION,"Correlation token collision detected");
        }

      if(entry.Status()==BRE_TRADE_EXEC_STATUS_CREATED)
         entry.SetStatus(BRE_TRADE_EXEC_STATUS_QUEUED);

      CBrokerSubmissionEnvelope envelope=BuildEnvelope(request,basket,quote,magicNumber,brokerComment,
                                                         correlationToken,fingerprint,nowUtc);
      entry.IncrementPreparationAttemptCount();
      entry.SetLastPreparationFailureReason(BRE_PREP_FAIL_NONE);
      ApplyPreparationMetadata(entry,envelope,quote);
      EvaluateRiskReadOnly(request,basket,quote);

      UpsertEntry(entry);
      if(m_store!=NULL)
         m_store.SavePreparedState(entry,envelope);

      return CSubmissionPreparationResult::Ok(envelope,false);
     }
  };

#endif
