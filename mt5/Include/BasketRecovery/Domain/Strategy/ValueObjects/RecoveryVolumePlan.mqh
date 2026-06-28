#ifndef BRE_DOMAIN_RECOVERY_VOLUME_PLAN_MQH
#define BRE_DOMAIN_RECOVERY_VOLUME_PLAN_MQH

#include <BasketRecovery/Domain/Strategy/Enums/RecoveryCandidateReason.mqh>

class CRecoveryVolumePlan
  {
private:
   bool                              m_valid;
   double                            m_rawVolume;
   double                            m_normalizedVolume;
   ENUM_BRE_RECOVERY_CANDIDATE_REASON m_reason;

public:
                     CRecoveryVolumePlan(void) {}

   bool              Valid(void) const { return m_valid; }
   double            RawVolume(void) const { return m_rawVolume; }
   double            NormalizedVolume(void) const { return m_normalizedVolume; }
   ENUM_BRE_RECOVERY_CANDIDATE_REASON Reason(void) const { return m_reason; }

   static CRecoveryVolumePlan        ValidPlan(const double rawVolume,const double normalizedVolume)
     {
      CRecoveryVolumePlan plan;
      plan.m_valid=true;
      plan.m_rawVolume=rawVolume;
      plan.m_normalizedVolume=normalizedVolume;
      plan.m_reason=BRE_RECOVERY_CANDIDATE_REASON_NONE;
      return plan;
     }

   static CRecoveryVolumePlan        Invalid(const ENUM_BRE_RECOVERY_CANDIDATE_REASON reason)
     {
      CRecoveryVolumePlan plan;
      plan.m_valid=false;
      plan.m_rawVolume=0.0;
      plan.m_normalizedVolume=0.0;
      plan.m_reason=reason;
      return plan;
     }
  };

#endif
