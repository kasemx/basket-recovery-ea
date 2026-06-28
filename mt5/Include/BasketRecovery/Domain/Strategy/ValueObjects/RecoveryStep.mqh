#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_RECOVERY_STEP_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_RECOVERY_STEP_MQH

class CRecoveryStep
  {
private:
   int    m_stepIndex;
   double m_distancePips;
   double m_lot;
   bool   m_lotMultiplierEnabled;
   double m_lotMultiplier;
   bool   m_usesRiskBudgetVolume;

public:
                     CRecoveryStep(void)
     {
      m_lotMultiplierEnabled=false;
      m_lotMultiplier=1.0;
      m_usesRiskBudgetVolume=false;
     }

                     CRecoveryStep(const CRecoveryStep &other)
     {
      m_stepIndex=other.m_stepIndex;
      m_distancePips=other.m_distancePips;
      m_lot=other.m_lot;
      m_lotMultiplierEnabled=other.m_lotMultiplierEnabled;
      m_lotMultiplier=other.m_lotMultiplier;
      m_usesRiskBudgetVolume=other.m_usesRiskBudgetVolume;
     }

   int               StepIndex(void) const { return m_stepIndex; }
   double            DistancePips(void) const { return m_distancePips; }
   double            Lot(void) const { return m_lot; }
   bool              LotMultiplierEnabled(void) const { return m_lotMultiplierEnabled; }
   double            LotMultiplier(void) const { return m_lotMultiplier; }
   bool              UsesRiskBudgetVolume(void) const { return m_usesRiskBudgetVolume; }

   static CRecoveryStep Create(const int stepIndex,const double distancePips,const double lot)
     {
      CRecoveryStep step;
      step.m_stepIndex=stepIndex;
      step.m_distancePips=distancePips;
      step.m_lot=lot;
      return step;
     }

   static CRecoveryStep CreateWithVolumePolicy(const int stepIndex,
                                               const double distancePips,
                                               const double lot,
                                               const bool lotMultiplierEnabled,
                                               const double lotMultiplier,
                                               const bool usesRiskBudgetVolume)
     {
      CRecoveryStep step;
      step.m_stepIndex=stepIndex;
      step.m_distancePips=distancePips;
      step.m_lot=lot;
      step.m_lotMultiplierEnabled=lotMultiplierEnabled;
      step.m_lotMultiplier=lotMultiplier;
      step.m_usesRiskBudgetVolume=usesRiskBudgetVolume;
      return step;
     }
  };

#endif
