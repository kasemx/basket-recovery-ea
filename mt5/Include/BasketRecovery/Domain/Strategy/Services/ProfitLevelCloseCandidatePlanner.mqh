#ifndef BRE_DOMAIN_PROFIT_LEVEL_CLOSE_CANDIDATE_PLANNER_MQH
#define BRE_DOMAIN_PROFIT_LEVEL_CLOSE_CANDIDATE_PLANNER_MQH

#include <BasketRecovery/Domain/Strategy/Context/ProfitLevelEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevelCloseCandidate.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ProfitLevelTriggerEvaluator.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ProfitLevelPositionSelector.mqh>
#include <BasketRecovery/Domain/Execution/ProfitCloseCandidateCloseVolumeCalculator.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>

class CProfitLevelCloseCandidatePlanner
  {
private:
   string            BuildIdempotencyKey(const CBasketId &basketId,
                                         const string profitLevelId,
                                         const ulong quoteSequence) const
     {
      return "profit-level-close:"+basketId.Value()+":level:"+profitLevelId+":q:"+IntegerToString((long)quoteSequence);
     }

   CProfitLevelCloseCandidate Blocked(const CProfitLevelEvaluationContext &ctx,
                                      const CProfitLevel &level,
                                      const ENUM_BRE_PROFIT_LEVEL_CLOSE_CANDIDATE_STATUS status,
                                      const ENUM_BRE_PROFIT_LEVEL_CLOSE_REASON reason,
                                      const ENUM_BRE_PROFIT_LEVEL_PROGRESS_STATE progressState,
                                      const ENUM_BRE_PROFIT_LEVEL_TRIGGER_TYPE triggerType,
                                      const double triggerValue) const
     {
      string idempotencyKey=BuildIdempotencyKey(ctx.BasketId(),level.LevelId(),ctx.QuoteSequence());
      CPositionReductionInstruction empty[];
      CProfitLevelCloseAudit audit=CProfitLevelCloseAudit::Create(ctx.BasketId(),
                                                                 ctx.StrategyProfileHash(),
                                                                 ctx.BasketVersion(),
                                                                 level.LevelId(),
                                                                 level.LevelIndex(),
                                                                 triggerType,
                                                                 triggerValue,
                                                                 ctx.FloatingProfitUsd(),
                                                                 level.ClosePercent(),
                                                                 0.0,
                                                                 empty,
                                                                 0,
                                                                 level.CloseMode(),
                                                                 ctx.QuoteSequence(),
                                                                 idempotencyKey,
                                                                 ctx.TimestampUtc(),
                                                                 status,
                                                                 reason,
                                                                 progressState,
                                                                 false);
      return CProfitLevelCloseCandidate::FromAudit(audit);
     }

   bool              IsActiveLifecycle(const ENUM_BRE_BASKET_LIFECYCLE_STATE state) const
     {
      return state==BRE_STATE_ACTIVE;
     }

   bool              IsBlockingLifecycle(const ENUM_BRE_BASKET_LIFECYCLE_STATE state) const
     {
      return state==BRE_STATE_SUSPENDED || state==BRE_STATE_CLOSING;
     }

   double            SumRemainingVolume(const CPositionRuntimeView &positions[],const int positionCount) const
     {
      double total=0.0;
      for(int i=0;i<positionCount;i++)
        {
         if(positions[i].Lot()>0.0)
            total+=positions[i].Lot();
        }
      return total;
     }

   double            EstimateCloseMoney(const CPositionRuntimeView &position,const double closeVolume) const
     {
      if(position.Lot()<=0.0 || closeVolume<=0.0)
         return 0.0;
      return position.FloatingProfit()*(closeVolume/position.Lot());
     }

   bool              BuildReductionsForPlannedCloseVolume(const ENUM_BRE_CLOSE_MODE closeMode,
                                                          const ENUM_BRE_TRADE_DIRECTION direction,
                                                          const CPositionRuntimeView &positions[],
                                                          const int positionCount,
                                                          const double plannedCloseVolume,
                                                          const CSymbolTradingConstraints &constraints,
                                                          CPositionReductionInstruction &reductions[],
                                                          int &reductionCount) const
     {
      reductionCount=0;
      ArrayResize(reductions,0);
      if(positionCount<=0 || plannedCloseVolume<=0.0)
         return false;

      CPositionRuntimeView ordered[];
      int orderedCount=CProfitLevelPositionSelector::SelectOrdered(closeMode,direction,positions,positionCount,ordered);
      if(orderedCount<=0)
         return false;

      double remainingToClose=plannedCloseVolume;
      const double epsilon=CProfitCloseCandidateCloseVolumeCalculator::VolumeComparisonEpsilon(constraints.VolumeStep());

      for(int i=0;i<orderedCount && remainingToClose>epsilon;i++)
        {
         CPositionRuntimeView position=ordered[i];
         if(position.Lot()<=epsilon)
            continue;

         double slice=MathMin(position.Lot(),remainingToClose);
         if(slice<=epsilon)
            continue;

         double estimated=EstimateCloseMoney(position,slice);
         ArrayResize(reductions,reductionCount+1);
         reductions[reductionCount]=CPositionReductionInstruction::Create(position.Ticket(),slice,estimated);
         reductionCount++;
         remainingToClose-=slice;
        }

      return reductionCount>0;
     }

public:
   CProfitLevelCloseCandidate Plan(const CProfitLevelEvaluationContext &ctx,
                                   const bool duplicateQuoteSequence) const
     {
      CProfitDistributionPlan plan=ctx.Profile().ProfitDistributionPlan();
      if(!ctx.ProfileValid() || plan.LevelCount()<=0)
         return Blocked(ctx,CProfitLevel::Create("",0,BRE_PROFIT_LEVEL_SOURCE_NONE,0.0,false,0.0,BRE_CLOSE_MODE_NONE,false,false,false),
                        BRE_PROFIT_LEVEL_CLOSE_INVALID_PROFILE,
                        BRE_PROFIT_LEVEL_CLOSE_REASON_INVALID_PROFILE,
                        BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED,
                        BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE,0.0);

      if(ctx.Market().Bid()<=0.0 || ctx.Market().Ask()<=0.0)
         return Blocked(ctx,plan.LevelAt(0),
                        BRE_PROFIT_LEVEL_CLOSE_INVALID_MARKET_CONTEXT,
                        BRE_PROFIT_LEVEL_CLOSE_REASON_INVALID_SESSION,
                        BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED,
                        BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE,0.0);

      if(!ctx.MarketSessionValid())
         return Blocked(ctx,plan.LevelAt(0),
                        BRE_PROFIT_LEVEL_CLOSE_INVALID_MARKET_CONTEXT,
                        BRE_PROFIT_LEVEL_CLOSE_REASON_INVALID_SESSION,
                        BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED,
                        BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE,0.0);

      if(ctx.QuoteStaleThresholdMs()>0 && ctx.QuoteFreshnessAgeMs()>ctx.QuoteStaleThresholdMs())
         return Blocked(ctx,plan.LevelAt(0),
                        BRE_PROFIT_LEVEL_CLOSE_INVALID_MARKET_CONTEXT,
                        BRE_PROFIT_LEVEL_CLOSE_REASON_STALE_QUOTE,
                        BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED,
                        BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE,0.0);

      if(!IsActiveLifecycle(ctx.LifecycleState()))
         return Blocked(ctx,plan.LevelAt(0),
                        BRE_PROFIT_LEVEL_CLOSE_BLOCKED_BY_SAFETY,
                        IsBlockingLifecycle(ctx.LifecycleState()) ? BRE_PROFIT_LEVEL_CLOSE_REASON_BASKET_LOCKED : BRE_PROFIT_LEVEL_CLOSE_REASON_BASKET_NOT_ACTIVE,
                        BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED,
                        BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE,0.0);

      if(ctx.BasketLocked())
         return Blocked(ctx,plan.LevelAt(0),
                        BRE_PROFIT_LEVEL_CLOSE_BLOCKED_BY_SAFETY,
                        BRE_PROFIT_LEVEL_CLOSE_REASON_BASKET_LOCKED,
                        BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED,
                        BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE,0.0);

      if(ctx.UnresolvedPendingExecution())
         return Blocked(ctx,plan.LevelAt(0),
                        BRE_PROFIT_LEVEL_CLOSE_BLOCKED_BY_PENDING_EXECUTION,
                        BRE_PROFIT_LEVEL_CLOSE_REASON_PENDING_EXECUTION,
                        BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED,
                        BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE,0.0);

      if(ctx.Symbol()!=ctx.Market().Symbol() || ctx.Direction()==BRE_DIRECTION_NONE)
         return Blocked(ctx,plan.LevelAt(0),
                        BRE_PROFIT_LEVEL_CLOSE_BLOCKED_BY_SAFETY,
                        BRE_PROFIT_LEVEL_CLOSE_REASON_SYMBOL_SIDE_MISMATCH,
                        BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED,
                        BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE,0.0);

      if(plan.RequireFloatingProfitPositive() && ctx.FloatingProfitUsd()<=0.0)
         return Blocked(ctx,plan.LevelAt(0),
                        BRE_PROFIT_LEVEL_CLOSE_NOT_REACHED,
                        BRE_PROFIT_LEVEL_CLOSE_REASON_NEGATIVE_FLOATING_PROFIT,
                        BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED,
                        BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE,0.0);

      if(ctx.PositionCount()<=0)
         return Blocked(ctx,plan.LevelAt(0),
                        BRE_PROFIT_LEVEL_CLOSE_INVALID_CLOSE_PLAN,
                        BRE_PROFIT_LEVEL_CLOSE_REASON_NO_OPEN_POSITIONS,
                        BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED,
                        BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE,0.0);

      for(int i=0;i<plan.LevelCount();i++)
        {
         CProfitLevel level=plan.LevelAt(i);
         if(!level.Enabled())
            continue;

         CBasketProfitLevelProgress progress;
         if(!ctx.FindLevelProgress(level.LevelId(),progress))
            progress=CBasketProfitLevelProgress::CreateEmpty(level.LevelId());

         ENUM_BRE_PROFIT_LEVEL_PROGRESS_STATE progressState=
            CProfitLevelProgressStateText::FromBasketProgress(progress.CloseCompleted(),progress.CloseRequested());

         if(progress.CloseCompleted())
           {
            continue;
           }

         CProfitLevelTriggerEvaluation trigger=CProfitLevelTriggerEvaluator::Evaluate(ctx,level);
         if(!trigger.Supported())
            return Blocked(ctx,level,
                           BRE_PROFIT_LEVEL_CLOSE_NOT_IMPLEMENTED,
                           BRE_PROFIT_LEVEL_CLOSE_REASON_UNSUPPORTED_TRIGGER,
                           progressState,
                           trigger.TriggerType(),trigger.TriggerValue());

         if(duplicateQuoteSequence)
            return Blocked(ctx,level,
                           BRE_PROFIT_LEVEL_CLOSE_NOT_REACHED,
                           BRE_PROFIT_LEVEL_CLOSE_REASON_DUPLICATE_QUOTE_SEQUENCE,
                           progressState,
                           trigger.TriggerType(),trigger.TriggerValue());

         if(!trigger.Reached())
           {
            if(!progress.Reached())
               continue;
            return Blocked(ctx,level,
                           BRE_PROFIT_LEVEL_CLOSE_NOT_REACHED,
                           BRE_PROFIT_LEVEL_CLOSE_REASON_TRIGGER_NOT_SATISFIED,
                           progressState,
                           trigger.TriggerType(),trigger.TriggerValue());
           }

         bool requiresBasketReach=false;
         for(int prior=0;prior<i;prior++)
           {
            CProfitLevel priorLevel=plan.LevelAt(prior);
            if(!priorLevel.Enabled())
               continue;
            CBasketProfitLevelProgress priorProgress;
            if(ctx.FindLevelProgress(priorLevel.LevelId(),priorProgress) && priorProgress.CloseCompleted())
              {
               requiresBasketReach=true;
               break;
              }
           }
         if(requiresBasketReach && !progress.Reached())
            continue;

         ENUM_BRE_CLOSE_MODE closeMode=level.CloseMode();
         if(closeMode==BRE_CLOSE_MODE_NONE)
            closeMode=plan.DefaultCloseMode();

         CPositionRuntimeView positions[];
         ArrayResize(positions,ctx.PositionCount());
         for(int p=0;p<ctx.PositionCount();p++)
            positions[p]=ctx.PositionAt(p);

         double sourceRemainingVolume=SumRemainingVolume(positions,ctx.PositionCount());
         SProfitCloseVolumeCalculation volumeCalc=
            CProfitCloseCandidateCloseVolumeCalculator::CalculateNextCloseVolume(sourceRemainingVolume,
                                                                               level.ClosePercent(),
                                                                               ctx.Constraints());
         if(volumeCalc.result==BRE_PROFIT_CLOSE_VOLUME_RESULT_NO_VALID_CLOSE_VOLUME)
            return Blocked(ctx,level,
                           BRE_PROFIT_LEVEL_CLOSE_INVALID_CLOSE_PLAN,
                           BRE_PROFIT_LEVEL_CLOSE_REASON_VOLUME_PLAN_FAILED,
                           progressState,
                           trigger.TriggerType(),trigger.TriggerValue());

         CPositionReductionInstruction reductions[];
         int reductionCount=0;
         if(!BuildReductionsForPlannedCloseVolume(closeMode,
                                                  ctx.Direction(),
                                                  positions,
                                                  ctx.PositionCount(),
                                                  volumeCalc.closeVolume,
                                                  ctx.Constraints(),
                                                  reductions,
                                                  reductionCount))
            return Blocked(ctx,level,
                           BRE_PROFIT_LEVEL_CLOSE_INVALID_CLOSE_PLAN,
                           BRE_PROFIT_LEVEL_CLOSE_REASON_VOLUME_PLAN_FAILED,
                           progressState,
                           trigger.TriggerType(),trigger.TriggerValue());

         double targetCloseMoney=ctx.FloatingProfitUsd()*level.ClosePercent()/100.0;
         if(targetCloseMoney<=0.0)
            return Blocked(ctx,level,
                           BRE_PROFIT_LEVEL_CLOSE_INVALID_CLOSE_PLAN,
                           BRE_PROFIT_LEVEL_CLOSE_REASON_VOLUME_PLAN_FAILED,
                           progressState,
                           trigger.TriggerType(),trigger.TriggerValue());

         string idempotencyKey=BuildIdempotencyKey(ctx.BasketId(),level.LevelId(),ctx.QuoteSequence());
         CProfitLevelCloseAudit audit=CProfitLevelCloseAudit::Create(ctx.BasketId(),
                                                                    ctx.StrategyProfileHash(),
                                                                    ctx.BasketVersion(),
                                                                    level.LevelId(),
                                                                    level.LevelIndex(),
                                                                    trigger.TriggerType(),
                                                                    trigger.TriggerValue(),
                                                                    ctx.FloatingProfitUsd(),
                                                                    level.ClosePercent(),
                                                                    targetCloseMoney,
                                                                    reductions,
                                                                    reductionCount,
                                                                    closeMode,
                                                                    ctx.QuoteSequence(),
                                                                    idempotencyKey,
                                                                    ctx.TimestampUtc(),
                                                                    BRE_PROFIT_LEVEL_CLOSE_DUE,
                                                                    BRE_PROFIT_LEVEL_CLOSE_REASON_NONE,
                                                                    BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED,
                                                                    false);
         return CProfitLevelCloseCandidate::FromAudit(audit);
        }

      return Blocked(ctx,plan.LevelAt(0),
                     BRE_PROFIT_LEVEL_CLOSE_ALREADY_COMPLETED,
                     BRE_PROFIT_LEVEL_CLOSE_REASON_LEVEL_ALREADY_COMPLETED,
                     BRE_PROFIT_LEVEL_PROGRESS_COMPLETED,
                     BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE,0.0);
     }
  };

#endif
