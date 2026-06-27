#ifndef BRE_APP_SUBMIT_PREPARED_EXECUTION_USE_CASE_MQH
#define BRE_APP_SUBMIT_PREPARED_EXECUTION_USE_CASE_MQH

#include <BasketRecovery/Application/Execution/PreparedSubmissionValidator.mqh>
#include <BasketRecovery/Application/Execution/SubmissionResultMapper.mqh>
#include <BasketRecovery/Application/Execution/SubmissionDiagnostics.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/Ports/ISubmissionGateway.mqh>
#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Domain/Execution/PreparedSubmissionResult.mqh>

class CSubmitPreparedExecutionUseCase
  {
private:
   CPreparedSubmissionValidator m_validator;
   CPendingExecutionRegistry   *m_registry;
   ISubmissionGateway          *m_gateway;
   IPendingExecutionStore      *m_store;
   IClock                      *m_clock;
   CSubmissionDiagnostics      *m_diagnostics;

   string            m_cachedIdempotencyKeys[];
   CPreparedSubmissionResult m_cachedOutcomes[];

   int               FindCachedIndex(const string idempotencyKey) const
     {
      for(int i=0;i<ArraySize(m_cachedIdempotencyKeys);i++)
        {
         if(m_cachedIdempotencyKeys[i]==idempotencyKey)
            return i;
        }
      return -1;
     }

   void              RememberOutcome(const string idempotencyKey,const CPreparedSubmissionResult &outcome)
     {
      int index=FindCachedIndex(idempotencyKey);
      if(index<0)
        {
         int size=ArraySize(m_cachedIdempotencyKeys);
         ArrayResize(m_cachedIdempotencyKeys,size+1);
         ArrayResize(m_cachedOutcomes,size+1);
         m_cachedIdempotencyKeys[size]=idempotencyKey;
         m_cachedOutcomes[size]=outcome;
        }
      else
        {
         m_cachedOutcomes[index]=outcome;
        }
     }

   CPreparedSubmissionResult TryReturnCached(const string idempotencyKey)
     {
      int index=FindCachedIndex(idempotencyKey);
      if(index<0)
         return CPreparedSubmissionResult();
      CPreparedSubmissionResult cached=m_cachedOutcomes[index];
      if(cached.IsSuccess())
         return CPreparedSubmissionResult::Ok(cached.ResultingStatus(),
                                            cached.BrokerRequestId(),
                                            true,
                                            false);
      return CPreparedSubmissionResult::Fail(cached.FailureReason(),
                                             cached.FailureMessage(),
                                             cached.ResultingStatus(),
                                             true,
                                             false);
     }

   void              PersistEntry(const CPendingExecutionEntry &entry,const CBrokerSubmissionEnvelope &envelope)
     {
      if(m_store==NULL)
         return;
      m_store.SavePreparedState(entry,envelope);
     }

   CPreparedSubmissionResult ApplyGatewayAccepted(CPendingExecutionEntry &entry,
                                                  const CBrokerSubmissionEnvelope &envelope,
                                                  const CSubmissionGatewayResult &gatewayResult,
                                                  const bool duplicateReplay,
                                                  const bool gatewayInvoked)
     {
      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : TimeCurrent();
      CPendingExecutionEntry updated;
      if(!m_registry.TryBrokerSubmitTransition(entry.ExecutionRequestId(),true,updated))
        {
         return CPreparedSubmissionResult::Fail(BRE_SUBMIT_FAIL_VALIDATION,
                                                "Broker submit transition to SUBMITTED failed");
        }

      updated.SetSubmittedAtUtc(nowUtc);
      CBrokerRequestCorrelation broker=updated.BrokerCorrelation();
      broker.SetBrokerOrderId(gatewayResult.BrokerRequestId());
      updated.SetBrokerCorrelation(broker);
      m_registry.Upsert(updated);

      if(m_diagnostics!=NULL)
        {
         m_diagnostics.OnBrokerPlaceholderAssigned(updated.ExecutionRequestId(),gatewayResult.BrokerRequestId());
         m_diagnostics.OnStateTransition(entry.ExecutionRequestId(),
                                         entry.Status(),
                                         BRE_TRADE_EXEC_STATUS_SUBMITTED,
                                         true);
        }

      PersistEntry(updated,envelope);
      CPreparedSubmissionResult outcome=CSubmissionResultMapper::MapGatewayAccepted(gatewayResult.BrokerRequestId(),
                                                                                    duplicateReplay,
                                                                                    gatewayInvoked);
      RememberOutcome(entry.IdempotencyKey(),outcome);
      return outcome;
     }

   CPreparedSubmissionResult ApplyGatewayRejected(CPendingExecutionEntry &entry,
                                                  const CBrokerSubmissionEnvelope &envelope,
                                                  const CSubmissionGatewayResult &gatewayResult)
     {
      CPendingExecutionEntry updated;
      ENUM_BRE_TRADE_EXECUTION_STATUS rejectedStatus=CSubmissionResultMapper::MapGatewayRejectionStatus();
      if(!m_registry.TryTransitionByRequestId(entry.ExecutionRequestId(),rejectedStatus,updated))
        {
         return CPreparedSubmissionResult::Fail(BRE_SUBMIT_FAIL_VALIDATION,
                                                "Failed to transition entry to REJECTED");
        }
      m_registry.Upsert(updated);
      PersistEntry(updated,envelope);
      CPreparedSubmissionResult outcome=CSubmissionResultMapper::MapGatewayRejected(gatewayResult.Detail());
      RememberOutcome(entry.IdempotencyKey(),outcome);
      return outcome;
     }

   CPreparedSubmissionResult ApplyGatewayUnknown(CPendingExecutionEntry &entry,
                                                 const CBrokerSubmissionEnvelope &envelope,
                                                 const CSubmissionGatewayResult &gatewayResult)
     {
      CPendingExecutionEntry updated;
      ENUM_BRE_TRADE_EXECUTION_STATUS unknownStatus=CSubmissionResultMapper::MapGatewayUnknownStatus();
      if(!m_registry.TryTransitionByRequestId(entry.ExecutionRequestId(),unknownStatus,updated))
        {
         return CPreparedSubmissionResult::Fail(BRE_SUBMIT_FAIL_VALIDATION,
                                                "Failed to transition entry to UNKNOWN");
        }
      m_registry.Upsert(updated);
      PersistEntry(updated,envelope);
      CPreparedSubmissionResult outcome=CSubmissionResultMapper::MapGatewayUnknown(gatewayResult.Detail());
      RememberOutcome(entry.IdempotencyKey(),outcome);
      return outcome;
     }

public:
                     CSubmitPreparedExecutionUseCase(CPendingExecutionRegistry *registry,
                                                     ISubmissionGateway *gateway,
                                                     IPendingExecutionStore *store,
                                                     IClock *clock,
                                                     CSubmissionDiagnostics *diagnostics=NULL)
     : m_validator(registry,store,clock)
     {
      m_registry=registry;
      m_gateway=gateway;
      m_store=store;
      m_clock=clock;
      m_diagnostics=diagnostics;
     }

   CPreparedSubmissionResult Execute(const string executionRequestId)
     {
      if(m_gateway==NULL)
         return CPreparedSubmissionResult::Fail(BRE_SUBMIT_FAIL_VALIDATION,"Submission gateway is not configured");

      if(m_diagnostics!=NULL)
         m_diagnostics.OnSubmissionAttempted(executionRequestId);

      CPendingExecutionEntry entry;
      CBrokerSubmissionEnvelope envelope;
      ENUM_BRE_PREPARED_SUBMISSION_FAILURE_REASON failureReason=BRE_SUBMIT_FAIL_NONE;
      string failureMessage="";

      if(!m_validator.Validate(executionRequestId,entry,envelope,failureReason,failureMessage))
        {
         if(m_diagnostics!=NULL)
           {
            m_diagnostics.OnEnvelopeValidation(executionRequestId,false,failureMessage);
            m_diagnostics.OnValidationFailure(executionRequestId,failureReason);
           }
         return CPreparedSubmissionResult::Fail(failureReason,failureMessage);
        }

      if(m_diagnostics!=NULL)
         m_diagnostics.OnEnvelopeValidation(executionRequestId,true,"ok");

      ENUM_BRE_PREPARED_SUBMISSION_FAILURE_REASON blockReason=BRE_SUBMIT_FAIL_NONE;
      string blockMessage="";
      if(m_validator.BlocksResubmission(entry,blockReason,blockMessage))
        {
         if(blockReason==BRE_SUBMIT_FAIL_ALREADY_SUBMITTED)
           {
            if(m_diagnostics!=NULL)
               m_diagnostics.OnDuplicateSubmissionBlocked(executionRequestId,entry.IdempotencyKey());
            ulong brokerRequestId=entry.BrokerCorrelation().BrokerOrderId();
            CPreparedSubmissionResult duplicate=CSubmissionResultMapper::MapDuplicateFromEntry(entry,brokerRequestId);
            return duplicate;
           }
         if(m_diagnostics!=NULL)
            m_diagnostics.OnValidationFailure(executionRequestId,blockReason);
         return CPreparedSubmissionResult::Fail(blockReason,blockMessage,entry.Status());
        }

      int cachedIndex=FindCachedIndex(entry.IdempotencyKey());
      if(cachedIndex>=0)
        {
         if(m_diagnostics!=NULL)
            m_diagnostics.OnDuplicateSubmissionBlocked(executionRequestId,entry.IdempotencyKey());
         return TryReturnCached(entry.IdempotencyKey());
        }

      CSubmissionGatewayResult gatewayResult=m_gateway.Submit(envelope);
      if(m_diagnostics!=NULL)
         m_diagnostics.OnGatewayResult(executionRequestId,gatewayResult.Status());

      if(gatewayResult.IsDuplicateReplay())
        {
         if(m_diagnostics!=NULL)
            m_diagnostics.OnDuplicateSubmissionBlocked(executionRequestId,entry.IdempotencyKey());
         return TryReturnCached(entry.IdempotencyKey());
        }

      if(gatewayResult.IsAccepted())
        {
         if(m_diagnostics!=NULL)
            m_diagnostics.OnSimulatedSubmitAccepted(executionRequestId,gatewayResult.BrokerRequestId());
         return ApplyGatewayAccepted(entry,envelope,gatewayResult,false,true);
        }

      if(gatewayResult.IsRejected())
        {
         if(m_diagnostics!=NULL)
            m_diagnostics.OnSimulatedSubmitRejected(executionRequestId,gatewayResult.Detail());
         return ApplyGatewayRejected(entry,envelope,gatewayResult);
        }

      if(gatewayResult.IsUnknown())
        {
         return ApplyGatewayUnknown(entry,envelope,gatewayResult);
        }

      return CPreparedSubmissionResult::Fail(BRE_SUBMIT_FAIL_VALIDATION,"Unsupported gateway result");
     }

   void              ClearCache(void)
     {
      ArrayResize(m_cachedIdempotencyKeys,0);
      ArrayResize(m_cachedOutcomes,0);
     }
  };

#endif
