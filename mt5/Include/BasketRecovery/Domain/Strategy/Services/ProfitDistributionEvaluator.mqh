#ifndef BRE_DOM_PROFIT_DISTRIBUTION_EVALUATOR_MQH
#define BRE_DOM_PROFIT_DISTRIBUTION_EVALUATOR_MQH

#include <BasketRecovery/Domain/Strategy/Context/StrategyEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecisionSet.mqh>
#include <BasketRecovery/Domain/Strategy/Services/CloseOrderingResolver.mqh>

class CProfitDistributionEvaluator
  {
private:
   CCloseOrderingResolver m_closeOrdering;

   bool              IsLevelReady(const CStrategyEvaluationContext &context,
                                  const CProfitLevel &level,
                                  const CProfitLevelRuntimeState &runtimeState) const
     {
      if(!level.Enabled() || runtimeState.Executed())
         return false;
      if(!runtimeState.Reached())
         return false;
      if(context.Profile().ProfitDistributionPlan().RequireFloatingProfitPositive() &&
         context.FloatingProfitUsd()<=0.0)
         return false;
      return true;
     }

   void              CollectOpenPositions(const CStrategyEvaluationContext &context,CPositionRuntimeView &buffer[],int &count) const
     {
      count=0;
      ArrayResize(buffer,context.PositionCount());
      for(int i=0;i<context.PositionCount();i++)
        {
         buffer[count]=context.PositionAt(i);
         count++;
        }
     }

public:
   CStrategyDecisionSet Evaluate(const CStrategyEvaluationContext &context) const
     {
      CStrategyDecisionSet decisions=CStrategyDecisionSet::Create();
      CProfitDistributionPlan plan=context.Profile().ProfitDistributionPlan();
      CPositionRuntimeView openPositions[];
      int openCount=0;
      CollectOpenPositions(context,openPositions,openCount);
      if(openCount<=0)
         return decisions;

      for(int i=0;i<plan.LevelCount();i++)
        {
         CProfitLevel level=plan.LevelAt(i);
         CProfitLevelRuntimeState runtimeState;
         if(!context.FindProfitLevelState(level.LevelId(),runtimeState))
            runtimeState=CProfitLevelRuntimeState::Create(level.LevelId(),false,false,0.0,false);

         if(!IsLevelReady(context,level,runtimeState))
            continue;

         ulong tickets[];
         ENUM_BRE_CLOSE_MODE closeMode=level.CloseMode();
         if(closeMode==BRE_CLOSE_MODE_NONE)
            closeMode=plan.DefaultCloseMode();

         int ticketCount=m_closeOrdering.ResolveTickets(closeMode,
                                                        context.BasketState().Direction(),
                                                        openPositions,
                                                        openCount,
                                                        level.ClosePercent(),
                                                        tickets);
         if(ticketCount<=0)
            continue;

         string idempotencyKey="profit:"+context.BasketState().BasketId().Value()+":level:"+level.LevelId();
         CClosePositionsDecision closeDecision=CClosePositionsDecision::Create(idempotencyKey,
                                                                               level.LevelId(),
                                                                               level.ClosePercent(),
                                                                               closeMode,
                                                                               level.PartialClose(),
                                                                               tickets,
                                                                               ticketCount);
         decisions.Add(CStrategyDecision::FromClosePositions(closeDecision));
        }

      return decisions;
     }
  };

#endif
