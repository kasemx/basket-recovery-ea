#ifndef BRE_DOMAIN_BREAK_EVEN_CANDIDATE_TRIGGER_EVALUATOR_MQH
#define BRE_DOMAIN_BREAK_EVEN_CANDIDATE_TRIGGER_EVALUATOR_MQH

#include <BasketRecovery/Domain/Strategy/Context/BreakEvenEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenRule.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/BreakEvenTriggerType.mqh>

class CBreakEvenCandidateTriggerEvaluation
  {
private:
   ENUM_BRE_BREAK_EVEN_CANDIDATE_TRIGGER_TYPE m_triggerType;
   double                                     m_triggerValue;
   bool                                       m_supported;
   bool                                       m_reached;

public:
                     CBreakEvenCandidateTriggerEvaluation(void)
     {
      m_triggerType=BRE_BE_CANDIDATE_TRIGGER_NONE;
      m_triggerValue=0.0;
      m_supported=false;
      m_reached=false;
     }

   ENUM_BRE_BREAK_EVEN_CANDIDATE_TRIGGER_TYPE TriggerType(void) const { return m_triggerType; }
   double                                     TriggerValue(void) const { return m_triggerValue; }
   bool                                       Supported(void) const { return m_supported; }
   bool                                       Reached(void) const { return m_reached; }

   static CBreakEvenCandidateTriggerEvaluation Unsupported(void)
     {
      return CBreakEvenCandidateTriggerEvaluation::Create(BRE_BE_CANDIDATE_TRIGGER_NONE,0.0,false,false);
     }

   static CBreakEvenCandidateTriggerEvaluation Create(const ENUM_BRE_BREAK_EVEN_CANDIDATE_TRIGGER_TYPE triggerType,
                                                      const double triggerValue,
                                                      const bool supported,
                                                      const bool reached)
     {
      CBreakEvenCandidateTriggerEvaluation evaluation;
      evaluation.m_triggerType=triggerType;
      evaluation.m_triggerValue=triggerValue;
      evaluation.m_supported=supported;
      evaluation.m_reached=reached;
      return evaluation;
     }
  };

class CBreakEvenCandidateTriggerEvaluator
  {
private:
   static bool       IsProfitLevelCompleted(const CBreakEvenEvaluationContext &ctx,
                                            const string profitLevelId)
     {
      CBasketProfitLevelProgress progress;
      if(ctx.FindLevelProgress(profitLevelId,progress) && progress.CloseCompleted())
         return true;

      CProfitLevelRuntimeState runtimeState;
      if(ctx.FindProfitLevelState(profitLevelId,runtimeState) && runtimeState.Reached())
         return true;
      return false;
     }

   static bool       IsRiskReductionTrigger(const CBreakEvenTrigger &trigger)
     {
      return trigger.Type()==BRE_BE_TRIGGER_SPECIFIC_BASKET_STATE &&
             trigger.BasketState()=="RISK_REDUCTION_COMPLETED";
     }

public:
   static CBreakEvenCandidateTriggerEvaluation Evaluate(const CBreakEvenEvaluationContext &ctx,
                                                        const CBreakEvenRule &rule)
     {
      CBreakEvenTrigger trigger=rule.Trigger();
      switch(trigger.Type())
        {
         case BRE_BE_TRIGGER_FLOATING_PROFIT:
           {
            if(trigger.HasFloatingProfitUsd())
               return CBreakEvenCandidateTriggerEvaluation::Create(
                  BRE_BE_CANDIDATE_TRIGGER_FLOATING_PROFIT_MONEY,
                  trigger.FloatingProfitUsd(),true,
                  ctx.FloatingProfitUsd()>=trigger.FloatingProfitUsd());
            if(trigger.HasPercentOfTargetRisk())
              {
               if(ctx.TargetRiskMoney()<=0.0)
                  return CBreakEvenCandidateTriggerEvaluation::Create(
                     BRE_BE_CANDIDATE_TRIGGER_FLOATING_PROFIT_PCT_TARGET_RISK,
                     trigger.PercentOfTargetRisk(),true,false);
               double threshold=ctx.TargetRiskMoney()*trigger.PercentOfTargetRisk()/100.0;
               return CBreakEvenCandidateTriggerEvaluation::Create(
                  BRE_BE_CANDIDATE_TRIGGER_FLOATING_PROFIT_PCT_TARGET_RISK,
                  trigger.PercentOfTargetRisk(),true,
                  ctx.FloatingProfitUsd()>=threshold);
              }
            return CBreakEvenCandidateTriggerEvaluation::Unsupported();
           }
         case BRE_BE_TRIGGER_REALIZED_PROFIT:
           {
            if(trigger.HasRealizedProfitUsd())
               return CBreakEvenCandidateTriggerEvaluation::Create(
                  BRE_BE_CANDIDATE_TRIGGER_REALIZED_PROFIT_MONEY,
                  trigger.RealizedProfitUsd(),true,
                  ctx.RealizedProfitUsd()>=trigger.RealizedProfitUsd());
            if(trigger.HasPercentOfTargetRisk())
              {
               if(ctx.TargetRiskMoney()<=0.0)
                  return CBreakEvenCandidateTriggerEvaluation::Create(
                     BRE_BE_CANDIDATE_TRIGGER_FLOATING_PROFIT_PCT_TARGET_RISK,
                     trigger.PercentOfTargetRisk(),true,false);
               double threshold=ctx.TargetRiskMoney()*trigger.PercentOfTargetRisk()/100.0;
               return CBreakEvenCandidateTriggerEvaluation::Create(
                  BRE_BE_CANDIDATE_TRIGGER_REALIZED_PROFIT_MONEY,
                  trigger.PercentOfTargetRisk(),true,
                  ctx.RealizedProfitUsd()>=threshold);
              }
            return CBreakEvenCandidateTriggerEvaluation::Unsupported();
           }
         case BRE_BE_TRIGGER_SPECIFIC_PROFIT_LEVEL:
           {
            bool completed=IsProfitLevelCompleted(ctx,trigger.ProfitLevelId());
            return CBreakEvenCandidateTriggerEvaluation::Create(
               BRE_BE_CANDIDATE_TRIGGER_PROFIT_LEVEL_COMPLETED,0.0,true,completed);
           }
         case BRE_BE_TRIGGER_MANUAL:
            return CBreakEvenCandidateTriggerEvaluation::Create(
               BRE_BE_CANDIDATE_TRIGGER_MANUAL_EVENT,0.0,true,ctx.ManualBreakEvenRequested());
         case BRE_BE_TRIGGER_SPECIFIC_BASKET_STATE:
           {
            if(IsRiskReductionTrigger(trigger))
               return CBreakEvenCandidateTriggerEvaluation::Create(
                  BRE_BE_CANDIDATE_TRIGGER_RISK_REDUCTION_COMPLETED,0.0,true,ctx.RiskReductionCompleted());
            return CBreakEvenCandidateTriggerEvaluation::Unsupported();
           }
         default:
            return CBreakEvenCandidateTriggerEvaluation::Unsupported();
        }
     }
  };

#endif
