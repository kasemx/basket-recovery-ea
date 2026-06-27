#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_RECOVERY_PLAN_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_RECOVERY_PLAN_MQH

#include <BasketRecovery/Domain/Strategy/Enums/RecoveryAlgorithm.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryStep.mqh>

class CRecoveryPlan
  {
private:
   ENUM_BRE_RECOVERY_ALGORITHM m_algorithm;
   int                         m_maxSteps;
   bool                        m_hasMaxSteps;
   double                      m_constantDistancePips;
   double                      m_constantLot;
   double                      m_linearDistanceIncrement;
   double                      m_linearLotIncrement;
   double                      m_progressiveDistanceFactor;
   double                      m_progressiveLotFactor;
   bool                        m_allowDuringProfitTaking;
   bool                        m_disableAfterBreakEven;
   int                         m_initialPositionCount;
   double                      m_initialLotSize;
   CRecoveryStep               m_steps[];

                     CRecoveryPlan(void) {}

public:
   ENUM_BRE_RECOVERY_ALGORITHM Algorithm(void) const { return m_algorithm; }
   int                         MaxSteps(void) const { return m_maxSteps; }
   bool                        HasMaxSteps(void) const { return m_hasMaxSteps; }
   double                      ConstantDistancePips(void) const { return m_constantDistancePips; }
   double                      ConstantLot(void) const { return m_constantLot; }
   double                      LinearDistanceIncrement(void) const { return m_linearDistanceIncrement; }
   double                      LinearLotIncrement(void) const { return m_linearLotIncrement; }
   double                      ProgressiveDistanceFactor(void) const { return m_progressiveDistanceFactor; }
   double                      ProgressiveLotFactor(void) const { return m_progressiveLotFactor; }
   bool                        AllowDuringProfitTaking(void) const { return m_allowDuringProfitTaking; }
   bool                        DisableAfterBreakEven(void) const { return m_disableAfterBreakEven; }
   int                         InitialPositionCount(void) const { return m_initialPositionCount; }
   double                      InitialLotSize(void) const { return m_initialLotSize; }
   int                         StepCount(void) const { return ArraySize(m_steps); }

   CRecoveryStep               StepAt(const int index) const
     {
      if(index<0 || index>=ArraySize(m_steps))
         return CRecoveryStep::Create(0,0.0,0.0);
      return m_steps[index];
     }

   void                        CopyStepsTo(CRecoveryStep &outSteps[]) const
     {
      int count=ArraySize(m_steps);
      ArrayResize(outSteps,count);
      for(int i=0;i<count;i++)
         outSteps[i]=m_steps[i];
     }

   static CRecoveryPlan        CreateConstant(const double distancePips,
                                              const double lot,
                                              const int maxSteps,
                                              const bool hasMaxSteps,
                                              const bool allowDuringProfitTaking,
                                              const bool disableAfterBreakEven,
                                              const int initialPositionCount,
                                              const double initialLotSize)
     {
      CRecoveryPlan plan;
      plan.m_algorithm=BRE_RECOVERY_ALGORITHM_CONSTANT;
      plan.m_constantDistancePips=distancePips;
      plan.m_constantLot=lot;
      plan.m_maxSteps=maxSteps;
      plan.m_hasMaxSteps=hasMaxSteps;
      plan.m_allowDuringProfitTaking=allowDuringProfitTaking;
      plan.m_disableAfterBreakEven=disableAfterBreakEven;
      plan.m_initialPositionCount=initialPositionCount;
      plan.m_initialLotSize=initialLotSize;
      ArrayResize(plan.m_steps,0);
      return plan;
     }

   static CRecoveryPlan        CreateCustom(const CRecoveryStep &steps[],
                                            const int stepCount,
                                            const bool allowDuringProfitTaking,
                                            const bool disableAfterBreakEven,
                                            const int initialPositionCount,
                                            const double initialLotSize)
     {
      CRecoveryPlan plan;
      plan.m_algorithm=BRE_RECOVERY_ALGORITHM_CUSTOM;
      plan.m_hasMaxSteps=false;
      plan.m_allowDuringProfitTaking=allowDuringProfitTaking;
      plan.m_disableAfterBreakEven=disableAfterBreakEven;
      plan.m_initialPositionCount=initialPositionCount;
      plan.m_initialLotSize=initialLotSize;
      ArrayResize(plan.m_steps,stepCount);
      for(int i=0;i<stepCount;i++)
         plan.m_steps[i]=steps[i];
      return plan;
     }

   static CRecoveryPlan        CreateLinear(const double baseDistancePips,
                                            const double distanceIncrementPips,
                                            const double baseLot,
                                            const double lotIncrement,
                                            const int maxSteps,
                                            const bool hasMaxSteps,
                                            const bool allowDuringProfitTaking,
                                            const bool disableAfterBreakEven,
                                            const int initialPositionCount,
                                            const double initialLotSize)
     {
      CRecoveryPlan plan;
      plan.m_algorithm=BRE_RECOVERY_ALGORITHM_LINEAR;
      plan.m_constantDistancePips=baseDistancePips;
      plan.m_linearDistanceIncrement=distanceIncrementPips;
      plan.m_constantLot=baseLot;
      plan.m_linearLotIncrement=lotIncrement;
      plan.m_maxSteps=maxSteps;
      plan.m_hasMaxSteps=hasMaxSteps;
      plan.m_allowDuringProfitTaking=allowDuringProfitTaking;
      plan.m_disableAfterBreakEven=disableAfterBreakEven;
      plan.m_initialPositionCount=initialPositionCount;
      plan.m_initialLotSize=initialLotSize;
      ArrayResize(plan.m_steps,0);
      return plan;
     }

   static CRecoveryPlan        CreateProgressive(const double baseDistancePips,
                                                 const double distanceFactor,
                                                 const double baseLot,
                                                 const double lotFactor,
                                                 const int maxSteps,
                                                 const bool hasMaxSteps,
                                                 const bool allowDuringProfitTaking,
                                                 const bool disableAfterBreakEven,
                                                 const int initialPositionCount,
                                                 const double initialLotSize)
     {
      CRecoveryPlan plan;
      plan.m_algorithm=BRE_RECOVERY_ALGORITHM_PROGRESSIVE;
      plan.m_constantDistancePips=baseDistancePips;
      plan.m_progressiveDistanceFactor=distanceFactor;
      plan.m_constantLot=baseLot;
      plan.m_progressiveLotFactor=lotFactor;
      plan.m_maxSteps=maxSteps;
      plan.m_hasMaxSteps=hasMaxSteps;
      plan.m_allowDuringProfitTaking=allowDuringProfitTaking;
      plan.m_disableAfterBreakEven=disableAfterBreakEven;
      plan.m_initialPositionCount=initialPositionCount;
      plan.m_initialLotSize=initialLotSize;
      ArrayResize(plan.m_steps,0);
      return plan;
     }

   static CRecoveryPlan        CreatePlaceholder(const ENUM_BRE_RECOVERY_ALGORITHM algorithm,
                                                 const bool allowDuringProfitTaking,
                                                 const bool disableAfterBreakEven,
                                                 const int initialPositionCount,
                                                 const double initialLotSize)
     {
      CRecoveryPlan plan;
      plan.m_algorithm=algorithm;
      plan.m_hasMaxSteps=false;
      plan.m_allowDuringProfitTaking=allowDuringProfitTaking;
      plan.m_disableAfterBreakEven=disableAfterBreakEven;
      plan.m_initialPositionCount=initialPositionCount;
      plan.m_initialLotSize=initialLotSize;
      ArrayResize(plan.m_steps,0);
      return plan;
     }
  };

#endif
