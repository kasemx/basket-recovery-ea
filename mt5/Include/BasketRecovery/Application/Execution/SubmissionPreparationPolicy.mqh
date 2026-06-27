#ifndef BRE_APP_SUBMISSION_PREPARATION_POLICY_MQH
#define BRE_APP_SUBMISSION_PREPARATION_POLICY_MQH

class CSubmissionPreparationPolicy
  {
private:
   int      m_maxCommentLength;
   int      m_quoteFreshnessMs;
   int      m_envelopeValiditySeconds;

public:
                     CSubmissionPreparationPolicy(void)
     {
      m_maxCommentLength=31;
      m_quoteFreshnessMs=5000;
      m_envelopeValiditySeconds=60;
     }

                     CSubmissionPreparationPolicy(const int maxCommentLength,
                                                  const int quoteFreshnessMs,
                                                  const int envelopeValiditySeconds)
     {
      m_maxCommentLength=(maxCommentLength<=0 ? 31 : maxCommentLength);
      m_quoteFreshnessMs=(quoteFreshnessMs<=0 ? 5000 : quoteFreshnessMs);
      m_envelopeValiditySeconds=(envelopeValiditySeconds<=0 ? 60 : envelopeValiditySeconds);
     }

   int               MaxCommentLength(void) const { return m_maxCommentLength; }
   int               QuoteFreshnessMs(void) const { return m_quoteFreshnessMs; }
   int               EnvelopeValiditySeconds(void) const { return m_envelopeValiditySeconds; }

   static CSubmissionPreparationPolicy Default(void)
     {
      CSubmissionPreparationPolicy policy;
      return policy;
     }
  };

#endif
