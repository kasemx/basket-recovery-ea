#ifndef BRE_DOMAIN_BREAK_EVEN_MODIFICATION_AUDIT_MQH
#define BRE_DOMAIN_BREAK_EVEN_MODIFICATION_AUDIT_MQH

#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenStopLossModificationRequest.mqh>

class CBreakEvenModificationAudit
  {
private:
   CBreakEvenStopLossModificationRequest m_request;
   bool                                  m_lifecycleActive;
   bool                                  m_candidateDue;
   bool                                  m_breakEvenInactive;
   bool                                  m_quoteSequenceMatched;
   bool                                  m_quoteFresh;
   bool                                  m_noPendingExecution;
   bool                                  m_profileBindingMatched;
   bool                                  m_snapshotConsistent;
   bool                                  m_stopValidationPassed;
   bool                                  m_idempotencyPassed;
   bool                                  m_dryRunAuthorized;
   bool                                  m_accountEligible;
   bool                                  m_allOrNothingSatisfied;

public:
                     CBreakEvenModificationAudit(void)
     {
      m_lifecycleActive=false;
      m_candidateDue=false;
      m_breakEvenInactive=false;
      m_quoteSequenceMatched=false;
      m_quoteFresh=false;
      m_noPendingExecution=false;
      m_profileBindingMatched=false;
      m_snapshotConsistent=false;
      m_stopValidationPassed=false;
      m_idempotencyPassed=false;
      m_dryRunAuthorized=false;
      m_accountEligible=false;
      m_allOrNothingSatisfied=false;
     }

   CBreakEvenStopLossModificationRequest Request(void) const { return m_request; }
   bool              LifecycleActive(void) const { return m_lifecycleActive; }
   bool              CandidateDue(void) const { return m_candidateDue; }
   bool              BreakEvenInactive(void) const { return m_breakEvenInactive; }
   bool              QuoteSequenceMatched(void) const { return m_quoteSequenceMatched; }
   bool              QuoteFresh(void) const { return m_quoteFresh; }
   bool              NoPendingExecution(void) const { return m_noPendingExecution; }
   bool              ProfileBindingMatched(void) const { return m_profileBindingMatched; }
   bool              SnapshotConsistent(void) const { return m_snapshotConsistent; }
   bool              StopValidationPassed(void) const { return m_stopValidationPassed; }
   bool              IdempotencyPassed(void) const { return m_idempotencyPassed; }
   bool              DryRunAuthorized(void) const { return m_dryRunAuthorized; }
   bool              AccountEligible(void) const { return m_accountEligible; }
   bool              AllOrNothingSatisfied(void) const { return m_allOrNothingSatisfied; }

   static CBreakEvenModificationAudit Create(const CBreakEvenStopLossModificationRequest &request,
                                             const bool lifecycleActive,
                                             const bool candidateDue,
                                             const bool breakEvenInactive,
                                             const bool quoteSequenceMatched,
                                             const bool quoteFresh,
                                             const bool noPendingExecution,
                                             const bool profileBindingMatched,
                                             const bool snapshotConsistent,
                                             const bool stopValidationPassed,
                                             const bool idempotencyPassed,
                                             const bool dryRunAuthorized,
                                             const bool accountEligible,
                                             const bool allOrNothingSatisfied)
     {
      CBreakEvenModificationAudit audit;
      audit.m_request=request;
      audit.m_lifecycleActive=lifecycleActive;
      audit.m_candidateDue=candidateDue;
      audit.m_breakEvenInactive=breakEvenInactive;
      audit.m_quoteSequenceMatched=quoteSequenceMatched;
      audit.m_quoteFresh=quoteFresh;
      audit.m_noPendingExecution=noPendingExecution;
      audit.m_profileBindingMatched=profileBindingMatched;
      audit.m_snapshotConsistent=snapshotConsistent;
      audit.m_stopValidationPassed=stopValidationPassed;
      audit.m_idempotencyPassed=idempotencyPassed;
      audit.m_dryRunAuthorized=dryRunAuthorized;
      audit.m_accountEligible=accountEligible;
      audit.m_allOrNothingSatisfied=allOrNothingSatisfied;
      return audit;
     }
  };

#endif
