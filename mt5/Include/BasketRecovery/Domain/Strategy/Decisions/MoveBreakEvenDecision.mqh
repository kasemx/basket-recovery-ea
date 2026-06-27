#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_MOVE_BREAK_EVEN_DECISION_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_MOVE_BREAK_EVEN_DECISION_MQH

class CMoveBreakEvenDecision
  {
private:
   string m_idempotencyKey;
   string m_ruleId;
   double m_bufferPips;
   bool   m_includeSpread;
   double m_slOffsetPips;
   bool   m_useOffset;

                     CMoveBreakEvenDecision(void) {}

public:
   string            IdempotencyKey(void) const { return m_idempotencyKey; }
   string            RuleId(void) const { return m_ruleId; }
   double            BufferPips(void) const { return m_bufferPips; }
   bool              IncludeSpread(void) const { return m_includeSpread; }
   double            SlOffsetPips(void) const { return m_slOffsetPips; }
   bool              UseOffset(void) const { return m_useOffset; }

   static CMoveBreakEvenDecision CreateAverage(const string idempotencyKey,
                                               const string ruleId,
                                               const double bufferPips,
                                               const bool includeSpread)
     {
      CMoveBreakEvenDecision decision;
      decision.m_idempotencyKey=idempotencyKey;
      decision.m_ruleId=ruleId;
      decision.m_bufferPips=bufferPips;
      decision.m_includeSpread=includeSpread;
      decision.m_slOffsetPips=0.0;
      decision.m_useOffset=false;
      return decision;
     }

   static CMoveBreakEvenDecision CreateOffset(const string idempotencyKey,
                                              const string ruleId,
                                              const double slOffsetPips)
     {
      CMoveBreakEvenDecision decision;
      decision.m_idempotencyKey=idempotencyKey;
      decision.m_ruleId=ruleId;
      decision.m_bufferPips=0.0;
      decision.m_includeSpread=false;
      decision.m_slOffsetPips=slOffsetPips;
      decision.m_useOffset=true;
      return decision;
     }
  };

#endif
