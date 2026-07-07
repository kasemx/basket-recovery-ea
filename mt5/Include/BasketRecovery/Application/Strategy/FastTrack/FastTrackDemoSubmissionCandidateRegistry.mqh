#ifndef BRE_APP_FAST_TRACK_DEMO_SUBMISSION_CANDIDATE_REGISTRY_MQH
#define BRE_APP_FAST_TRACK_DEMO_SUBMISSION_CANDIDATE_REGISTRY_MQH

#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackDemoSubmissionTypes.mqh>

class CFastTrackDemoSubmissionCandidateRegistry
  {
private:
   string                       m_processed_idempotency_keys[];
   SFastTrackDemoSubmissionCandidate m_active_candidate;
   bool                         m_has_active_candidate;

public:
                     CFastTrackDemoSubmissionCandidateRegistry(void)
     {
      ArrayResize(m_processed_idempotency_keys,0);
      m_has_active_candidate=false;
      m_active_candidate.Reset();
     }

   void              ResetForTests(void)
     {
      ArrayResize(m_processed_idempotency_keys,0);
      m_has_active_candidate=false;
      m_active_candidate.Reset();
     }

   bool              HasProcessedIdempotencyKey(const string idempotencyKey) const
     {
      for(int i=0;i<ArraySize(m_processed_idempotency_keys);i++)
        {
         if(m_processed_idempotency_keys[i]==idempotencyKey)
            return true;
        }
      return false;
     }

   void              MarkProcessedIdempotencyKey(const string idempotencyKey)
     {
      if(idempotencyKey=="" || HasProcessedIdempotencyKey(idempotencyKey))
         return;
      const int size=ArraySize(m_processed_idempotency_keys);
      ArrayResize(m_processed_idempotency_keys,size+1);
      m_processed_idempotency_keys[size]=idempotencyKey;
     }

   bool              TryGetActiveCandidate(SFastTrackDemoSubmissionCandidate &candidateOut) const
     {
      if(!m_has_active_candidate)
         return false;
      candidateOut=m_active_candidate;
      return true;
     }

   void              RegisterActiveCandidate(const SFastTrackDemoSubmissionCandidate &candidate)
     {
      m_active_candidate=candidate;
      m_has_active_candidate=true;
     }
  };

#endif
