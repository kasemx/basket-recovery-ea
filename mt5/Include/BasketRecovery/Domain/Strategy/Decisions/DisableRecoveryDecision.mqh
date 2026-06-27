#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_DISABLE_RECOVERY_DECISION_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_DISABLE_RECOVERY_DECISION_MQH

class CDisableRecoveryDecision
  {
private:
   string m_idempotencyKey;
   string m_ruleId;
   bool   m_permanent;

public:
                     CDisableRecoveryDecision(void) {}

                     CDisableRecoveryDecision(const CDisableRecoveryDecision &other)
     {
      m_idempotencyKey=other.m_idempotencyKey;
      m_ruleId=other.m_ruleId;
      m_permanent=other.m_permanent;
     }

   string            IdempotencyKey(void) const { return m_idempotencyKey; }
   string            RuleId(void) const { return m_ruleId; }
   bool              Permanent(void) const { return m_permanent; }

   static CDisableRecoveryDecision Create(const string idempotencyKey,const string ruleId,const bool permanent)
     {
      CDisableRecoveryDecision decision;
      decision.m_idempotencyKey=idempotencyKey;
      decision.m_ruleId=ruleId;
      decision.m_permanent=permanent;
      return decision;
     }
  };

#endif
