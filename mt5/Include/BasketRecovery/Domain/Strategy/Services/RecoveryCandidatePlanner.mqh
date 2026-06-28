#ifndef BRE_DOMAIN_RECOVERY_CANDIDATE_PLANNER_MQH
#define BRE_DOMAIN_RECOVERY_CANDIDATE_PLANNER_MQH

#include <BasketRecovery/Domain/Strategy/Context/RecoveryPlanEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryCandidate.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryPlanResolver.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ExecutionZoneResolver.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryTriggerEvaluator.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryVolumeResolver.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>

class CRecoveryCandidatePlanner
  {
private:
   CRecoveryPlanResolver      m_planResolver;
   CExecutionZoneResolver     m_zoneResolver;

   string                     BuildIdempotencyKey(const CBasketId &basketId,const int stepIndex,const ulong quoteSequence) const
     {
      return "recovery-candidate:"+basketId.Value()+":step:"+IntegerToString(stepIndex)+":q:"+IntegerToString((long)quoteSequence);
     }

   CRecoveryCandidate         BlockedCandidate(const CRecoveryPlanEvaluationContext &ctx,
                                                 const int stepIndex,
                                                 const double triggerReferencePrice,
                                                 const double zoneLow,
                                                 const double zoneHigh,
                                                 const double proposedVolume,
                                                 const ENUM_BRE_RECOVERY_CANDIDATE_STATUS status,
                                                 const ENUM_BRE_RECOVERY_CANDIDATE_REASON reason) const
     {
      string idempotencyKey=BuildIdempotencyKey(ctx.BasketId(),stepIndex,ctx.QuoteSequence());
      CRecoveryCandidateAudit audit=CRecoveryCandidateAudit::Create(ctx.BasketId(),
                                                                    ctx.StrategyProfileHash(),
                                                                    ctx.BasketVersion(),
                                                                    ctx.Symbol(),
                                                                    ctx.Direction(),
                                                                    stepIndex,
                                                                    triggerReferencePrice,
                                                                    ctx.Market().Bid(),
                                                                    ctx.Market().Ask(),
                                                                    zoneLow,
                                                                    zoneHigh,
                                                                    proposedVolume,
                                                                    ctx.BasketStopLoss(),
                                                                    ctx.QuoteSequence(),
                                                                    status,
                                                                    reason,
                                                                    idempotencyKey,
                                                                    ctx.TimestampUtc());
      return CRecoveryCandidate::FromAudit(audit);
     }

public:
   CRecoveryCandidate         Plan(const CRecoveryPlanEvaluationContext &ctx,
                                   const bool duplicateQuoteSequence) const
     {
      double zoneLow=0.0;
      double zoneHigh=0.0;
      int stepIndex=0;
      double triggerReferencePrice=ctx.StepState().LastTriggerReferencePrice();

      if(!ctx.ProfileValid())
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_INVALID_PROFILE,BRE_RECOVERY_CANDIDATE_REASON_INVALID_PROFILE);

      if(ctx.Market().Bid()<=0.0 || ctx.Market().Ask()<=0.0 || ctx.Market().PipSize()<=0.0)
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_INVALID_MARKET_CONTEXT,BRE_RECOVERY_CANDIDATE_REASON_INVALID_SESSION);

      if(!ctx.MarketSessionValid())
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_INVALID_MARKET_CONTEXT,BRE_RECOVERY_CANDIDATE_REASON_INVALID_SESSION);

      if(ctx.QuoteStaleThresholdMs()>0 && ctx.QuoteFreshnessAgeMs()>ctx.QuoteStaleThresholdMs())
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_INVALID_MARKET_CONTEXT,BRE_RECOVERY_CANDIDATE_REASON_STALE_QUOTE);

      if(ctx.LifecycleState()!=BRE_STATE_ACTIVE)
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_BLOCKED_BY_SAFETY,BRE_RECOVERY_CANDIDATE_REASON_BASKET_NOT_ACTIVE);

      if(!ctx.RecoveryActive())
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_BLOCKED_BY_SAFETY,BRE_RECOVERY_CANDIDATE_REASON_RECOVERY_NOT_ACTIVE);

      if(ctx.RecoveryPermanentlyDisabled() || ctx.BasketState().RecoveryDisabled())
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_BLOCKED_BY_SAFETY,BRE_RECOVERY_CANDIDATE_REASON_RECOVERY_DISABLED);

      CRecoveryPlan recoveryPlan=ctx.Profile().RecoveryPlan();
      if(recoveryPlan.DisableAfterBreakEven() && ctx.BasketState().BreakEvenActivated())
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_BLOCKED_BY_SAFETY,BRE_RECOVERY_CANDIDATE_REASON_BREAK_EVEN_DISABLED);

      if(ctx.BasketLocked())
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_BLOCKED_BY_SAFETY,BRE_RECOVERY_CANDIDATE_REASON_BASKET_NOT_ACTIVE);

      if(ctx.UnresolvedPendingExecution())
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_BLOCKED_BY_PENDING_EXECUTION,BRE_RECOVERY_CANDIDATE_REASON_PENDING_EXECUTION);

      if(ctx.Symbol()!=ctx.Market().Symbol() || ctx.Direction()==BRE_DIRECTION_NONE)
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_BLOCKED_BY_SAFETY,BRE_RECOVERY_CANDIDATE_REASON_SYMBOL_SIDE_MISMATCH);

      if(duplicateQuoteSequence)
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_NOT_DUE,BRE_RECOVERY_CANDIDATE_REASON_DUPLICATE_QUOTE_SEQUENCE);

      int currentStepIndex=ctx.StepState().LastAcceptedStepIndex();
      CRecoveryPlanResolution resolution=m_planResolver.ResolveNextStep(recoveryPlan,currentStepIndex);
      if(!resolution.Supported())
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_INVALID_PROFILE,BRE_RECOVERY_CANDIDATE_REASON_UNSUPPORTED_ALGORITHM);

      if(!resolution.HasStep())
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_BLOCKED_BY_STEP_LIMIT,BRE_RECOVERY_CANDIDATE_REASON_STEP_LIMIT_REACHED);

      CRecoveryStep step=resolution.Step();
      stepIndex=step.StepIndex();
      triggerReferencePrice=ctx.StepState().LastTriggerReferencePrice();

      CRecoveryTriggerEvaluation trigger=CRecoveryTriggerEvaluator::Evaluate(ctx.Direction(),
                                                                             triggerReferencePrice,
                                                                             ctx.Market().Bid(),
                                                                             ctx.Market().Ask(),
                                                                             ctx.Market().PipSize(),
                                                                             step.DistancePips());
      if(trigger.FavorableMovement())
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_NOT_DUE,BRE_RECOVERY_CANDIDATE_REASON_FAVORABLE_MOVEMENT);

      if(!trigger.IsDue())
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_NOT_DUE,BRE_RECOVERY_CANDIDATE_REASON_INSUFFICIENT_ADVERSE_MOVE);

      CEffectiveRecoveryZone zone=m_zoneResolver.Resolve(ctx.Profile().ExecutionZone(),
                                                         ctx.Direction(),
                                                         ctx.BasketState().SignalRangeLow(),
                                                         ctx.BasketState().SignalRangeHigh(),
                                                         ctx.Market().PipSize());
      zoneLow=zone.Low();
      zoneHigh=zone.High();
      if(!zone.ContainsPrice(trigger.ExecutablePrice()))
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_BLOCKED_BY_ZONE,BRE_RECOVERY_CANDIDATE_REASON_OUTSIDE_EXECUTION_ZONE);

      CRecoveryVolumePlan volumePlan=CRecoveryVolumeResolver::Resolve(recoveryPlan,
                                                                      step,
                                                                      ctx.StepState().PriorRecoveryVolume(),
                                                                      ctx.Constraints());
      if(!volumePlan.Valid())
         return BlockedCandidate(ctx,stepIndex,triggerReferencePrice,zoneLow,zoneHigh,0.0,
                                 BRE_RECOVERY_CANDIDATE_BLOCKED_BY_SAFETY,volumePlan.Reason());

      string idempotencyKey=BuildIdempotencyKey(ctx.BasketId(),stepIndex,ctx.QuoteSequence());
      CRecoveryCandidateAudit audit=CRecoveryCandidateAudit::Create(ctx.BasketId(),
                                                                    ctx.StrategyProfileHash(),
                                                                    ctx.BasketVersion(),
                                                                    ctx.Symbol(),
                                                                    ctx.Direction(),
                                                                    stepIndex,
                                                                    triggerReferencePrice,
                                                                    ctx.Market().Bid(),
                                                                    ctx.Market().Ask(),
                                                                    zoneLow,
                                                                    zoneHigh,
                                                                    volumePlan.NormalizedVolume(),
                                                                    ctx.BasketStopLoss(),
                                                                    ctx.QuoteSequence(),
                                                                    BRE_RECOVERY_CANDIDATE_DUE,
                                                                    BRE_RECOVERY_CANDIDATE_REASON_NONE,
                                                                    idempotencyKey,
                                                                    ctx.TimestampUtc());
      return CRecoveryCandidate::FromAudit(audit);
     }
  };

#endif
