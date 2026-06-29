#ifndef BRE_DOMAIN_BREAK_EVEN_CANDIDATE_PLANNER_MQH
#define BRE_DOMAIN_BREAK_EVEN_CANDIDATE_PLANNER_MQH

#include <BasketRecovery/Domain/Strategy/Context/BreakEvenEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenCandidate.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenRule.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenTrigger.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenAction.mqh>
#include <BasketRecovery/Domain/Strategy/Services/BreakEvenCandidateTriggerEvaluator.mqh>
#include <BasketRecovery/Domain/Strategy/Services/BreakEvenPriceCalculationService.mqh>
#include <BasketRecovery/Domain/Strategy/Services/BreakEvenStopPriceValidator.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>

class CBreakEvenCandidatePlanner
  {
private:
   string            BuildIdempotencyKey(const CBasketId &basketId,
                                         const string ruleId,
                                         const ulong quoteSequence) const
     {
      return "break-even-candidate:"+basketId.Value()+":rule:"+ruleId+":q:"+IntegerToString((long)quoteSequence);
     }

   CBreakEvenCandidate Blocked(const CBreakEvenEvaluationContext &ctx,
                             const CBreakEvenRule &rule,
                             const ENUM_BRE_BREAK_EVEN_CANDIDATE_STATUS status,
                             const ENUM_BRE_BREAK_EVEN_REASON reason,
                             const ENUM_BRE_BREAK_EVEN_PROGRESS_STATE progressState,
                             const ENUM_BRE_BREAK_EVEN_CANDIDATE_TRIGGER_TYPE triggerType,
                             const double triggerValue,
                             const CBreakEvenPriceCalculation &priceCalc) const
     {
      string idempotencyKey=BuildIdempotencyKey(ctx.BasketId(),rule.RuleId(),ctx.QuoteSequence());
      bool disableRecovery=false;
      bool lockBasket=false;
      bool trailingHandoff=false;
      CBreakEvenPriceCalculationService::ExtractPolicyRecommendations(rule,disableRecovery,lockBasket,trailingHandoff);
      CBreakEvenCandidateAudit audit=CBreakEvenCandidateAudit::Create(ctx.BasketId(),
                                                                     ctx.StrategyProfileHash(),
                                                                     ctx.BasketVersion(),
                                                                     rule.RuleId(),
                                                                     triggerType,
                                                                     triggerValue,
                                                                     priceCalc.WeightedAverageEntry(),
                                                                     priceCalc.TotalActiveVolume(),
                                                                     ctx.Market().Bid(),
                                                                     ctx.Market().Ask(),
                                                                     priceCalc,
                                                                     ctx.BasketStopLoss(),
                                                                     ctx.Direction(),
                                                                     ctx.QuoteSequence(),
                                                                     disableRecovery,
                                                                     lockBasket,
                                                                     trailingHandoff,
                                                                     idempotencyKey,
                                                                     ctx.TimestampUtc(),
                                                                     status,
                                                                     reason,
                                                                     progressState);
      return CBreakEvenCandidate::FromAudit(audit);
     }

   CBreakEvenRule    EmptyRule(void) const
     {
      CBreakEvenTrigger trigger=CBreakEvenTrigger::Create(BRE_BE_TRIGGER_NONE,0.0,false,0.0,false,0.0,false,"","","","");
      CBreakEvenAction actions[];
      ArrayResize(actions,0);
      return CBreakEvenRule::Create("",false,0,false,trigger,actions,0);
     }

   bool              IsActiveLifecycle(const ENUM_BRE_BASKET_LIFECYCLE_STATE state) const
     {
      return state==BRE_STATE_ACTIVE;
     }

   bool              IsBlockingLifecycle(const ENUM_BRE_BASKET_LIFECYCLE_STATE state) const
     {
      return state==BRE_STATE_SUSPENDED || state==BRE_STATE_CLOSING;
     }

   double            ExecutablePrice(const CBreakEvenEvaluationContext &ctx) const
     {
      return ctx.Direction()==BRE_DIRECTION_BUY ? ctx.Market().Bid() : ctx.Market().Ask();
     }

   int               FindNextRuleIndex(const CBreakEvenPlan &plan,
                                       const CBreakEvenEvaluationContext &ctx,
                                       int &outBestPriority) const
     {
      int bestIndex=-1;
      outBestPriority=2147483647;
      for(int i=0;i<plan.RuleCount();i++)
        {
         CBreakEvenRule rule=plan.RuleAt(i);
         if(!rule.Enabled())
            continue;
         if(rule.RunOnce() && ctx.HasExecutedBreakEvenRule(rule.RuleId()))
            continue;
         if(rule.Priority()<outBestPriority)
           {
            outBestPriority=rule.Priority();
            bestIndex=i;
           }
        }
      return bestIndex;
     }

public:
   CBreakEvenCandidate Plan(const CBreakEvenEvaluationContext &ctx,
                          const bool duplicateQuoteSequence) const
     {
      CBreakEvenRule emptyRule=EmptyRule();
      CBreakEvenPriceCalculation emptyCalc=CBreakEvenPriceCalculation::Invalid();
      CBreakEvenPlan plan=ctx.Profile().BreakEvenPlan();

      if(!ctx.ProfileValid() || plan.RuleCount()<=0)
         return Blocked(ctx,emptyRule,
                        BRE_BREAK_EVEN_CANDIDATE_INVALID_PROFILE,
                        BRE_BREAK_EVEN_REASON_INVALID_PROFILE,
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        BRE_BE_CANDIDATE_TRIGGER_NONE,0.0,emptyCalc);

      if(ctx.BreakEvenActive())
         return Blocked(ctx,emptyRule,
                        BRE_BREAK_EVEN_CANDIDATE_ALREADY_ACTIVATED,
                        BRE_BREAK_EVEN_REASON_BREAK_EVEN_ALREADY_ACTIVE,
                        BRE_BREAK_EVEN_PROGRESS_ACTIVATED,
                        BRE_BE_CANDIDATE_TRIGGER_NONE,0.0,emptyCalc);

      if(ctx.Market().Bid()<=0.0 || ctx.Market().Ask()<=0.0)
         return Blocked(ctx,emptyRule,
                        BRE_BREAK_EVEN_CANDIDATE_INVALID_MARKET_CONTEXT,
                        BRE_BREAK_EVEN_REASON_INVALID_SESSION,
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        BRE_BE_CANDIDATE_TRIGGER_NONE,0.0,emptyCalc);

      if(!ctx.MarketSessionValid())
         return Blocked(ctx,emptyRule,
                        BRE_BREAK_EVEN_CANDIDATE_INVALID_MARKET_CONTEXT,
                        BRE_BREAK_EVEN_REASON_INVALID_SESSION,
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        BRE_BE_CANDIDATE_TRIGGER_NONE,0.0,emptyCalc);

      if(ctx.QuoteStaleThresholdMs()>0 && ctx.QuoteFreshnessAgeMs()>ctx.QuoteStaleThresholdMs())
         return Blocked(ctx,emptyRule,
                        BRE_BREAK_EVEN_CANDIDATE_INVALID_MARKET_CONTEXT,
                        BRE_BREAK_EVEN_REASON_STALE_QUOTE,
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        BRE_BE_CANDIDATE_TRIGGER_NONE,0.0,emptyCalc);

      if(!IsActiveLifecycle(ctx.LifecycleState()))
         return Blocked(ctx,emptyRule,
                        BRE_BREAK_EVEN_CANDIDATE_BLOCKED_BY_SAFETY,
                        IsBlockingLifecycle(ctx.LifecycleState()) ? BRE_BREAK_EVEN_REASON_BASKET_LOCKED : BRE_BREAK_EVEN_REASON_BASKET_NOT_ACTIVE,
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        BRE_BE_CANDIDATE_TRIGGER_NONE,0.0,emptyCalc);

      if(ctx.BasketLocked())
         return Blocked(ctx,emptyRule,
                        BRE_BREAK_EVEN_CANDIDATE_BLOCKED_BY_SAFETY,
                        BRE_BREAK_EVEN_REASON_BASKET_LOCKED,
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        BRE_BE_CANDIDATE_TRIGGER_NONE,0.0,emptyCalc);

      if(ctx.UnresolvedPendingExecution())
         return Blocked(ctx,emptyRule,
                        BRE_BREAK_EVEN_CANDIDATE_BLOCKED_BY_PENDING_EXECUTION,
                        BRE_BREAK_EVEN_REASON_PENDING_EXECUTION,
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        BRE_BE_CANDIDATE_TRIGGER_NONE,0.0,emptyCalc);

      if(ctx.Symbol()!=ctx.Market().Symbol() || ctx.Direction()==BRE_DIRECTION_NONE)
         return Blocked(ctx,emptyRule,
                        BRE_BREAK_EVEN_CANDIDATE_BLOCKED_BY_SAFETY,
                        BRE_BREAK_EVEN_REASON_SYMBOL_SIDE_MISMATCH,
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        BRE_BE_CANDIDATE_TRIGGER_NONE,0.0,emptyCalc);

      if(ctx.PositionCount()<=0)
         return Blocked(ctx,emptyRule,
                        BRE_BREAK_EVEN_CANDIDATE_BLOCKED_BY_SAFETY,
                        BRE_BREAK_EVEN_REASON_NO_OPEN_POSITIONS,
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        BRE_BE_CANDIDATE_TRIGGER_NONE,0.0,emptyCalc);

      if(duplicateQuoteSequence)
         return Blocked(ctx,emptyRule,
                        BRE_BREAK_EVEN_CANDIDATE_NOT_REACHED,
                        BRE_BREAK_EVEN_REASON_DUPLICATE_QUOTE_SEQUENCE,
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        BRE_BE_CANDIDATE_TRIGGER_NONE,0.0,emptyCalc);

      int bestPriority=0;
      int ruleIndex=FindNextRuleIndex(plan,ctx,bestPriority);
      if(ruleIndex<0)
         return Blocked(ctx,emptyRule,
                        BRE_BREAK_EVEN_CANDIDATE_ALREADY_ACTIVATED,
                        BRE_BREAK_EVEN_REASON_RULE_ALREADY_EXECUTED,
                        BRE_BREAK_EVEN_PROGRESS_ACTIVATED,
                        BRE_BE_CANDIDATE_TRIGGER_NONE,0.0,emptyCalc);

      CBreakEvenRule rule=plan.RuleAt(ruleIndex);
      CBreakEvenCandidateTriggerEvaluation trigger=CBreakEvenCandidateTriggerEvaluator::Evaluate(ctx,rule);
      if(!trigger.Supported())
         return Blocked(ctx,rule,
                        BRE_BREAK_EVEN_CANDIDATE_NOT_IMPLEMENTED,
                        BRE_BREAK_EVEN_REASON_UNSUPPORTED_TRIGGER,
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        trigger.TriggerType(),trigger.TriggerValue(),emptyCalc);

      if(!trigger.Reached())
         return Blocked(ctx,rule,
                        BRE_BREAK_EVEN_CANDIDATE_NOT_REACHED,
                        BRE_BREAK_EVEN_REASON_TRIGGER_NOT_SATISFIED,
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        trigger.TriggerType(),trigger.TriggerValue(),emptyCalc);

      CBreakEvenAction moveAction;
      bool hasMove=false;
      for(int a=0;a<rule.ActionCount();a++)
        {
         CBreakEvenAction action=rule.ActionAt(a);
         if(action.Type()==BRE_BE_ACTION_MOVE_SL_TO_AVERAGE || action.Type()==BRE_BE_ACTION_MOVE_SL_WITH_OFFSET)
           {
            moveAction=action;
            hasMove=true;
            break;
           }
        }
      if(!hasMove)
         return Blocked(ctx,rule,
                        BRE_BREAK_EVEN_CANDIDATE_INVALID_PROFILE,
                        BRE_BREAK_EVEN_REASON_NO_SL_ACTION,
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        trigger.TriggerType(),trigger.TriggerValue(),emptyCalc);

      CBreakEvenPriceCalculation priceCalc=CBreakEvenPriceCalculationService::Compute(ctx,rule);
      if(!priceCalc.Valid())
         return Blocked(ctx,rule,
                        BRE_BREAK_EVEN_CANDIDATE_INVALID_PROFILE,
                        BRE_BREAK_EVEN_REASON_INVALID_WEIGHTED_ENTRY,
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        trigger.TriggerType(),trigger.TriggerValue(),priceCalc);

      CBreakEvenStopPriceValidation stopValidation=CBreakEvenStopPriceValidator::Validate(ctx.Direction(),
                                                                                          ExecutablePrice(ctx),
                                                                                          priceCalc.NormalizedStopLoss(),
                                                                                          ctx.Point(),
                                                                                          ctx.Constraints());
      if(!stopValidation.Valid())
         return Blocked(ctx,rule,
                        BRE_BREAK_EVEN_CANDIDATE_INVALID_STOP_PRICE,
                        stopValidation.Reason(),
                        BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED,
                        trigger.TriggerType(),trigger.TriggerValue(),priceCalc);

      bool disableRecovery=false;
      bool lockBasket=false;
      bool trailingHandoff=false;
      CBreakEvenPriceCalculationService::ExtractPolicyRecommendations(rule,disableRecovery,lockBasket,trailingHandoff);

      string idempotencyKey=BuildIdempotencyKey(ctx.BasketId(),rule.RuleId(),ctx.QuoteSequence());
      CBreakEvenCandidateAudit audit=CBreakEvenCandidateAudit::Create(ctx.BasketId(),
                                                                     ctx.StrategyProfileHash(),
                                                                     ctx.BasketVersion(),
                                                                     rule.RuleId(),
                                                                     trigger.TriggerType(),
                                                                     trigger.TriggerValue(),
                                                                     priceCalc.WeightedAverageEntry(),
                                                                     priceCalc.TotalActiveVolume(),
                                                                     ctx.Market().Bid(),
                                                                     ctx.Market().Ask(),
                                                                     priceCalc,
                                                                     ctx.BasketStopLoss(),
                                                                     ctx.Direction(),
                                                                     ctx.QuoteSequence(),
                                                                     disableRecovery,
                                                                     lockBasket,
                                                                     trailingHandoff,
                                                                     idempotencyKey,
                                                                     ctx.TimestampUtc(),
                                                                     BRE_BREAK_EVEN_CANDIDATE_DUE,
                                                                     BRE_BREAK_EVEN_REASON_NONE,
                                                                     BRE_BREAK_EVEN_PROGRESS_CANDIDATE_GENERATED);
      return CBreakEvenCandidate::FromAudit(audit);
     }
  };

#endif
