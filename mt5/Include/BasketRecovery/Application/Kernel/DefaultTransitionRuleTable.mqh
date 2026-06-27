#ifndef BASKET_RECOVERY_APPLICATION_DEFAULT_TRANSITION_RULE_TABLE_MQH
#define BASKET_RECOVERY_APPLICATION_DEFAULT_TRANSITION_RULE_TABLE_MQH

#include <BasketRecovery/Application/Kernel/TransitionRuleRegistry.mqh>
#include <BasketRecovery/Domain/StateMachine/AlwaysTrueTransitionGuard.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CDefaultTransitionRuleTable
  {
private:
   static CTransitionRule MakeRule(const string ruleId,
                                   const ENUM_BRE_BASKET_LIFECYCLE_STATE currentState,
                                   const ENUM_BRE_EVENT_TYPE allowedEvent,
                                   const ENUM_BRE_BASKET_LIFECYCLE_STATE nextState,
                                   ITransitionGuard *guard,
                                   const int priority,
                                   const string description)
     {
      CTransitionRule rule;
      rule.SetRuleId(ruleId);
      rule.SetCurrentState(currentState);
      rule.SetAllowedEvent(allowedEvent);
      rule.SetNextState(nextState);
      rule.SetGuard(guard);
      rule.SetPriority(priority);
      rule.SetErrorCode(BRE_ERR_TRANSITION_GUARD_FAILED);
      rule.SetDescription(description);
      return rule;
     }

   static CVoidResult RegisterLifecycleRules(CTransitionRuleRegistry &registry,
                                             ITransitionGuard *guard)
     {
      CVoidResult result;

      result=registry.RegisterRule(MakeRule("PO-001",BRE_STATE_PENDING_OPEN,BRE_EVENT_INITIAL_POSITIONS_OPENED,
                                            BRE_STATE_WAIT_DETAILS,guard,10,"Initial positions opened"));
      if(result.IsFail()) return result;
      result=registry.RegisterRule(MakeRule("PO-002",BRE_STATE_PENDING_OPEN,BRE_EVENT_COMMAND_FAILED,
                                            BRE_STATE_ERROR,guard,100,"Open command exhausted"));
      if(result.IsFail()) return result;
      result=registry.RegisterRule(MakeRule("PO-003",BRE_STATE_PENDING_OPEN,BRE_EVENT_CLOSE_BASKET_REQUESTED,
                                            BRE_STATE_CLOSING,guard,90,"Close basket requested"));
      if(result.IsFail()) return result;

      result=registry.RegisterRule(MakeRule("WD-001",BRE_STATE_WAIT_DETAILS,BRE_EVENT_BASKET_ACTIVATED,
                                            BRE_STATE_ACTIVE,guard,10,"Basket activated with details"));
      if(result.IsFail()) return result;
      result=registry.RegisterRule(MakeRule("WD-002",BRE_STATE_WAIT_DETAILS,BRE_EVENT_WAIT_DETAILS_TIMEOUT,
                                            BRE_STATE_CLOSING,guard,20,"Wait details timeout"));
      if(result.IsFail()) return result;
      result=registry.RegisterRule(MakeRule("WD-003",BRE_STATE_WAIT_DETAILS,BRE_EVENT_CLOSE_BASKET_REQUESTED,
                                            BRE_STATE_CLOSING,guard,90,"Close basket requested"));
      if(result.IsFail()) return result;
      result=registry.RegisterRule(MakeRule("WD-004",BRE_STATE_WAIT_DETAILS,BRE_EVENT_COMMAND_FAILED,
                                            BRE_STATE_ERROR,guard,100,"Critical command failure"));
      if(result.IsFail()) return result;

      result=registry.RegisterRule(MakeRule("AC-001",BRE_STATE_ACTIVE,BRE_EVENT_MAX_RISK_REACHED,
                                            BRE_STATE_SUSPENDED,guard,50,"Max risk reached"));
      if(result.IsFail()) return result;
      result=registry.RegisterRule(MakeRule("AC-002",BRE_STATE_ACTIVE,BRE_EVENT_CLOSE_BASKET_REQUESTED,
                                            BRE_STATE_CLOSING,guard,90,"Close basket requested"));
      if(result.IsFail()) return result;
      result=registry.RegisterRule(MakeRule("AC-003",BRE_STATE_ACTIVE,BRE_EVENT_COMMAND_FAILED,
                                            BRE_STATE_ERROR,guard,100,"Critical command failure"));
      if(result.IsFail()) return result;
      result=registry.RegisterRule(MakeRule("AC-004",BRE_STATE_ACTIVE,BRE_EVENT_ALL_POSITIONS_CLOSED,
                                            BRE_STATE_FINISHED,guard,80,"All positions closed while active"));
      if(result.IsFail()) return result;

      result=registry.RegisterRule(MakeRule("CL-001",BRE_STATE_CLOSING,BRE_EVENT_ALL_POSITIONS_CLOSED,
                                            BRE_STATE_FINISHED,guard,80,"Closing completed"));
      if(result.IsFail()) return result;

      result=registry.RegisterRule(MakeRule("SU-001",BRE_STATE_SUSPENDED,BRE_EVENT_RISK_REDUCED,
                                            BRE_STATE_ACTIVE,guard,10,"Risk reduced below max"));
      if(result.IsFail()) return result;
      result=registry.RegisterRule(MakeRule("SU-002",BRE_STATE_SUSPENDED,BRE_EVENT_CLOSE_BASKET_REQUESTED,
                                            BRE_STATE_CLOSING,guard,90,"Close basket requested"));
      if(result.IsFail()) return result;

      return CVoidResult::Ok();
     }

   static CVoidResult RegisterRejectedEvents(CTransitionRuleRegistry &registry)
     {
      CVoidResult result;

      result=registry.RegisterRejectedEvent(BRE_STATE_WAIT_DETAILS,BRE_EVENT_RECOVERY_STEP_CROSSED);
      if(result.IsFail()) return result;
      result=registry.RegisterRejectedEvent(BRE_STATE_WAIT_DETAILS,BRE_EVENT_PROFIT_LEVEL_REACHED);
      if(result.IsFail()) return result;
      result=registry.RegisterRejectedEvent(BRE_STATE_WAIT_DETAILS,BRE_EVENT_TARGET_RISK_REACHED);
      if(result.IsFail()) return result;
      result=registry.RegisterRejectedEvent(BRE_STATE_WAIT_DETAILS,BRE_EVENT_BREAK_EVEN_ACTIVATED);
      if(result.IsFail()) return result;

      result=registry.RegisterRejectedEvent(BRE_STATE_ACTIVE,BRE_EVENT_BASKET_ACTIVATED);
      if(result.IsFail()) return result;
      result=registry.RegisterRejectedEvent(BRE_STATE_ACTIVE,BRE_EVENT_INITIAL_POSITIONS_OPENED);
      if(result.IsFail()) return result;

      result=registry.RegisterRejectedEvent(BRE_STATE_CLOSING,BRE_EVENT_RECOVERY_STEP_CROSSED);
      if(result.IsFail()) return result;
      result=registry.RegisterRejectedEvent(BRE_STATE_CLOSING,BRE_EVENT_PROFIT_LEVEL_REACHED);
      if(result.IsFail()) return result;

      result=registry.RegisterRejectedEvent(BRE_STATE_SUSPENDED,BRE_EVENT_RECOVERY_STEP_CROSSED);
      if(result.IsFail()) return result;

      return CVoidResult::Ok();
     }

public:
   static CVoidResult RegisterDefaultRules(CTransitionRuleRegistry &registry,
                                           ITransitionGuard *defaultGuard)
     {
      ITransitionGuard *guard=defaultGuard;
      if(guard==NULL)
         return CVoidResult::Fail(BRE_ERR_TRANSITION_INVALID,"Default guard is null");

      CVoidResult lifecycleResult=RegisterLifecycleRules(registry,guard);
      if(lifecycleResult.IsFail())
         return lifecycleResult;

      return RegisterRejectedEvents(registry);
     }
  };

#endif
