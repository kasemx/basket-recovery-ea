#ifndef BRE_APP_BASKET_FAST_STATE_MQH
#define BRE_APP_BASKET_FAST_STATE_MQH

enum ENUM_BRE_FAST_EVAL_OUTCOME
  {
   BRE_FAST_EVAL_OUTCOME_NONE=0,
   BRE_FAST_EVAL_OUTCOME_EXECUTED,
   BRE_FAST_EVAL_OUTCOME_DEFERRED,
   BRE_FAST_EVAL_OUTCOME_SKIPPED
  };

class CBasketFastState
  {
private:
   ulong                         m_lastEvaluatedTickTimeMsc;
   double                        m_lastEvaluatedBid;
   double                        m_lastEvaluatedAsk;
   ulong                         m_lastEvaluatedQuoteSequence;
   bool                          m_forceReevaluate;
   ENUM_BRE_FAST_EVAL_OUTCOME    m_lastEvaluationOutcome;
   datetime                      m_nextAllowedEvaluationUtc;
   datetime                      m_lastTransactionUtc;

public:
                     CBasketFastState(void)
     {
      m_lastEvaluatedTickTimeMsc=0;
      m_lastEvaluatedBid=0.0;
      m_lastEvaluatedAsk=0.0;
      m_lastEvaluatedQuoteSequence=0;
      m_forceReevaluate=false;
      m_lastEvaluationOutcome=BRE_FAST_EVAL_OUTCOME_NONE;
      m_nextAllowedEvaluationUtc=0;
      m_lastTransactionUtc=0;
     }

                     CBasketFastState(const CBasketFastState &other)
     {
      m_lastEvaluatedTickTimeMsc=other.m_lastEvaluatedTickTimeMsc;
      m_lastEvaluatedBid=other.m_lastEvaluatedBid;
      m_lastEvaluatedAsk=other.m_lastEvaluatedAsk;
      m_lastEvaluatedQuoteSequence=other.m_lastEvaluatedQuoteSequence;
      m_forceReevaluate=other.m_forceReevaluate;
      m_lastEvaluationOutcome=other.m_lastEvaluationOutcome;
      m_nextAllowedEvaluationUtc=other.m_nextAllowedEvaluationUtc;
      m_lastTransactionUtc=other.m_lastTransactionUtc;
     }

   ulong                         LastEvaluatedTickTimeMsc(void) const { return m_lastEvaluatedTickTimeMsc; }
   double                        LastEvaluatedBid(void) const { return m_lastEvaluatedBid; }
   double                        LastEvaluatedAsk(void) const { return m_lastEvaluatedAsk; }
   ulong                         LastEvaluatedQuoteSequence(void) const { return m_lastEvaluatedQuoteSequence; }
   bool                          ForceReevaluate(void) const { return m_forceReevaluate; }
   ENUM_BRE_FAST_EVAL_OUTCOME    LastEvaluationOutcome(void) const { return m_lastEvaluationOutcome; }
   datetime                      NextAllowedEvaluationUtc(void) const { return m_nextAllowedEvaluationUtc; }
   datetime                      LastTransactionUtc(void) const { return m_lastTransactionUtc; }

   void                          SetLastEvaluatedTickTimeMsc(const ulong value) { m_lastEvaluatedTickTimeMsc=value; }
   void                          SetLastEvaluatedBid(const double value) { m_lastEvaluatedBid=value; }
   void                          SetLastEvaluatedAsk(const double value) { m_lastEvaluatedAsk=value; }
   void                          SetLastEvaluatedQuoteSequence(const ulong value) { m_lastEvaluatedQuoteSequence=value; }
   void                          SetForceReevaluate(const bool value) { m_forceReevaluate=value; }
   void                          SetLastEvaluationOutcome(const ENUM_BRE_FAST_EVAL_OUTCOME value) { m_lastEvaluationOutcome=value; }
   void                          SetNextAllowedEvaluationUtc(const datetime value) { m_nextAllowedEvaluationUtc=value; }
   void                          SetLastTransactionUtc(const datetime value) { m_lastTransactionUtc=value; }
  };

#endif
