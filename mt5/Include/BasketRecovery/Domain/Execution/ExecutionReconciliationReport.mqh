#ifndef BRE_DOMAIN_EXECUTION_RECONCILIATION_REPORT_MQH
#define BRE_DOMAIN_EXECUTION_RECONCILIATION_REPORT_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/BrokerExecutionHistoryCorrelation.mqh>

class CExecutionReconciliationReport
  {
private:
   string                            m_currentOpenState;
   string                            m_historyCorrelationState;
   ENUM_BRE_TRADE_EXECUTION_STATUS   m_finalState;
   string                            m_confidence;
   bool                              m_mutationPermitted;
   string                            m_evidenceMethod;
   int                               m_fingerprintCandidateCount;
   int                               m_stampCandidateCount;
   int                               m_orderFilledCandidateCount;

public:
                     CExecutionReconciliationReport(void)
     {
      m_currentOpenState="unqueried";
      m_historyCorrelationState="unqueried";
      m_finalState=BRE_TRADE_EXEC_STATUS_UNKNOWN;
      m_confidence="none";
      m_mutationPermitted=false;
      m_evidenceMethod="none";
      m_fingerprintCandidateCount=-1;
      m_stampCandidateCount=0;
      m_orderFilledCandidateCount=-1;
     }

   string            CurrentOpenState(void) const { return m_currentOpenState; }
   string            HistoryCorrelationState(void) const { return m_historyCorrelationState; }
   ENUM_BRE_TRADE_EXECUTION_STATUS FinalState(void) const { return m_finalState; }
   string            Confidence(void) const { return m_confidence; }
   bool              MutationPermitted(void) const { return m_mutationPermitted; }
   string            EvidenceMethod(void) const { return m_evidenceMethod; }
   int               FingerprintCandidateCount(void) const { return m_fingerprintCandidateCount; }
   int               StampCandidateCount(void) const { return m_stampCandidateCount; }
   int               OrderFilledCandidateCount(void) const { return m_orderFilledCandidateCount; }

   void              SetCurrentOpenState(const string value) { m_currentOpenState=value; }
   void              SetHistoryCorrelationState(const string value) { m_historyCorrelationState=value; }
   void              SetFinalState(const ENUM_BRE_TRADE_EXECUTION_STATUS value) { m_finalState=value; }
   void              SetConfidence(const string value) { m_confidence=value; }
   void              SetMutationPermitted(const bool value) { m_mutationPermitted=value; }
   void              SetEvidenceMethod(const string value) { m_evidenceMethod=value; }
   void              SetFingerprintCandidateCount(const int value) { m_fingerprintCandidateCount=value; }
   void              SetStampCandidateCount(const int value) { m_stampCandidateCount=value; }
   void              SetOrderFilledCandidateCount(const int value) { m_orderFilledCandidateCount=value; }
  };

#endif
