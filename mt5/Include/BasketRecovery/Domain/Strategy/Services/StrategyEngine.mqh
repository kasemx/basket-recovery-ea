#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_ENGINE_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_ENGINE_MQH

#include <BasketRecovery/Domain/Strategy/Context/StrategyEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecisionSet.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ExecutionZoneResolver.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryPlanResolver.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ProfitDistributionEvaluator.mqh>
#include <BasketRecovery/Domain/Strategy/Services/BreakEvenEvaluator.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RiskReductionEvaluator.mqh>

class CStrategyEngine
  {
private:
   CExecutionZoneResolver       m_zoneResolver;
   CRecoveryPlanResolver        m_recoveryResolver;
   CProfitDistributionEvaluator m_profitEvaluator;
   CBreakEvenEvaluator          m_breakEvenEvaluator;
   CRiskReductionEvaluator      m_riskReductionEvaluator;

   double                       CurrentAdversePrice(const CStrategyEvaluationContext &context) const
     {
      if(context.BasketState().Direction()==BRE_DIRECTION_SELL)
         return context.Market().Bid();
      if(context.BasketState().Direction()==BRE_DIRECTION_BUY)
         return context.Market().Ask();
      return context.Market().Bid();
     }

public:
   CStrategyDecisionSet         EvaluateRecovery(const CStrategyEvaluationContext &context) const
     {
      CStrategyDecisionSet decisions=CStrategyDecisionSet::Create();
      CRecoveryPlan recoveryPlan=context.Profile().RecoveryPlan();

      if(context.BasketState().RecoveryDisabled())
         return decisions;
      if(recoveryPlan.DisableAfterBreakEven() && context.BasketState().BreakEvenActivated())
         return decisions;
      if(!context.RiskContext().CanOpenRecovery())
         return decisions;

      CRecoveryPlanResolution resolution=m_recoveryResolver.ResolveNextStep(recoveryPlan,
                                                                            context.BasketState().CurrentRecoveryStepIndex());
      if(!resolution.Supported() || !resolution.HasStep())
         return decisions;

      CRecoveryStep step=resolution.Step();
      if(context.AdverseMovePips()<step.DistancePips())
         return decisions;

      CEffectiveRecoveryZone zone=m_zoneResolver.Resolve(context.Profile().ExecutionZone(),
                                                           context.BasketState().Direction(),
                                                           context.BasketState().SignalRangeLow(),
                                                           context.BasketState().SignalRangeHigh(),
                                                           context.Market().PipSize());
      double currentPrice=CurrentAdversePrice(context);
      if(!zone.ContainsPrice(currentPrice))
         return decisions;

      string idempotencyKey="recovery:"+context.BasketState().BasketId().Value()+":step:"+IntegerToString(step.StepIndex());
      COpenRecoveryPositionDecision openDecision=COpenRecoveryPositionDecision::Create(idempotencyKey,
                                                                                     step.StepIndex(),
                                                                                     step.DistancePips(),
                                                                                     step.Lot(),
                                                                                     currentPrice,
                                                                                     BRE_TRADE_ROLE_RECOVERY);
      decisions.Add(CStrategyDecision::FromOpenRecovery(openDecision));
      return decisions;
     }

   CStrategyDecisionSet         EvaluateProfitDistribution(const CStrategyEvaluationContext &context) const
     {
      return m_profitEvaluator.Evaluate(context);
     }

   CStrategyDecisionSet         EvaluateBreakEven(const CStrategyEvaluationContext &context) const
     {
      return m_breakEvenEvaluator.Evaluate(context);
     }

   CStrategyDecisionSet         EvaluateRiskReduction(const CStrategyEvaluationContext &context) const
     {
      return m_riskReductionEvaluator.Evaluate(context);
     }

   CStrategyDecisionSet         EvaluateAll(const CStrategyEvaluationContext &context) const
     {
      CStrategyDecisionSet all=CStrategyDecisionSet::Create();
      all.Merge(EvaluateRiskReduction(context));
      all.Merge(EvaluateRecovery(context));
      all.Merge(EvaluateProfitDistribution(context));
      all.Merge(EvaluateBreakEven(context));
      return all;
     }
  };

#endif
