#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_RECOVERY_STEP_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_RECOVERY_STEP_MQH

class CRecoveryStep
  {
private:
   int    m_stepIndex;
   double m_distancePips;
   double m_lot;

public:
                     CRecoveryStep(void) {}

                     CRecoveryStep(const CRecoveryStep &other)
     {
      m_stepIndex=other.m_stepIndex;
      m_distancePips=other.m_distancePips;
      m_lot=other.m_lot;
     }

   int               StepIndex(void) const { return m_stepIndex; }
   double            DistancePips(void) const { return m_distancePips; }
   double            Lot(void) const { return m_lot; }

   static CRecoveryStep Create(const int stepIndex,const double distancePips,const double lot)
     {
      CRecoveryStep step;
      step.m_stepIndex=stepIndex;
      step.m_distancePips=distancePips;
      step.m_lot=lot;
      return step;
     }
  };

#endif
