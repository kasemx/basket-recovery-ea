#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryPlanResolver.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryStep.mqh>

void TestCustomRecoveryStep(void)
  {
   CRecoveryStep steps[2];
   steps[0]=CRecoveryStep::Create(1,0.2,0.01);
   steps[1]=CRecoveryStep::Create(2,0.4,0.02);
   CRecoveryPlan plan=CRecoveryPlan::CreateCustom(steps,2,true,true,3,0.01);
   CRecoveryPlanResolver resolver;
   CRecoveryPlanResolution resolution=resolver.ResolveNextStep(plan,0);
   CTestAssert::True(resolution.HasStep(),"Custom recovery must resolve first step");
   CTestAssert::EqualInt(1,resolution.Step().StepIndex(),"Custom step index must be 1");
   CTestAssert::EqualDouble(0.2,resolution.Step().DistancePips(),0.0001,"Custom step distance must match");
  }

void TestConstantRecoveryStep(void)
  {
   CRecoveryPlan plan=CRecoveryPlan::CreateConstant(0.2,0.01,50,true,true,true,3,0.01);
   CRecoveryPlanResolver resolver;
   CRecoveryPlanResolution step2=resolver.ResolveNextStep(plan,1);
   CTestAssert::True(step2.HasStep(),"Constant recovery must resolve step 2");
   CTestAssert::EqualDouble(0.4,step2.Step().DistancePips(),0.0001,"Constant step 2 distance must be cumulative");
  }

void TestLinearRecoveryStep(void)
  {
   CRecoveryPlan plan=CRecoveryPlan::CreateLinear(0.2,0.2,0.01,0.0,50,true,true,true,3,0.01);
   CRecoveryPlanResolver resolver;
   CRecoveryPlanResolution step3=resolver.ResolveNextStep(plan,2);
   CTestAssert::True(step3.HasStep(),"Linear recovery must resolve step 3");
   CTestAssert::EqualDouble(0.6,step3.Step().DistancePips(),0.0001,"Linear step 3 distance must be 0.6");
  }

void TestProgressiveRecoveryStep(void)
  {
   CRecoveryPlan plan=CRecoveryPlan::CreateProgressive(0.2,1.0,0.01,1.0,50,true,true,true,3,0.01);
   CRecoveryPlanResolver resolver;
   CRecoveryPlanResolution step2=resolver.ResolveNextStep(plan,1);
   CTestAssert::True(step2.HasStep(),"Progressive recovery must resolve step 2");
   CTestAssert::EqualDouble(0.4,step2.Step().DistancePips(),0.0001,"Progressive step 2 distance must be 0.4");
   CTestAssert::EqualDouble(0.02,step2.Step().Lot(),0.0001,"Progressive step 2 lot must be 0.02");
  }

void TestUnsupportedAtr(void)
  {
   CRecoveryPlan plan=CRecoveryPlan::CreatePlaceholder(BRE_RECOVERY_ALGORITHM_ATR,true,true,3,0.01);
   CRecoveryPlanResolver resolver;
   CRecoveryPlanResolution resolution=resolver.ResolveNextStep(plan,0);
   CTestAssert::False(resolution.Supported(),"ATR recovery must be unsupported");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestCustomRecoveryStep();
   TestConstantRecoveryStep();
   TestLinearRecoveryStep();
   TestProgressiveRecoveryStep();
   TestUnsupportedAtr();
   CTestAssert::Summary("TestRecoveryPlanResolver");
  }
