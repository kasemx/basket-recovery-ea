#ifndef BRE_DOMAIN_RECOVERY_DECISION_RISK_VALIDATOR_MQH
#define BRE_DOMAIN_RECOVERY_DECISION_RISK_VALIDATOR_MQH

#include <BasketRecovery/Domain/Risk/ValueObjects/RecoveryDecisionRiskGateResult.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RecoveryRiskDecisionAudit.mqh>
#include <BasketRecovery/Domain/Risk/Services/ProposedPositionRiskValidator.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/ProjectedBasketRisk.mqh>
#include <BasketRecovery/Domain/Risk/Services/RiskReductionPlanner.mqh>
#include <BasketRecovery/Domain/Risk/Services/SlRiskMath.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/OpenRecoveryPositionDecision.mqh>
#include <BasketRecovery/Domain/Strategy/Context/StrategyRiskEvaluationContext.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Enums/BasketMode.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>

class CRecoveryDecisionRiskValidator
  {
private:
   static bool       IsProposedVolumeValid(const double volume,const CSymbolTradingConstraints &constraints)
     {
      if(volume<=0.0)
         return false;
      double minVolume=constraints.VolumeMin();
      double maxVolume=constraints.VolumeMax();
      if(minVolume>0.0 && volume<minVolume-0.0000001)
         return false;
      if(maxVolume>0.0 && volume>maxVolume+0.0000001)
         return false;
      double normalized=CSlRiskMath::NormalizeVolumeDown(volume,constraints);
      return normalized>0.0 && MathAbs(normalized-volume)<=0.0000001;
     }

   static ENUM_BRE_RECOVERY_RISK_BLOCK_REASON MapLifecycleBlock(const CBasketAggregate &basket)
     {
      switch(basket.LifecycleState())
        {
         case BRE_STATE_SUSPENDED: return BRE_RECOVERY_RISK_BLOCK_BASKET_SUSPENDED;
         case BRE_STATE_CLOSING: return BRE_RECOVERY_RISK_BLOCK_BASKET_CLOSING;
         case BRE_STATE_FINISHED: return BRE_RECOVERY_RISK_BLOCK_BASKET_FINISHED;
         case BRE_STATE_ERROR: return BRE_RECOVERY_RISK_BLOCK_BASKET_RECONCILING;
         default: return BRE_RECOVERY_RISK_BLOCK_BASKET_NOT_ACTIVE;
        }
     }

   static CRecoveryRiskDecisionAudit BuildAudit(const CBasketAggregate &basket,
                                                const COpenRecoveryPositionDecision &decision,
                                                const ENUM_BRE_TRADE_DIRECTION direction,
                                                const double currentSlRisk,
                                                const double projectedSlRisk,
                                                const double targetRisk,
                                                const double maxRisk,
                                                const double maxRiskRemaining,
                                                const bool allowed,
                                                const ENUM_BRE_RECOVERY_RISK_BLOCK_REASON blockReason,
                                                const string strategyProfileHash,
                                                const datetime timestampUtc,
                                                const double basketStopLoss)
     {
      return CRecoveryRiskDecisionAudit::Create(basket.Id(),
                                                decision.IdempotencyKey(),
                                                direction,
                                                decision.Lot(),
                                                decision.ExpectedEntryPrice(),
                                                basketStopLoss,
                                                currentSlRisk,
                                                projectedSlRisk,
                                                targetRisk,
                                                maxRisk,
                                                maxRiskRemaining,
                                                allowed,
                                                blockReason,
                                                strategyProfileHash,
                                                basket.Version(),
                                                timestampUtc);
     }

   static CRecoveryDecisionRiskGateResult Reject(const CBasketAggregate &basket,
                                                 const COpenRecoveryPositionDecision &decision,
                                                 const ENUM_BRE_TRADE_DIRECTION direction,
                                                 const ENUM_BRE_RECOVERY_RISK_BLOCK_REASON blockReason,
                                                 const string strategyProfileHash,
                                                 const datetime timestampUtc,
                                                 const double basketStopLoss,
                                                 const CBasketRiskSnapshot &current,
                                                 const CProjectedBasketRisk &projected,
                                                 const CRiskReductionPlan &reductionPlan)
     {
      double projectedRisk=projected.ProjectedSlRiskMoney();
      double currentRisk=current.IsSafe() ? current.CurrentSlRiskMoney() : 0.0;
      double targetRisk=current.IsSafe() ? current.TargetRiskMoney() : 0.0;
      double maxRisk=current.IsSafe() ? current.MaxRiskMoney() : 0.0;
      double remaining=projected.SafetyStatus()==BRE_RISK_SAFETY_SAFE ? projected.MaxRiskRemainingMoney() : 0.0;
      CRecoveryRiskDecisionAudit audit=BuildAudit(basket,decision,direction,currentRisk,projectedRisk,
                                                  targetRisk,maxRisk,remaining,false,blockReason,
                                                  strategyProfileHash,timestampUtc,basketStopLoss);
      return CRecoveryDecisionRiskGateResult::Blocked(audit,reductionPlan);
     }

public:
   static CRecoveryDecisionRiskGateResult Validate(const CBasketAggregate &basket,
                                                   const COpenRecoveryPositionDecision &decision,
                                                   const CTradeExecutionRequest &request,
                                                   const CPositionSnapshotEntry &entries[],
                                                   const int entryCount,
                                                   const CRiskCalculationContext &context,
                                                   const CStrategyRiskEvaluationContext &riskContext,
                                                   const int quoteStaleThresholdMs,
                                                   const string expectedStrategyProfileHash,
                                                   const datetime timestampUtc)
     {
      ENUM_BRE_TRADE_DIRECTION direction=request.Direction();
      CSignalDetails details=basket.SignalDetails();
      double basketStopLoss=details.StopLoss().Value();
      CBasketRiskSnapshot emptySnapshot=CBasketRiskSnapshot::Unknown(basket.Id(),basket.Symbol());
      CProjectedBasketRisk emptyProjected=CProjectedBasketRisk::Create(emptySnapshot,0.0,0.0,BRE_RISK_SAFETY_UNKNOWN);
      CRiskReductionPlan emptyPlan=CRiskReductionPlan::CreateEmpty();

      if(expectedStrategyProfileHash!="" && expectedStrategyProfileHash!=basket.StrategyProfileHash())
         return Reject(basket,decision,direction,BRE_RECOVERY_RISK_BLOCK_PROFILE_HASH_MISMATCH,
                       basket.StrategyProfileHash(),timestampUtc,basketStopLoss,emptySnapshot,emptyProjected,emptyPlan);

      if(basket.ModeFlags().Locked())
         return Reject(basket,decision,direction,BRE_RECOVERY_RISK_BLOCK_BASKET_LOCKED,
                       basket.StrategyProfileHash(),timestampUtc,basketStopLoss,emptySnapshot,emptyProjected,emptyPlan);

      if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
         return Reject(basket,decision,direction,MapLifecycleBlock(basket),
                       basket.StrategyProfileHash(),timestampUtc,basketStopLoss,emptySnapshot,emptyProjected,emptyPlan);

      if(riskContext.UnresolvedPendingExecution())
         return Reject(basket,decision,direction,BRE_RECOVERY_RISK_BLOCK_UNRESOLVED_PENDING_EXECUTION,
                       basket.StrategyProfileHash(),timestampUtc,basketStopLoss,emptySnapshot,emptyProjected,emptyPlan);

      if(quoteStaleThresholdMs>0 && context.Quote().FreshnessAgeMs()>quoteStaleThresholdMs)
         return Reject(basket,decision,direction,BRE_RECOVERY_RISK_BLOCK_STALE_QUOTE,
                       basket.StrategyProfileHash(),timestampUtc,basketStopLoss,emptySnapshot,emptyProjected,emptyPlan);

      if(request.Symbol()!=basket.Symbol() || direction!=basket.Direction() || direction==BRE_DIRECTION_NONE)
         return Reject(basket,decision,direction,BRE_RECOVERY_RISK_BLOCK_DIRECTION_OR_SYMBOL_CONFLICT,
                       basket.StrategyProfileHash(),timestampUtc,basketStopLoss,emptySnapshot,emptyProjected,emptyPlan);

      if(!IsProposedVolumeValid(decision.Lot(),context.Quote().Constraints()))
         return Reject(basket,decision,direction,BRE_RECOVERY_RISK_BLOCK_INVALID_PROPOSED_VOLUME,
                       basket.StrategyProfileHash(),timestampUtc,basketStopLoss,emptySnapshot,emptyProjected,emptyPlan);

      if(basketStopLoss<=0.0)
         return Reject(basket,decision,direction,BRE_RECOVERY_RISK_BLOCK_MISSING_BASKET_SL,
                       basket.StrategyProfileHash(),timestampUtc,basketStopLoss,emptySnapshot,emptyProjected,emptyPlan);

      CRiskValidationResult validation=CProposedPositionRiskValidator::Validate(basket,entries,entryCount,request,context);
      CBasketRiskSnapshot current=validation.CurrentRisk();
      CProjectedBasketRisk projected=validation.ProjectedRisk();
      CRiskReductionPlan reductionPlan=validation.ReductionPlan();

      if(!validation.Allowed())
        {
         ENUM_BRE_RECOVERY_RISK_BLOCK_REASON blockReason=CRecoveryRiskBlockReasonText::FromRiskViolation(validation.Reason());
         if(validation.Reason()==BRE_RISK_VIOLATION_RISK_DATA_UNSAFE && current.SafetyStatus()==BRE_RISK_SAFETY_UNSAFE)
            blockReason=BRE_RECOVERY_RISK_BLOCK_RISK_DATA_UNSAFE;
         return Reject(basket,decision,direction,blockReason,basket.StrategyProfileHash(),timestampUtc,
                       basketStopLoss,current,projected,reductionPlan);
        }

      double projectedRisk=projected.ProjectedSlRiskMoney();
      double currentRisk=current.CurrentSlRiskMoney();
      double targetRisk=current.TargetRiskMoney();
      double maxRisk=current.MaxRiskMoney();
      double remaining=projected.MaxRiskRemainingMoney();
      bool suggestReduction=current.AboveTargetRisk() && reductionPlan.HasPlan();
      CRecoveryRiskDecisionAudit audit=BuildAudit(basket,decision,direction,currentRisk,projectedRisk,
                                                  targetRisk,maxRisk,remaining,true,
                                                  BRE_RECOVERY_RISK_BLOCK_NONE,
                                                  basket.StrategyProfileHash(),timestampUtc,basketStopLoss);
      return CRecoveryDecisionRiskGateResult::Allowed(audit,reductionPlan,suggestReduction);
     }
  };

#endif
