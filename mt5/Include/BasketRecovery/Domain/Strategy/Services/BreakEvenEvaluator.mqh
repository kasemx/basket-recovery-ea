#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_BREAK_EVEN_EVALUATOR_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_BREAK_EVEN_EVALUATOR_MQH

#include <BasketRecovery/Domain/Strategy/Context/StrategyEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecisionSet.mqh>

class CBreakEvenEvaluator
  {
private:
   bool              IsTriggerSatisfied(const CStrategyEvaluationContext &context,
                                        const CBreakEvenTrigger &trigger) const
     {
      switch(trigger.Type())
        {
         case BRE_BE_TRIGGER_SPECIFIC_PROFIT_LEVEL:
           {
            CProfitLevelRuntimeState runtimeState;
            if(!context.FindProfitLevelState(trigger.ProfitLevelId(),runtimeState))
               return false;
            return runtimeState.Reached();
           }
         case BRE_BE_TRIGGER_REALIZED_PROFIT:
           {
            if(trigger.HasRealizedProfitUsd())
               return context.RiskContext().RealizedProfitUsd()>=trigger.RealizedProfitUsd();
            if(trigger.HasPercentOfTargetRisk())
              {
               double targetAmount=context.RiskContext().TargetRiskPct();
               return context.RiskContext().RealizedProfitUsd()>=targetAmount*trigger.PercentOfTargetRisk()/100.0;
              }
            return false;
           }
         case BRE_BE_TRIGGER_TARGET_RISK_REACHED:
            return context.RiskContext().TargetRiskReached();
         case BRE_BE_TRIGGER_MANUAL:
            return context.BasketState().ManualBreakEvenRequested();
         default:
            return false;
        }
     }

public:
   CStrategyDecisionSet Evaluate(const CStrategyEvaluationContext &context) const
     {
      CStrategyDecisionSet decisions=CStrategyDecisionSet::Create();
      CBreakEvenPlan plan=context.Profile().BreakEvenPlan();

      for(int i=0;i<plan.RuleCount();i++)
        {
         CBreakEvenRule rule=plan.RuleAt(i);
         if(!rule.Enabled())
            continue;
         if(rule.RunOnce() && context.BasketState().HasExecutedBreakEvenRule(rule.RuleId()))
            continue;
         if(!IsTriggerSatisfied(context,rule.Trigger()))
            continue;

         string baseKey="be:"+context.BasketState().BasketId().Value()+":rule:"+rule.RuleId();
         for(int actionIndex=0;actionIndex<rule.ActionCount();actionIndex++)
           {
            CBreakEvenAction action=rule.ActionAt(actionIndex);
            switch(action.Type())
              {
               case BRE_BE_ACTION_MOVE_SL_TO_AVERAGE:
                 {
                  CMoveBreakEvenDecision moveDecision=CMoveBreakEvenDecision::CreateAverage(baseKey+":move_avg",
                                                                                            rule.RuleId(),
                                                                                            action.BufferPips(),
                                                                                            action.IncludeSpread());
                  decisions.Add(CStrategyDecision::FromMoveBreakEven(moveDecision));
                  break;
                 }
               case BRE_BE_ACTION_MOVE_SL_WITH_OFFSET:
                 {
                  CMoveBreakEvenDecision moveDecision=CMoveBreakEvenDecision::CreateOffset(baseKey+":move_offset",
                                                                                           rule.RuleId(),
                                                                                           action.SlOffsetPips());
                  decisions.Add(CStrategyDecision::FromMoveBreakEven(moveDecision));
                  break;
                 }
               case BRE_BE_ACTION_DISABLE_RECOVERY:
                 {
                  CDisableRecoveryDecision disableDecision=CDisableRecoveryDecision::Create(baseKey+":disable_recovery",
                                                                                            rule.RuleId(),
                                                                                            true);
                  decisions.Add(CStrategyDecision::FromDisableRecovery(disableDecision));
                  break;
                 }
               default:
                 {
                  CNoActionDecision warning=CNoActionDecision::Create(baseKey+":unsupported:"+IntegerToString(actionIndex),
                                                                      "Unsupported break-even action type");
                  decisions.Add(CStrategyDecision::FromNoAction(warning));
                  break;
                 }
              }
           }
        }

      return decisions;
     }
  };

#endif
