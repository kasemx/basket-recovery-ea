#ifndef BRE_DOMAIN_BASKET_RECONCILIATION_APPLY_OUTCOME_MQH
#define BRE_DOMAIN_BASKET_RECONCILIATION_APPLY_OUTCOME_MQH

#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>

struct SBasketReconciliationApplyOutcome
  {
   ENUM_BRE_BASKET_LIFECYCLE_STATE lifecycle_before;
   ENUM_BRE_BASKET_LIFECYCLE_STATE lifecycle_after;
   bool                            reconciliation_clean;
   string                          blocking_reason;
   bool                            resume_attempted;
   bool                            resume_result;
   string                          resume_failure_reason;
   bool                            max_risk_lockout;
   int                             unresolved_execution_count;
   int                             current_ticket_unresolved_count;
   int                             foreign_ticket_unresolved_count;
   int                             orphan_position_count;
   int                             missing_position_count;
   int                             mismatch_position_count;
   ulong                           expected_ticket;
   ulong                           live_ticket;
   double                          expected_volume;
   double                          live_volume;
   string                          persisted_basket_write_result;
   string                          snapshot_write_result;

   void Reset(void)
     {
      lifecycle_before=BRE_STATE_NONE;
      lifecycle_after=BRE_STATE_NONE;
      reconciliation_clean=false;
      blocking_reason="";
      resume_attempted=false;
      resume_result=false;
      resume_failure_reason="";
      max_risk_lockout=false;
      unresolved_execution_count=0;
      current_ticket_unresolved_count=0;
      foreign_ticket_unresolved_count=0;
      orphan_position_count=0;
      missing_position_count=0;
      mismatch_position_count=0;
      expected_ticket=0;
      live_ticket=0;
      expected_volume=0.0;
      live_volume=0.0;
      persisted_basket_write_result="";
      snapshot_write_result="";
     }
  };

#endif
