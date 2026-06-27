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
   CTestAssert::False(StringFind(exported,"TP1")>=0,"Production rules must not depend on TP1");
  }

void TestLifecycleRules(void)
  {
   CTransitionTestFixture fixture;
   CTestAssert::True(fixture.Initialize(),"Fixture initialization failed");
   fixture.AssertRuleApplied(BRE_STATE_PENDING_OPEN,BRE_EVENT_INITIAL_POSITIONS_OPENED,BRE_STATE_WAIT_DETAILS);
   fixture.AssertRuleApplied(BRE_STATE_PENDING_OPEN,BRE_EVENT_COMMAND_FAILED,BRE_STATE_ERROR);
   fixture.AssertRuleApplied(BRE_STATE_WAIT_DETAILS,BRE_EVENT_BASKET_ACTIVATED,BRE_STATE_ACTIVE);
   fixture.AssertRuleApplied(BRE_STATE_ACTIVE,BRE_EVENT_MAX_RISK_REACHED,BRE_STATE_SUSPENDED);
   fixture.AssertRuleApplied(BRE_STATE_ACTIVE,BRE_EVENT_ALL_POSITIONS_CLOSED,BRE_STATE_FINISHED);
   fixture.AssertRuleApplied(BRE_STATE_CLOSING,BRE_EVENT_ALL_POSITIONS_CLOSED,BRE_STATE_FINISHED);
   fixture.AssertRuleApplied(BRE_STATE_SUSPENDED,BRE_EVENT_RISK_REDUCED,BRE_STATE_ACTIVE);
  }

void TestRejectedEvents(void)
  {
   CTransitionTestFixture fixture;
   CTestAssert::True(fixture.Initialize(),"Fixture initialization failed");
   fixture.AssertRuleRejected(BRE_STATE_WAIT_DETAILS,BRE_EVENT_PROFIT_LEVEL_REACHED);
   fixture.AssertRuleRejected(BRE_STATE_ACTIVE,BRE_EVENT_BASKET_ACTIVATED);
   fixture.AssertRuleRejected(BRE_STATE_FINISHED,BRE_EVENT_PROFIT_LEVEL_REACHED);
   fixture.AssertRuleRejected(BRE_STATE_ERROR,BRE_EVENT_BASKET_ACTIVATED);
  }

void TestDuplicateRuleDetection(void)
  {
   CTransitionRuleRegistry registry;
   CAlwaysTrueTransitionGuard guard;
   CTransitionRule rule;
   rule.SetRuleId("dup-test");
   rule.SetCurrentState(BRE_STATE_ACTIVE);
   rule.SetAllowedEvent(BRE_EVENT_PROFIT_LEVEL_REACHED);
   rule.SetNextState(BRE_STATE_ACTIVE);
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
