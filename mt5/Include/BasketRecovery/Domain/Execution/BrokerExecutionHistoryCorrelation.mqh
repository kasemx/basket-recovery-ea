#ifndef BRE_DOMAIN_BROKER_EXECUTION_HISTORY_CORRELATION_MQH
#define BRE_DOMAIN_BROKER_EXECUTION_HISTORY_CORRELATION_MQH

class CBrokerExecutionHistoryCorrelation
  {
private:
   bool              m_queryAvailable;
   bool              m_hasFillEvidence;
   bool              m_hasRejectEvidence;
   bool              m_hasCancelEvidence;
   bool              m_hasFailureEvidence;
   bool              m_hasOpenPendingOrder;
   double            m_fillVolume;
   string            m_summary;
   string            m_evidenceMethod;
   int               m_fingerprintCandidateCount;
   int               m_stampCandidateCount;
   int               m_orderFilledCandidateCount;

public:
                     CBrokerExecutionHistoryCorrelation(void)
     {
      m_queryAvailable=false;
      m_hasFillEvidence=false;
      m_hasRejectEvidence=false;
      m_hasCancelEvidence=false;
      m_hasFailureEvidence=false;
      m_hasOpenPendingOrder=false;
      m_fillVolume=0.0;
      m_summary="unqueried";
      m_evidenceMethod="none";
      m_fingerprintCandidateCount=-1;
      m_stampCandidateCount=0;
      m_orderFilledCandidateCount=-1;
     }

   static CBrokerExecutionHistoryCorrelation Unqueried(void)
     {
      CBrokerExecutionHistoryCorrelation value;
      return value;
     }

   static CBrokerExecutionHistoryCorrelation Unavailable(const string reason="history_query_unavailable")
     {
      CBrokerExecutionHistoryCorrelation value;
      value.m_summary=reason;
      return value;
     }

   bool              QueryAvailable(void) const { return m_queryAvailable; }
   bool              HasFillEvidence(void) const { return m_hasFillEvidence; }
   bool              HasRejectEvidence(void) const { return m_hasRejectEvidence; }
   bool              HasCancelEvidence(void) const { return m_hasCancelEvidence; }
   bool              HasFailureEvidence(void) const { return m_hasFailureEvidence; }
   bool              HasOpenPendingOrder(void) const { return m_hasOpenPendingOrder; }
   double            FillVolume(void) const { return m_fillVolume; }
   string            Summary(void) const { return m_summary; }
   string            EvidenceMethod(void) const { return m_evidenceMethod; }
   int               FingerprintCandidateCount(void) const { return m_fingerprintCandidateCount; }
   int               StampCandidateCount(void) const { return m_stampCandidateCount; }
   int               OrderFilledCandidateCount(void) const { return m_orderFilledCandidateCount; }

   void              SetQueryAvailable(const bool value) { m_queryAvailable=value; }
   void              SetHasFillEvidence(const bool value) { m_hasFillEvidence=value; }
   void              SetHasRejectEvidence(const bool value) { m_hasRejectEvidence=value; }
   void              SetHasCancelEvidence(const bool value) { m_hasCancelEvidence=value; }
   void              SetHasFailureEvidence(const bool value) { m_hasFailureEvidence=value; }
   void              SetHasOpenPendingOrder(const bool value) { m_hasOpenPendingOrder=value; }
   void              SetFillVolume(const double value) { m_fillVolume=value; }
   void              SetSummary(const string value) { m_summary=value; }
   void              SetEvidenceMethod(const string value) { m_evidenceMethod=value; }
   void              SetFingerprintCandidateCount(const int value) { m_fingerprintCandidateCount=value; }
   void              SetStampCandidateCount(const int value) { m_stampCandidateCount=value; }
   void              SetOrderFilledCandidateCount(const int value) { m_orderFilledCandidateCount=value; }
  };

#endif
