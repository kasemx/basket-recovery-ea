#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Domain/Strategy/Validation/StrategyProfileValidator.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

void TestValidProfile(void)
  {
   CStrategyProfileValidator validator;
   CStrategyProfile profile=CStrategyProfileTestFixture::BuildValidProfile();
   CTestAssert::True(validator.Validate(profile).IsOk(),"Valid strategy profile must pass validation");
  }

void TestInvalidRiskMaxBelowTarget(void)
  {
   CStrategyProfile base=CStrategyProfileTestFixture::BuildValidProfile();
   CRiskPlan invalidRisk=CRiskPlan::Create(1.2,1.0,0.95,true,BRE_RISK_REDUCTION_MODE_WORST_ENTRY,0.0,false,30,100);
   CStrategyProfile profile=CStrategyProfile::Create(base.StrategyId(),
                                                     base.SchemaVersion(),
                                                     base.Metadata(),
                                                     base.ExecutionZone(),
                                                     base.RecoveryPlan(),
                                                     base.ProfitDistributionPlan(),
                                                     base.BreakEvenPlan(),
                                                     invalidRisk,
                                                     base.ExecutionPolicy(),
                                                     base.BoundAt());
   CStrategyProfileValidator validator;
   CVoidResult result=validator.Validate(profile);
   CTestAssert::False(result.IsOk(),"Max risk below target must fail validation");
   CTestAssert::EqualInt(BRE_ERR_STRATEGY_VALIDATION_FAILED,result.ErrorCode(),"Risk validation must use strategy validation error code");
  }

void TestDuplicateProfitLevelId(void)
  {
   CProfitLevel levels[2];
   levels[0]=CProfitLevel::Create("L1",1,BRE_PROFIT_LEVEL_SOURCE_SIGNAL_TP,0.0,false,33.0,BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true);
   levels[1]=CProfitLevel::Create("L1",2,BRE_PROFIT_LEVEL_SOURCE_SIGNAL_TP,0.0,false,66.0,BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true);
   CProfitDistributionPlan profitPlan=CProfitDistributionPlan::Create(true,BRE_CLOSE_MODE_WORST_ENTRY_FIRST,levels,2);

   CStrategyProfile base=CStrategyProfileTestFixture::BuildValidProfile();
   CStrategyProfile profile=CStrategyProfile::Create(base.StrategyId(),
                                                     base.SchemaVersion(),
                                                     base.Metadata(),
                                                     base.ExecutionZone(),
                                                     base.RecoveryPlan(),
                                                     profitPlan,
                                                     base.BreakEvenPlan(),
                                                     base.RiskPlan(),
                                                     base.ExecutionPolicy(),
                                                     base.BoundAt());
   CStrategyProfileValidator validator;
   CTestAssert::False(validator.Validate(profile).IsOk(),"Duplicate profit level id must fail validation");
  }

void TestInvalidClosePercent(void)
  {
   CProfitLevel levels[1];
   levels[0]=CProfitLevel::Create("L1",1,BRE_PROFIT_LEVEL_SOURCE_SIGNAL_TP,0.0,false,150.0,BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true);
   CProfitDistributionPlan profitPlan=CProfitDistributionPlan::Create(true,BRE_CLOSE_MODE_WORST_ENTRY_FIRST,levels,1);
   CStrategyProfile base=CStrategyProfileTestFixture::BuildValidProfile();
   CStrategyProfile profile=CStrategyProfile::Create(base.StrategyId(),
                                                     base.SchemaVersion(),
                                                     base.Metadata(),
                                                     base.ExecutionZone(),
                                                     base.RecoveryPlan(),
                                                     profitPlan,
                                                     base.BreakEvenPlan(),
                                                     base.RiskPlan(),
                                                     base.ExecutionPolicy(),
                                                     base.BoundAt());
   CStrategyProfileValidator validator;
   CTestAssert::False(validator.Validate(profile).IsOk(),"Close percent above 100 must fail validation");
  }

void TestBreakEvenMissingProfitLevelReference(void)
  {
   CBreakEvenTrigger trigger=CBreakEvenTrigger::Create(BRE_BE_TRIGGER_SPECIFIC_PROFIT_LEVEL,0.0,false,0.0,false,0.0,false,"MISSING","","","");
   CBreakEvenAction actions[1];
   actions[0]=CBreakEvenAction::Create(BRE_BE_ACTION_DISABLE_RECOVERY,0.0,0.0,false,false);
   CBreakEvenRule rules[1];
   rules[0]=CBreakEvenRule::Create("BE_MISSING",true,1,true,trigger,actions,1);
   CBreakEvenPlan breakEvenPlan=CBreakEvenPlan::Create(rules,1);

   CStrategyProfile base=CStrategyProfileTestFixture::BuildValidProfile();
   CStrategyProfile profile=CStrategyProfile::Create(base.StrategyId(),
                                                     base.SchemaVersion(),
                                                     base.Metadata(),
                                                     base.ExecutionZone(),
                                                     base.RecoveryPlan(),
                                                     base.ProfitDistributionPlan(),
                                                     breakEvenPlan,
                                                     base.RiskPlan(),
                                                     base.ExecutionPolicy(),
                                                     base.BoundAt());
   CStrategyProfileValidator validator;
   CTestAssert::False(validator.Validate(profile).IsOk(),"Break-even missing profit level reference must fail validation");
  }

void TestCustomRecoveryWithoutSteps(void)
  {
   CRecoveryStep steps[];
   ArrayResize(steps,0);
   CRecoveryPlan recovery=CRecoveryPlan::CreateCustom(steps,0,true,true,3,0.01);
   CStrategyProfile base=CStrategyProfileTestFixture::BuildValidProfile();
   CStrategyProfile profile=CStrategyProfile::Create(base.StrategyId(),
                                                     base.SchemaVersion(),
                                                     base.Metadata(),
                                                     base.ExecutionZone(),
                                                     recovery,
                                                     base.ProfitDistributionPlan(),
                                                     base.BreakEvenPlan(),
                                                     base.RiskPlan(),
                                                     base.ExecutionPolicy(),
                                                     base.BoundAt());
   CStrategyProfileValidator validator;
   CTestAssert::False(validator.Validate(profile).IsOk(),"Custom recovery without steps must fail validation");
  }

void TestNonMonotonicRecoveryDistances(void)
  {
   CRecoveryStep steps[2];
   steps[0]=CRecoveryStep::Create(1,0.6,0.01);
   steps[1]=CRecoveryStep::Create(2,0.4,0.01);
   CRecoveryPlan recovery=CRecoveryPlan::CreateCustom(steps,2,true,true,3,0.01);
   CStrategyProfile base=CStrategyProfileTestFixture::BuildValidProfile();
   CStrategyProfile profile=CStrategyProfile::Create(base.StrategyId(),
                                                     base.SchemaVersion(),
                                                     base.Metadata(),
                                                     base.ExecutionZone(),
                                                     recovery,
                                                     base.ProfitDistributionPlan(),
                                                     base.BreakEvenPlan(),
                                                     base.RiskPlan(),
                                                     base.ExecutionPolicy(),
                                                     base.BoundAt());
   CStrategyProfileValidator validator;
   CTestAssert::False(validator.Validate(profile).IsOk(),"Non-monotonic recovery distances must fail validation");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestValidProfile();
   TestInvalidRiskMaxBelowTarget();
   TestDuplicateProfitLevelId();
   TestInvalidClosePercent();
   TestBreakEvenMissingProfitLevelReference();
   TestCustomRecoveryWithoutSteps();
   TestNonMonotonicRecoveryDistances();
   CTestAssert::Summary("TestStrategyProfileValidation");
   if(!CTestAssert::AllPassed())
      Print("TestStrategyProfileValidation FAILED");
  }
