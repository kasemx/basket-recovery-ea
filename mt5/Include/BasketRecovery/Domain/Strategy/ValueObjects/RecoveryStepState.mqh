#ifndef BRE_DOMAIN_RECOVERY_STEP_STATE_MQH
#define BRE_DOMAIN_RECOVERY_STEP_STATE_MQH

#include <BasketRecovery/Domain/Strategy/Enums/RecoveryCandidateStatus.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/RecoveryCandidateReason.mqh>

class CRecoveryStepState
  {
private:
   ulong                             m_lastEvaluatedQuoteSequence;
   int                               m_lastAcceptedStepIndex;
   double                            m_lastTriggerReferencePrice;
   string                            m_candidateIdempotencyKey;
   ENUM_BRE_RECOVERY_CANDIDATE_STATUS m_lastCandidateStatus;
   ENUM_BRE_RECOVERY_CANDIDATE_REASON m_lastBlockReason;
   double                            m_priorRecoveryVolume;

public:
                     CRecoveryStepState(void)
     {
      m_lastEvaluatedQuoteSequence=0;
      m_lastAcceptedStepIndex=0;
      m_lastTriggerReferencePrice=0.0;
      m_lastCandidateStatus=BRE_RECOVERY_CANDIDATE_NOT_DUE;
      m_lastBlockReason=BRE_RECOVERY_CANDIDATE_REASON_NONE;
      m_priorRecoveryVolume=0.0;
     }

                     CRecoveryStepState(const CRecoveryStepState &other)
     {
      m_lastEvaluatedQuoteSequence=other.m_lastEvaluatedQuoteSequence;
      m_lastAcceptedStepIndex=other.m_lastAcceptedStepIndex;
      m_lastTriggerReferencePrice=other.m_lastTriggerReferencePrice;
      m_candidateIdempotencyKey=other.m_candidateIdempotencyKey;
      m_lastCandidateStatus=other.m_lastCandidateStatus;
      m_lastBlockReason=other.m_lastBlockReason;
      m_priorRecoveryVolume=other.m_priorRecoveryVolume;
     }

   ulong                             LastEvaluatedQuoteSequence(void) const { return m_lastEvaluatedQuoteSequence; }
   int                               LastAcceptedStepIndex(void) const { return m_lastAcceptedStepIndex; }
   double                            LastTriggerReferencePrice(void) const { return m_lastTriggerReferencePrice; }
   string                            CandidateIdempotencyKey(void) const { return m_candidateIdempotencyKey; }
   ENUM_BRE_RECOVERY_CANDIDATE_STATUS LastCandidateStatus(void) const { return m_lastCandidateStatus; }
   ENUM_BRE_RECOVERY_CANDIDATE_REASON LastBlockReason(void) const { return m_lastBlockReason; }
   double                            PriorRecoveryVolume(void) const { return m_priorRecoveryVolume; }

   void                              RecordEvaluation(const ulong quoteSequence,
                                                      const ENUM_BRE_RECOVERY_CANDIDATE_STATUS status,
                                                      const ENUM_BRE_RECOVERY_CANDIDATE_REASON reason,
                                                      const string idempotencyKey)
     {
      m_lastEvaluatedQuoteSequence=quoteSequence;
      m_lastCandidateStatus=status;
      m_lastBlockReason=reason;
      m_candidateIdempotencyKey=idempotencyKey;
     }

   static CRecoveryStepState         Create(const int lastAcceptedStepIndex,
                                            const double lastTriggerReferencePrice,
                                            const double priorRecoveryVolume)
     {
      CRecoveryStepState state;
      state.m_lastAcceptedStepIndex=lastAcceptedStepIndex;
      state.m_lastTriggerReferencePrice=lastTriggerReferencePrice;
      state.m_priorRecoveryVolume=priorRecoveryVolume;
      return state;
     }
  };

#endif
