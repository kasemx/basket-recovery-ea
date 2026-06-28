#ifndef BRE_DOMAIN_PROPOSED_POSITION_RISK_VALIDATOR_MQH
#define BRE_DOMAIN_PROPOSED_POSITION_RISK_VALIDATOR_MQH

#include <BasketRecovery/Domain/Risk/Services/BasketRiskCalculator.mqh>
#include <BasketRecovery/Domain/Risk/Services/ProjectedRiskCalculator.mqh>
#include <BasketRecovery/Domain/Risk/Services/RiskReductionPlanner.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskValidationResult.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Enums/BasketMode.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>

class CProposedPositionRiskValidator
  {
private:
   static bool       IsBasketOperational(const CBasketAggregate &basket,
                                           ENUM_BRE_RISK_VIOLATION_REASON &outReason,
                                           string &outDetail)
     {
      if(basket.LifecycleState()==BRE_STATE_SUSPENDED)
        {
         outReason=BRE_RISK_VIOLATION_BASKET_SUSPENDED;
         outDetail="Basket is suspended";
         return false;
        }
      if(basket.ModeFlags().Locked())
        {
         outReason=BRE_RISK_VIOLATION_BASKET_LOCKED;
         outDetail="Basket is locked";
         return false;
        }
      if(basket.LifecycleState()==BRE_STATE_ERROR)
        {
         outReason=BRE_RISK_VIOLATION_BASKET_RECONCILING;
         outDetail="Basket is in error/reconciliation state";
         return false;
        }
      if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
        {
         outReason=BRE_RISK_VIOLATION_RISK_DATA_UNKNOWN;
         outDetail="Basket lifecycle is not ACTIVE";
         return false;
        }
      return true;
     }

public:
   static CRiskValidationResult Validate(const CBasketAggregate &basket,
                                         const CPositionSnapshotEntry &entries[],
                                         const int entryCount,
                                         const CTradeExecutionRequest &request,
                                         const CRiskCalculationContext &context)
     {
      ENUM_BRE_RISK_VIOLATION_REASON reason=BRE_RISK_VIOLATION_NONE;
      string detail="";
      if(!IsBasketOperational(basket,reason,detail))
        {
         CBasketRiskSnapshot empty=CBasketRiskSnapshot::Unsafe(basket.Id(),basket.Symbol());
         CProjectedBasketRisk projected=CProjectedBasketRisk::Create(empty,0.0,0.0,BRE_RISK_SAFETY_UNSAFE);
         return CRiskValidationResult::Rejected(reason,detail,empty,projected,CRiskReductionPlan::CreateEmpty());
        }

      CBasketRiskSnapshot current=CBasketRiskCalculator::Calculate(basket.Id(),entries,entryCount,context);
      if(!current.IsSafe())
        {
         reason=current.SafetyStatus()==BRE_RISK_SAFETY_UNKNOWN
                ? BRE_RISK_VIOLATION_RISK_DATA_UNKNOWN
                : BRE_RISK_VIOLATION_RISK_DATA_UNSAFE;
         detail="Current basket risk is not safe for projection";
         CProjectedBasketRisk projected=CProjectedBasketRisk::Create(current,0.0,0.0,current.SafetyStatus());
         return CRiskValidationResult::Rejected(reason,detail,current,projected,CRiskReductionPlan::CreateEmpty());
        }

      CRiskReductionPlan reductionPlan=CRiskReductionPlanner::Plan(current,context);
      CProjectedBasketRisk projected=CProjectedRiskCalculator::ProjectForRequest(current,request,context);
      if(projected.SafetyStatus()!=BRE_RISK_SAFETY_SAFE)
        {
         return CRiskValidationResult::Rejected(BRE_RISK_VIOLATION_RISK_DATA_UNKNOWN,
                                                "Projected risk could not be calculated safely",
                                                current,
                                                projected,
                                                reductionPlan);
        }

      if(projected.ExceedsMaxRisk())
        {
         return CRiskValidationResult::Rejected(BRE_RISK_VIOLATION_PROJECTED_EXCEEDS_MAX,
                                                "Projected SL risk exceeds hard max risk",
                                                current,
                                                projected,
                                                reductionPlan);
        }

      return CRiskValidationResult::AllowedResult(current,projected,reductionPlan);
     }
  };

#endif
