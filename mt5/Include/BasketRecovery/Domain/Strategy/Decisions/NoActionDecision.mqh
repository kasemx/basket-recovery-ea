#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_NO_ACTION_DECISION_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_NO_ACTION_DECISION_MQH

class CNoActionDecision
  {
private:
   string m_idempotencyKey;
   string m_reason;

public:
                     CNoActionDecision(void) {}

                     CNoActionDecision(const CNoActionDecision &other)
     {
      m_idempotencyKey=other.m_idempotencyKey;
      m_reason=other.m_reason;
     }

   string            IdempotencyKey(void) const { return m_idempotencyKey; }
   string            Reason(void) const { return m_reason; }

   static CNoActionDecision Create(const string idempotencyKey,const string reason)
     {
      CNoActionDecision decision;
      decision.m_idempotencyKey=idempotencyKey;
      decision.m_reason=reason;
      return decision;
     }
  };

#endif
