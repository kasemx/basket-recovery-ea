#ifndef BRE_DOMAIN_RECOVERY_CANDIDATE_MQH
#define BRE_DOMAIN_RECOVERY_CANDIDATE_MQH

#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryCandidateAudit.mqh>

class CRecoveryCandidate
  {
private:
   CRecoveryCandidateAudit           m_audit;

public:
                     CRecoveryCandidate(void) {}

                     CRecoveryCandidate(const CRecoveryCandidate &other)
     {
      m_audit=other.m_audit;
     }

   CRecoveryCandidateAudit           Audit(void) const { return m_audit; }
   ENUM_BRE_RECOVERY_CANDIDATE_STATUS Status(void) const { return m_audit.Status(); }
   ENUM_BRE_RECOVERY_CANDIDATE_REASON Reason(void) const { return m_audit.Reason(); }
   string                            IdempotencyKey(void) const { return m_audit.IdempotencyKey(); }
   int                               RecoveryStepIndex(void) const { return m_audit.RecoveryStepIndex(); }
   double                            ProposedVolume(void) const { return m_audit.ProposedVolume(); }
   double                            TriggerReferencePrice(void) const { return m_audit.TriggerReferencePrice(); }

   bool                              IsDue(void) const
     {
      return m_audit.Status()==BRE_RECOVERY_CANDIDATE_DUE;
     }

   static CRecoveryCandidate         FromAudit(const CRecoveryCandidateAudit &audit)
     {
      CRecoveryCandidate candidate;
      candidate.m_audit=audit;
      return candidate;
     }
  };

#endif
