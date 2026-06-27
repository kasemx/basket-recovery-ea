#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_RECOVERY_PLAN_RESOLVER_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_RECOVERY_PLAN_RESOLVER_MQH

#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryStep.mqh>

class CRecoveryPlanResolution
  {
private:
   bool           m_supported;
   bool           m_hasStep;
   CRecoveryStep  m_step;
   string         m_reason;

public:
                     CRecoveryPlanResolution(void) {}

                     CRecoveryPlanResolution(const CRecoveryPlanResolution &other)
     {
      m_supported=other.m_supported;
      m_hasStep=other.m_hasStep;
      m_step=other.m_step;
      m_reason=other.m_reason;
     }

   bool           Supported(void) const { return m_supported; }
   bool           HasStep(void) const { return m_hasStep; }
   CRecoveryStep  Step(void) const { return m_step; }
   string         Reason(void) const { return m_reason; }

   static CRecoveryPlanResolution Unsupported(const string reason)
     {
      CRecoveryPlanResolution resolution;
      resolution.m_supported=false;
      resolution.m_hasStep=false;
      resolution.m_reason=reason;
      return resolution;
     }

   static CRecoveryPlanResolution Resolved(const CRecoveryStep &step)
     {
      CRecoveryPlanResolution resolution;
      resolution.m_supported=true;
      resolution.m_hasStep=true;
      resolution.m_step=step;
      resolution.m_reason="";
      return resolution;
     }

   static CRecoveryPlanResolution NoMoreSteps(void)
     {
      CRecoveryPlanResolution resolution;
      resolution.m_supported=true;
      resolution.m_hasStep=false;
      resolution.m_reason="No more recovery steps";
      return resolution;
     }
  };

class CRecoveryPlanResolver
  {
private:
   CRecoveryStep     FindCustomStep(const CRecoveryPlan &plan,const int stepIndex) const
     {
      for(int i=0;i<plan.StepCount();i++)
        {
         CRecoveryStep step=plan.StepAt(i);
         if(step.StepIndex()==stepIndex)
            return step;
        }
      return CRecoveryStep::Create(0,0.0,0.0);
     }

   bool              IsStepIndexValid(const CRecoveryPlan &plan,const int stepIndex) const
     {
      if(plan.HasMaxSteps() && stepIndex>plan.MaxSteps())
         return false;
      return true;
     }

public:
   CRecoveryPlanResolution ResolveNextStep(const CRecoveryPlan &plan,const int currentRecoveryStepIndex) const
     {
      int nextStepIndex=currentRecoveryStepIndex+1;
      if(!IsStepIndexValid(plan,nextStepIndex))
         return CRecoveryPlanResolution::NoMoreSteps();

      switch(plan.Algorithm())
        {
         case BRE_RECOVERY_ALGORITHM_CUSTOM:
           {
            CRecoveryStep step=FindCustomStep(plan,nextStepIndex);
            if(step.StepIndex()<=0)
               return CRecoveryPlanResolution::NoMoreSteps();
            return CRecoveryPlanResolution::Resolved(step);
           }
         case BRE_RECOVERY_ALGORITHM_CONSTANT:
           {
            CRecoveryStep step=CRecoveryStep::Create(nextStepIndex,
                                                     plan.ConstantDistancePips()*nextStepIndex,
                                                     plan.ConstantLot());
            return CRecoveryPlanResolution::Resolved(step);
           }
         case BRE_RECOVERY_ALGORITHM_LINEAR:
           {
            double distance=plan.ConstantDistancePips()+(nextStepIndex-1)*plan.LinearDistanceIncrement();
            double lot=plan.ConstantLot()+(nextStepIndex-1)*plan.LinearLotIncrement();
            CRecoveryStep step=CRecoveryStep::Create(nextStepIndex,distance,lot);
            return CRecoveryPlanResolution::Resolved(step);
           }
         case BRE_RECOVERY_ALGORITHM_PROGRESSIVE:
           {
            double distanceFactor=plan.ProgressiveDistanceFactor();
            if(distanceFactor<=0.0)
               distanceFactor=1.0;
            double lotFactor=plan.ProgressiveLotFactor();
            if(lotFactor<=0.0)
               lotFactor=1.0;
            double distance=plan.ConstantDistancePips()*nextStepIndex*distanceFactor;
            double lot=plan.ConstantLot()*nextStepIndex*lotFactor;
            CRecoveryStep step=CRecoveryStep::Create(nextStepIndex,distance,lot);
            return CRecoveryPlanResolution::Resolved(step);
           }
         case BRE_RECOVERY_ALGORITHM_ATR:
            return CRecoveryPlanResolution::Unsupported("ATR recovery algorithm is not supported yet");
         case BRE_RECOVERY_ALGORITHM_VOLATILITY:
            return CRecoveryPlanResolution::Unsupported("Volatility recovery algorithm is not supported yet");
         default:
            return CRecoveryPlanResolution::Unsupported("Recovery algorithm is not configured");
        }
     }
  };

#endif
