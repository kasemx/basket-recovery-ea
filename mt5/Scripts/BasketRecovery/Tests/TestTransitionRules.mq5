#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TransitionTestFixture.mqh>
#include <BasketRecovery/Application/Kernel/TransitionRuleRegistry.mqh>
#include <BasketRecovery/Domain/StateMachine/TransitionRule.mqh>
#include <BasketRecovery/Domain/StateMachine/AlwaysTrueTransitionGuard.mqh>

void TestRegistryValidation(void)
  {
   CTransitionTestFixture fixture;
   CTestAssert::True(fixture.Initialize(),"Fixture initialization failed");
   CTestAssert::True(fixture.Registry().RuleCount()>0,"Default rule table must not be empty");

   string exported=fixture.Registry().ExportTable();
   CTestAssert::True(StringFind(exported,"TransitionRuleTable")>=0,"ExportTable must include header");
  }

void TestLifecycleRules(void)
  {
   CTransitionTestFixture fixture;
   CTestAssert::True(fixture.Initialize(),"Fixture initialization failed");

   fixture.AssertRuleApplied(BRE_STATE_PENDING_OPEN,BRE_EVENT_INITIAL_POSITIONS_OPENED,BRE_STATE_WAIT_DETAILS);
   fixture.AssertRuleApplied(BRE_STATE_PENDING_OPEN,BRE_EVENT_COMMAND_FAILED,BRE_STATE_ERROR);
   fixture.AssertRuleApplied(BRE_STATE_WAIT_DETAILS,BRE_EVENT_BASKET_ACTIVATED,BRE_STATE_ACTIVE);
   fixture.AssertRuleApplied(BRE_STATE_ACTIVE,BRE_EVENT_TP1_REACHED,BRE_STATE_TP1);
   fixture.AssertRuleApplied(BRE_STATE_TP1,BRE_EVENT_BREAK_EVEN_ACTIVATED,BRE_STATE_BREAK_EVEN);
   fixture.AssertRuleApplied(BRE_STATE_TP1,BRE_EVENT_TP2_REACHED,BRE_STATE_TP2);
   fixture.AssertRuleApplied(BRE_STATE_TP2,BRE_EVENT_TP3_REACHED,BRE_STATE_TP3);
   fixture.AssertRuleApplied(BRE_STATE_TP3,BRE_EVENT_ALL_POSITIONS_CLOSED,BRE_STATE_FINISHED);
   fixture.AssertRuleApplied(BRE_STATE_CLOSING,BRE_EVENT_ALL_POSITIONS_CLOSED,BRE_STATE_FINISHED);
   fixture.AssertRuleApplied(BRE_STATE_SUSPENDED,BRE_EVENT_RISK_REDUCED,BRE_STATE_ACTIVE);
  }

void TestRejectedEvents(void)
  {
   CTransitionTestFixture fixture;
   CTestAssert::True(fixture.Initialize(),"Fixture initialization failed");

   fixture.AssertRuleRejected(BRE_STATE_WAIT_DETAILS,BRE_EVENT_TP1_REACHED);
   fixture.AssertRuleRejected(BRE_STATE_ACTIVE,BRE_EVENT_BASKET_ACTIVATED);
   fixture.AssertRuleRejected(BRE_STATE_BREAK_EVEN,BRE_EVENT_RECOVERY_STEP_CROSSED);
   fixture.AssertRuleRejected(BRE_STATE_FINISHED,BRE_EVENT_TP1_REACHED);
   fixture.AssertRuleRejected(BRE_STATE_ERROR,BRE_EVENT_BASKET_ACTIVATED);
  }

void TestDuplicateRuleDetection(void)
  {
   CTransitionRuleRegistry registry;
   CAlwaysTrueTransitionGuard guard;

   CTransitionRule rule;
   rule.SetRuleId("dup-test");
   rule.SetCurrentState(BRE_STATE_ACTIVE);
   rule.SetAllowedEvent(BRE_EVENT_TP1_REACHED);
   rule.SetNextState(BRE_STATE_TP1);
   rule.SetGuard(&guard);

   CTestAssert::True(registry.RegisterRule(rule).IsOk(),"First duplicate test rule must register");
   CTestAssert::True(registry.RegisterRule(rule).IsFail(),"Duplicate rule must be rejected");
  }

void TestTableDrivenRules(void)
  {
   CTransitionTestFixture fixture;
   CTestAssert::True(fixture.Initialize(),"Fixture initialization failed");

   CTransitionRule rule;
   for(int i=0;i<fixture.Registry().RuleCount();i++)
     {
      CTestAssert::True(fixture.Registry().GetRuleAt(i,rule),"Rule must exist at index");
      fixture.AssertRuleApplied(rule.CurrentState(),rule.AllowedEvent(),rule.NextState());
     }
  }

void OnStart()
  {
   CTestAssert::Reset();

   TestRegistryValidation();
   TestLifecycleRules();
   TestRejectedEvents();
   TestDuplicateRuleDetection();
   TestTableDrivenRules();

   CTestAssert::Summary("TestTransitionRules");
   if(!CTestAssert::AllPassed())
      Print("TestTransitionRules FAILED");
  }
