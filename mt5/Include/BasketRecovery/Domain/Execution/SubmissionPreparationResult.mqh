#ifndef BRE_DOMAIN_SUBMISSION_PREPARATION_RESULT_MQH
#define BRE_DOMAIN_SUBMISSION_PREPARATION_RESULT_MQH

#include <BasketRecovery/Domain/Execution/BrokerSubmissionEnvelope.mqh>
#include <BasketRecovery/Domain/Execution/SubmissionPreparationFailureReason.mqh>

class CSubmissionPreparationResult
  {
private:
   bool                                      m_success;
   CBrokerSubmissionEnvelope                 m_envelope;
   ENUM_BRE_SUBMISSION_PREPARATION_FAILURE_REASON m_failureReason;
   string                                    m_failureMessage;
   bool                                      m_reusedExistingEnvelope;

public:
                     CSubmissionPreparationResult(void)
     {
      m_success=false;
      m_failureReason=BRE_PREP_FAIL_NONE;
      m_failureMessage="";
      m_reusedExistingEnvelope=false;
     }

   bool              IsSuccess(void) const { return m_success; }
   CBrokerSubmissionEnvelope Envelope(void) const { return m_envelope; }
   ENUM_BRE_SUBMISSION_PREPARATION_FAILURE_REASON FailureReason(void) const { return m_failureReason; }
   string            FailureMessage(void) const { return m_failureMessage; }
   bool              ReusedExistingEnvelope(void) const { return m_reusedExistingEnvelope; }

   static CSubmissionPreparationResult Ok(const CBrokerSubmissionEnvelope &envelope,const bool reusedExisting=false)
     {
      CSubmissionPreparationResult result;
      result.m_success=true;
      result.m_envelope=envelope;
      result.m_reusedExistingEnvelope=reusedExisting;
      return result;
     }

   static CSubmissionPreparationResult Fail(const ENUM_BRE_SUBMISSION_PREPARATION_FAILURE_REASON reason,
                                            const string message)
     {
      CSubmissionPreparationResult result;
      result.m_success=false;
      result.m_failureReason=reason;
      result.m_failureMessage=message;
      return result;
     }
  };

#endif
