#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileMigrator.mqh>
#include <BasketRecovery/Domain/Strategy/Validation/StrategyProfileValidator.mqh>
#include <BasketRecovery/Shared/Constants/StrategySchema.mqh>

void TestV1ToV2Migration(void)
  {
   CProfileBundle bundle=CStrategyProfileTestFixture::BuildDefaultV1Bundle();
   CStrategyProfileMigrator migrator;
   CResult<CStrategyProfile> result=migrator.MigrateFromBundle(bundle);
   CTestAssert::True(result.IsOk(),"Default v1 bundle migration must succeed");

   CStrategyProfile profile;
   CTestAssert::True(result.TryGetValue(profile),"Migrated profile must exist");
   CTestAssert::EqualString(BRE_STRATEGY_DEFAULT_ID,profile.StrategyId(),"Default bundle must map to default-recovery-v1 id");
   CTestAssert::EqualInt(BRE_STRATEGY_SCHEMA_VERSION,profile.SchemaVersion(),"Migrated profile must use schema v2");

   CStrategyProfileValidator validator;
   CTestAssert::True(validator.Validate(profile).IsOk(),"Migrated profile must pass validation");
  }

void TestMigrationSemanticDefaults(void)
  {
   CStrategyProfileMigrator migrator;
   CStrategyProfile profile;
   migrator.MigrateFromBundle(CStrategyProfileTestFixture::BuildDefaultV1Bundle()).TryGetValue(profile);

   CTestAssert::EqualDouble(1.0,profile.RiskPlan().TargetRiskPct(),0.0001,"Migrated target risk must be 1.0");
   CTestAssert::EqualDouble(1.2,profile.RiskPlan().MaxRiskPct(),0.0001,"Migrated max risk must be 1.2");
   CTestAssert::EqualInt(3,profile.ProfitDistributionPlan().LevelCount(),"Migrated profile must contain 3 profit levels");
   CTestAssert::EqualString("L1",profile.ProfitDistributionPlan().LevelAt(0).LevelId(),"First profit level must be L1");
   CTestAssert::True(profile.RecoveryPlan().DisableAfterBreakEven(),"Migrated recovery must disable after break-even");
   CTestAssert::EqualInt(50,profile.RecoveryPlan().StepCount(),"Migrated recovery must contain 50 linear steps");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestV1ToV2Migration();
   TestMigrationSemanticDefaults();
   CTestAssert::Summary("TestStrategyProfileMigrator");
   if(!CTestAssert::AllPassed())
      Print("TestStrategyProfileMigrator FAILED");
  }
