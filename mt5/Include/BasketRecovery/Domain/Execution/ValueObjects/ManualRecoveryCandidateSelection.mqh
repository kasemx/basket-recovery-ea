#ifndef BRE_DOMAIN_MANUAL_RECOVERY_CANDIDATE_SELECTION_MQH
#define BRE_DOMAIN_MANUAL_RECOVERY_CANDIDATE_SELECTION_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>

class CManualRecoveryCandidateSelection
  {
private:
   string    m_candidateId;
   CBasketId m_basketId;
   datetime  m_selectedAtUtc;

public:
   string    CandidateId(void) const { return m_candidateId; }
   CBasketId BasketId(void) const { return m_basketId; }
   datetime  SelectedAtUtc(void) const { return m_selectedAtUtc; }

   static CManualRecoveryCandidateSelection Create(const string candidateId,
                                                  const CBasketId &basketId,
                                                  const datetime selectedAtUtc)
     {
      CManualRecoveryCandidateSelection selection;
      selection.m_candidateId=candidateId;
      selection.m_basketId=basketId;
      selection.m_selectedAtUtc=selectedAtUtc;
      return selection;
     }
  };

#endif
