#ifndef BRE_DOMAIN_RECOVERY_CANDIDATE_MANUAL_AUTH_CONTEXT_MQH
#define BRE_DOMAIN_RECOVERY_CANDIDATE_MANUAL_AUTH_CONTEXT_MQH

#include <BasketRecovery/Domain/Execution/ValueObjects/ManualRecoveryCandidateEntry.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>

class CRecoveryCandidateManualAuthorizationContext
  {
private:
   string m_executionRequestId;
   string m_bindingFingerprint;
   string m_tokenHash;

public:
   string ExecutionRequestId(void) const { return m_executionRequestId; }
   string BindingFingerprint(void) const { return m_bindingFingerprint; }
   string TokenHash(void) const { return m_tokenHash; }

   static CRecoveryCandidateManualAuthorizationContext FromEntry(const CManualRecoveryCandidateEntry &entry,
                                                                 const string plaintextToken)
     {
      CRecoveryCandidateManualAuthorizationContext context;
      context.m_executionRequestId=entry.ExecutionRequestId();
      context.m_bindingFingerprint=CExecutionAuthorizationToken::ComputeBindingFingerprint(entry.ExecutionRequestId(),
                                                                                           entry.BasketId(),
                                                                                           entry.Symbol(),
                                                                                           BRE_EXEC_INTENT_OPEN_POSITION,
                                                                                           entry.ProposedVolume(),
                                                                                           entry.BasketVersion(),
                                                                                           entry.StrategyProfileHash());
      context.m_tokenHash=CExecutionAuthorizationToken::ComputeTokenHash(plaintextToken);
      return context;
     }
  };

#endif
