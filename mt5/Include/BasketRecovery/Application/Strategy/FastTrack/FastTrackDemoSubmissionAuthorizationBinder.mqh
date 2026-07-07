#ifndef BRE_APP_FAST_TRACK_DEMO_SUBMISSION_AUTHORIZATION_BINDER_MQH
#define BRE_APP_FAST_TRACK_DEMO_SUBMISSION_AUTHORIZATION_BINDER_MQH

#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackDemoSubmissionTypes.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackDemoSubmissionCandidateRegistry.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>

struct SFastTrackDemoSubmissionAuthorizationCheckOutcome
  {
   bool              accepted;
   string            rejection_reason;
   string            detail;

   void              Reset(void)
     {
      accepted=false;
      rejection_reason="";
      detail="";
     }
  };

class CFastTrackDemoSubmissionAuthorizationBinder
  {
public:
   static SFastTrackDemoSubmissionAuthorizationCheckOutcome ValidateCandidateBinding(
      const CFastTrackDemoSubmissionCandidateRegistry &registry,
      const string executionRequestId,
      const string basketId,
      const string idempotencyKey)
     {
      SFastTrackDemoSubmissionAuthorizationCheckOutcome outcome;
      outcome.Reset();

      SFastTrackDemoSubmissionCandidate candidate;
      if(!registry.TryGetActiveCandidate(candidate))
        {
         outcome.rejection_reason="FASTTRACK_AUTHORIZATION_REJECTED";
         outcome.detail="No active FastTrack demo submission candidate";
         return outcome;
        }
      if(candidate.execution_request_id!=executionRequestId ||
         candidate.basket_id!=basketId ||
         candidate.idempotency_key!=idempotencyKey)
        {
         outcome.rejection_reason="FASTTRACK_AUTHORIZATION_REJECTED";
         outcome.detail="Candidate binding mismatch";
         return outcome;
        }
      if(candidate.status!=BRE_FT_DEMO_SUB_AWAIT_AUTH)
        {
         outcome.rejection_reason="FASTTRACK_AUTHORIZATION_REJECTED";
         outcome.detail="Candidate is not awaiting manual authorization";
         return outcome;
        }

      outcome.accepted=true;
      return outcome;
     }

   static SFastTrackDemoSubmissionAuthorizationCheckOutcome ValidateAuthorizationToken(
      const SFastTrackDemoSubmissionCandidate &candidate,
      const string authorizationToken,
      const datetime nowUtc,
      const int expectedBasketVersion,
      const string strategyProfileHash)
     {
      SFastTrackDemoSubmissionAuthorizationCheckOutcome outcome;
      outcome.Reset();

      if(authorizationToken=="")
        {
         outcome.rejection_reason="FASTTRACK_AUTHORIZATION_REJECTED";
         outcome.detail="Authorization token required";
         return outcome;
        }

      string bindingFingerprint="";
      datetime expiryUtc=0;
      if(!CExecutionAuthorizationToken::TryParsePlaintextToken(authorizationToken,bindingFingerprint,expiryUtc))
        {
         outcome.rejection_reason="FASTTRACK_AUTHORIZATION_REJECTED";
         outcome.detail="Authorization token format invalid";
         return outcome;
        }
      if(expiryUtc<=nowUtc)
        {
         outcome.rejection_reason="FASTTRACK_AUTHORIZATION_REJECTED";
         outcome.detail="Authorization token expired";
         return outcome;
        }

      const string expectedFingerprint=CExecutionAuthorizationToken::ComputeBindingFingerprint(
         candidate.execution_request_id,
         CBasketId(candidate.basket_id),
         candidate.symbol,
         BRE_EXEC_INTENT_OPEN_POSITION,
         candidate.volume,
         expectedBasketVersion,
         strategyProfileHash);
      if(bindingFingerprint!=expectedFingerprint)
        {
         outcome.rejection_reason="FASTTRACK_AUTHORIZATION_REJECTED";
         outcome.detail="Authorization token binding mismatch";
         return outcome;
        }

      outcome.accepted=true;
      return outcome;
     }
  };

#endif
