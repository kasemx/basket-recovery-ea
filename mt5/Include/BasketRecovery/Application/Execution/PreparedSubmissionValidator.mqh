#ifndef BRE_APP_PREPARED_SUBMISSION_VALIDATOR_MQH
#define BRE_APP_PREPARED_SUBMISSION_VALIDATOR_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionTransitionRules.mqh>
#include <BasketRecovery/Domain/Execution/PreparedSubmissionFailureReason.mqh>

class CPreparedSubmissionValidator
  {
private:
   CPendingExecutionRegistry *m_registry;
   IPendingExecutionStore    *m_store;
   IClock                    *m_clock;

public:
                     CPreparedSubmissionValidator(CPendingExecutionRegistry *registry,
                                                  IPendingExecutionStore *store,
                                                  IClock *clock)
     {
      m_registry=registry;
      m_store=store;
      m_clock=clock;
     }

   bool              Validate(const string executionRequestId,
                              CPendingExecutionEntry &entry,
                              CBrokerSubmissionEnvelope &envelope,
                              ENUM_BRE_PREPARED_SUBMISSION_FAILURE_REASON &failureReason,
                              string &failureMessage) const
     {
      failureReason=BRE_SUBMIT_FAIL_NONE;
      failureMessage="";

      if(m_registry==NULL || !m_registry.TryGetByExecutionRequestId(executionRequestId,entry))
        {
         failureReason=BRE_SUBMIT_FAIL_NOT_FOUND;
         failureMessage="Pending execution entry not found";
         return false;
        }

      if(entry.Status()!=BRE_TRADE_EXEC_STATUS_QUEUED)
        {
         failureReason=BRE_SUBMIT_FAIL_NOT_QUEUED;
         failureMessage="Entry must be QUEUED before submission";
         return false;
        }

      if(!entry.IsPreparedQueued())
        {
         failureReason=BRE_SUBMIT_FAIL_NOT_PREPARED;
         failureMessage="Prepared envelope metadata is missing";
         return false;
        }

      if(CPendingExecutionTransitionRules::BlocksBlindResend(entry.Status()) ||
         CPendingExecutionTransitionRules::IsTerminal(entry.Status()))
        {
         failureReason=BRE_SUBMIT_FAIL_BLOCKED_STATE;
         failureMessage="Entry is in a blocked or terminal state";
         return false;
        }

      if(m_store==NULL)
        {
         failureReason=BRE_SUBMIT_FAIL_VALIDATION;
         failureMessage="Pending execution store is not configured";
         return false;
        }

      CResult<CBrokerSubmissionEnvelope> envelopeResult=
         m_store.FindEnvelopeByIdempotencyKey(entry.IdempotencyKey());
      if(!envelopeResult.IsOk())
        {
         failureReason=BRE_SUBMIT_FAIL_ENVELOPE_MISMATCH;
         failureMessage="Prepared envelope not found in store";
         return false;
        }
      envelopeResult.TryGetValue(envelope);

      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : TimeCurrent();
      if(envelope.IsExpired(nowUtc))
        {
         failureReason=BRE_SUBMIT_FAIL_ENVELOPE_EXPIRED;
         failureMessage="Prepared envelope has expired";
         return false;
        }

      if(envelope.ExecutionRequestId()!=entry.ExecutionRequestId() ||
         envelope.IdempotencyKey()!=entry.IdempotencyKey() ||
         envelope.BrokerComment()!=entry.BrokerComment() ||
         envelope.CorrelationToken()!=entry.CorrelationToken() ||
         envelope.Fingerprint().Value()!=entry.RequestFingerprint())
        {
         failureReason=BRE_SUBMIT_FAIL_ENVELOPE_MISMATCH;
         failureMessage="Stored envelope does not match pending entry metadata";
         return false;
        }

      return true;
     }

   bool              BlocksResubmission(const CPendingExecutionEntry &entry,
                                        ENUM_BRE_PREPARED_SUBMISSION_FAILURE_REASON &failureReason,
                                        string &failureMessage) const
     {
      failureReason=BRE_SUBMIT_FAIL_NONE;
      failureMessage="";

      if(entry.Status()==BRE_TRADE_EXEC_STATUS_SUBMITTED ||
         entry.Status()==BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED ||
         entry.Status()==BRE_TRADE_EXEC_STATUS_ACCEPTED ||
         entry.Status()==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED)
        {
         failureReason=BRE_SUBMIT_FAIL_ALREADY_SUBMITTED;
         failureMessage="Request already submitted";
         return true;
        }

      if(CPendingExecutionTransitionRules::BlocksBlindResend(entry.Status()))
        {
         failureReason=BRE_SUBMIT_FAIL_BLOCKED_STATE;
         failureMessage="Blind resend blocked for current status";
         return true;
        }

      if(CPendingExecutionTransitionRules::IsTerminal(entry.Status()))
        {
         failureReason=BRE_SUBMIT_FAIL_BLOCKED_STATE;
         failureMessage="Terminal state blocks resubmission";
         return true;
        }

      return false;
     }
  };

#endif
