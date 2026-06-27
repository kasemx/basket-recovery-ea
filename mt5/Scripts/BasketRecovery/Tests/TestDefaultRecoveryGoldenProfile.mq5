#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonLoader.mqh>
#include <BasketRecovery/Domain/Strategy/Validation/StrategyProfileValidator.mqh>
#include <BasketRecovery/Shared/Constants/StrategySchema.mqh>

void TestGoldenProfileSemanticCheck(void)
  {
   CStrategyProfileJsonLoader loader;
   CResult<CStrategyProfile> result=loader.LoadFromStrategyId(BRE_STRATEGY_DEFAULT_ID);
   CTestAssert::True(result.IsOk(),"Golden profile must load");

   CStrategyProfile profile;
   CTestAssert::True(result.TryGetValue(profile),"Golden profile object must exist");

   CStrategyProfileValidator validator;
   CTestAssert::True(validator.Validate(profile).IsOk(),"Golden profile must pass validation");

   CTestAssert::EqualString(BRE_STRATEGY_DEFAULT_ID,profile.StrategyId(),"Golden strategy id must match");
   CTestAssert::EqualInt(BRE_STRATEGY_SCHEMA_VERSION,profile.SchemaVersion(),"Golden schema version must be 2");
   CTestAssert::EqualDouble(1.0,profile.RiskPlan().TargetRiskPct(),0.0001,"Golden target risk must be 1.0");
   CTestAssert::EqualDouble(1.2,profile.RiskPlan().MaxRiskPct(),0.0001,"Golden max risk must be 1.2");

   CExecutionZone zone=profile.ExecutionZone();
   CTestAssert::EqualInt(BRE_EXECUTION_ZONE_SOURCE_SIGNAL_RANGE,zone.Source(),"Golden execution zone must use signal range");
   CTestAssert::EqualInt(BRE_ZONE_EXPANSION_SYMMETRIC,zone.ExpansionMode(),"Golden expansion must be symmetric");
   CTestAssert::EqualDouble(3.0,zone.AboveEntryPips(),0.0001,"Golden above expansion must be 3 pips");
   CTestAssert::False(zone.ExpansionDisabled(),"Golden expansion must be enabled");

   CRecoveryPlan recovery=profile.RecoveryPlan();
   CTestAssert::EqualInt(BRE_RECOVERY_ALGORITHM_CUSTOM,recovery.Algorithm(),"Golden recovery must be custom");
   CTestAssert::EqualInt(4,recovery.StepCount(),"Golden recovery must define 4 custom steps");
   CTestAssert::True(recovery.DisableAfterBreakEven(),"Golden recovery must disable after break-even");
   CTestAssert::EqualDouble(1.0,recovery.StepAt(3).DistancePips(),0.0001,"Golden step 4 distance must be 1.0 pip");

   CProfitDistributionPlan profitPlan=profile.ProfitDistributionPlan();
   CTestAssert::EqualInt(3,profitPlan.LevelCount(),"Golden profile must define 3 profit levels");
   CTestAssert::EqualDouble(33.0,profitPlan.LevelAt(0).ClosePercent(),0.0001,"Golden L1 close percent must be 33");
   CTestAssert::EqualInt(BRE_PROFIT_LEVEL_SOURCE_SIGNAL_TP,profitPlan.LevelAt(0).Source(),"Golden L1 must use signal TP source");

   CBreakEvenPlan breakEvenPlan=profile.BreakEvenPlan();
   CTestAssert::EqualInt(1,breakEvenPlan.RuleCount(),"Golden profile must define one break-even rule");
   CBreakEvenRule rule=breakEvenPlan.RuleAt(0);
   CTestAssert::EqualString("BE_AFTER_L1",rule.RuleId(),"Golden break-even rule id must match");
   CTestAssert::EqualInt(BRE_BE_TRIGGER_SPECIFIC_PROFIT_LEVEL,rule.Trigger().Type(),"Golden BE trigger must reference profit level");
   CTestAssert::EqualString("L1",rule.Trigger().ProfitLevelId(),"Golden BE trigger must reference L1");
   CTestAssert::EqualInt(2,rule.ActionCount(),"Golden BE rule must contain two actions");
   CTestAssert::EqualInt(BRE_BE_ACTION_DISABLE_RECOVERY,rule.ActionAt(1).Type(),"Golden BE must disable recovery");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestGoldenProfileSemanticCheck();
   CTestAssert::Summary("TestDefaultRecoveryGoldenProfile");
   if(!CTestAssert::AllPassed())
      Print("TestDefaultRecoveryGoldenProfile FAILED");
  }
