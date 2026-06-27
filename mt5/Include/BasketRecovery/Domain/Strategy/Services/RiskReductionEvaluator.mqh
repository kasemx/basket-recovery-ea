#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_RISK_REDUCTION_EVALUATOR_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_RISK_REDUCTION_EVALUATOR_MQH

#include <BasketRecovery/Domain/Strategy/Context/StrategyEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecisionSet.mqh>
#include <BasketRecovery/Domain/Strategy/Services/CloseOrderingResolver.mqh>

class CRiskReductionEvaluator
  {
private:
   CCloseOrderingResolver m_closeOrdering;

   ENUM_BRE_CLOSE_MODE MapReductionMode(const ENUM_BRE_RISK_REDUCTION_MODE mode) const
     {
      switch(mode)
        {
         case BRE_RISK_REDUCTION_MODE_WORST_ENTRY: return BRE_CLOSE_MODE_WORST_ENTRY_FIRST;
         case BRE_RISK_REDUCTION_MODE_BEST_ENTRY: return BRE_CLOSE_MODE_BEST_ENTRY_FIRST;
         case BRE_RISK_REDUCTION_MODE_FIFO: return BRE_CLOSE_MODE_FIFO;
         case BRE_RISK_REDUCTION_MODE_PROFIT_BASED: return BRE_CLOSE_MODE_PROFIT_BASED;
         case BRE_RISK_REDUCTION_MODE_RISK_BASED: return BRE_CLOSE_MODE_RISK_BASED;
         default: return BRE_CLOSE_MODE_WORST_ENTRY_FIRST;
        }
     }

public:
   CStrategyDecisionSet Evaluate(const CStrategyEvaluationContext &context) const
     {
      CStrategyDecisionSet decisions=CStrategyDecisionSet::Create();
      CRiskPlan riskPlan=context.Profile().RiskPlan();
      double threshold=riskPlan.TargetRiskPct();
      if(context.RiskContext().CurrentRiskPct()<=threshold)
         return decisions;

      CPositionRuntimeView positions[];
      int count=context.PositionCount();
      ArrayResize(positions,count);
      for(int i=0;i<count;i++)
         positions[i]=context.PositionAt(i);
      if(count<=0)
         return decisions;

      ulong tickets[];
      ENUM_BRE_CLOSE_MODE closeMode=MapReductionMode(riskPlan.RiskReductionMode());
      int ticketCount=m_closeOrdering.ResolveTickets(closeMode,
                                                     context.BasketState().Direction(),
                                                     positions,
                                                     count,
                                                     100.0,
                                                     tickets);
      if(ticketCount<=0)
         return decisions;

      string idempotencyKey="riskreduce:"+context.BasketState().BasketId().Value();
      CReduceRiskDecision reduceDecision=CReduceRiskDecision::Create(idempotencyKey,
                                                                     riskPlan.RiskReductionMode(),
                                                                     tickets,
                                                                     1);
      decisions.Add(CStrategyDecision::FromReduceRisk(reduceDecision));
      return decisions;
     }
  };

#endif
