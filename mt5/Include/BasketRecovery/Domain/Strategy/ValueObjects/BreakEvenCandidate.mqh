#ifndef BRE_DOMAIN_BREAK_EVEN_CANDIDATE_MQH
#define BRE_DOMAIN_BREAK_EVEN_CANDIDATE_MQH

#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenCandidateAudit.mqh>

class CBreakEvenCandidate
  {
private:
   CBreakEvenCandidateAudit m_audit;

public:
                     CBreakEvenCandidate(void) {}

                     CBreakEvenCandidate(const CBreakEvenCandidate &other)
     {
      m_audit=other.m_audit;
     }

   CBreakEvenCandidateAudit                  Audit(void) const { return m_audit; }
   ENUM_BRE_BREAK_EVEN_CANDIDATE_STATUS      Status(void) const { return m_audit.Status(); }
   ENUM_BRE_BREAK_EVEN_REASON                Reason(void) const { return m_audit.Reason(); }
   string                                    IdempotencyKey(void) const { return m_audit.IdempotencyKey(); }
   string                                    RuleId(void) const { return m_audit.RuleId(); }

   bool                                      IsDue(void) const
     {
      return m_audit.Status()==BRE_BREAK_EVEN_CANDIDATE_DUE;
     }

   static CBreakEvenCandidate                FromAudit(const CBreakEvenCandidateAudit &audit)
     {
      CBreakEvenCandidate candidate;
      candidate.m_audit=audit;
      return candidate;
     }
  };

#endif
