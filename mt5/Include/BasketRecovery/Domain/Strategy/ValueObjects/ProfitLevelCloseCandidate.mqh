#ifndef BRE_DOMAIN_PROFIT_LEVEL_CLOSE_CANDIDATE_MQH
#define BRE_DOMAIN_PROFIT_LEVEL_CLOSE_CANDIDATE_MQH

#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevelCloseAudit.mqh>

class CProfitLevelCloseCandidate
  {
private:
   CProfitLevelCloseAudit m_audit;

public:
                     CProfitLevelCloseCandidate(void) {}

                     CProfitLevelCloseCandidate(const CProfitLevelCloseCandidate &other)
     {
      m_audit=other.m_audit;
     }

   CProfitLevelCloseAudit                  Audit(void) const { return m_audit; }
   ENUM_BRE_PROFIT_LEVEL_CLOSE_CANDIDATE_STATUS Status(void) const { return m_audit.Status(); }
   ENUM_BRE_PROFIT_LEVEL_CLOSE_REASON      Reason(void) const { return m_audit.Reason(); }
   string                                  IdempotencyKey(void) const { return m_audit.IdempotencyKey(); }
   string                                  ProfitLevelId(void) const { return m_audit.ProfitLevelId(); }

   bool                                    IsDue(void) const
     {
      return m_audit.Status()==BRE_PROFIT_LEVEL_CLOSE_DUE;
     }

   static CProfitLevelCloseCandidate       FromAudit(const CProfitLevelCloseAudit &audit)
     {
      CProfitLevelCloseCandidate candidate;
      candidate.m_audit=audit;
      return candidate;
     }
  };

#endif
