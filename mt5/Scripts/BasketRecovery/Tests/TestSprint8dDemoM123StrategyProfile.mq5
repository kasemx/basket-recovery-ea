#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Validation/Sprint8D/Sprint8dDemoM123StrategyProfile.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Domain/Strategy/Validation/StrategyProfileValidator.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ExecutionZoneExpansionMode.mqh>
#include <BasketRecovery/Domain/Execution/ProfitCloseCandidateCloseVolumeCalculator.mqh>

void TestCanonicalJsonParsesAndValidates(void)
  {
   string json=CSprint8dDemoM123StrategyProfile::CanonicalJson();
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(json,CUtcTime(1000));
   CTestAssert::True(profileResult.IsOk(),"Canonical JSON must parse");
   CStrategyProfile profile;
   CTestAssert::True(profileResult.TryGetValue(profile),"Canonical profile object must exist");
   CStrategyProfileValidator validator;
   CTestAssert::True(validator.Validate(profile).IsOk(),"Canonical profile must validate");
   CTestAssert::EqualString(CSprint8dDemoM123StrategyProfile::StrategyId(),profile.StrategyId(),
                            "strategy_id must match exactly");
  }

void TestCanonicalHashMatchesExpected(void)
  {
   string json=CSprint8dDemoM123StrategyProfile::CanonicalJson();
   string computed=CStrategyProfileCanonicalSerializer::ComputeHash(json);
   CTestAssert::EqualString(CSprint8dDemoM123StrategyProfile::ExpectedHash(),computed,
                            "Computed hash must equal ExpectedHash");
  }

void TestProfitLevelsMatchControlledDemoContract(void)
  {
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(CSprint8dDemoM123StrategyProfile::CanonicalJson(),CUtcTime(1000));
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   CProfitDistributionPlan plan=profile.ProfitDistributionPlan();
   CTestAssert::EqualInt(3,plan.LevelCount(),"Profile must define exactly three profit levels");
   CTestAssert::EqualString("M1",plan.LevelAt(0).LevelId(),"M1 level id");
   CTestAssert::EqualString("M2",plan.LevelAt(1).LevelId(),"M2 level id");
   CTestAssert::EqualString("M3",plan.LevelAt(2).LevelId(),"M3 level id");
   CTestAssert::EqualInt(1,plan.LevelAt(0).LevelIndex(),"M1 level index");
   CTestAssert::EqualInt(2,plan.LevelAt(1).LevelIndex(),"M2 level index");
   CTestAssert::EqualInt(3,plan.LevelAt(2).LevelIndex(),"M3 level index");
   CTestAssert::EqualDouble(33.0,plan.LevelAt(0).ClosePercent(),0.0000001,"M1 close percent");
   CTestAssert::EqualDouble(50.0,plan.LevelAt(1).ClosePercent(),0.0000001,"M2 close percent");
   CTestAssert::EqualDouble(34.0,plan.LevelAt(2).ClosePercent(),0.0000001,"M3 close percent");
   CTestAssert::EqualInt((int)BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,(int)plan.LevelAt(0).Source(),"M1 source");
   CTestAssert::EqualInt((int)BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,(int)plan.LevelAt(1).Source(),"M2 source");
   CTestAssert::EqualInt((int)BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,(int)plan.LevelAt(2).Source(),"M3 source");
   CTestAssert::EqualInt((int)BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,(int)plan.LevelAt(0).TriggerType(),"M1 trigger type");
   CTestAssert::EqualInt((int)BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,(int)plan.LevelAt(1).TriggerType(),"M2 trigger type");
   CTestAssert::EqualInt((int)BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,(int)plan.LevelAt(2).TriggerType(),"M3 trigger type");
   CTestAssert::EqualDouble(10.0,plan.LevelAt(0).TriggerValue(),0.0000001,"M1 trigger value");
   CTestAssert::EqualDouble(20.0,plan.LevelAt(1).TriggerValue(),0.0000001,"M2 trigger value");
   CTestAssert::EqualDouble(30.0,plan.LevelAt(2).TriggerValue(),0.0000001,"M3 trigger value");
   CTestAssert::True(plan.LevelAt(0).PartialClose(),"M1 partial_close");
   CTestAssert::True(plan.LevelAt(1).PartialClose(),"M2 partial_close");
   CTestAssert::True(plan.LevelAt(2).PartialClose(),"M3 partial_close");
   CTestAssert::True(plan.LevelAt(0).Enabled(),"M1 enabled");
   CTestAssert::True(plan.LevelAt(1).Enabled(),"M2 enabled");
   CTestAssert::True(plan.LevelAt(2).Enabled(),"M3 enabled");
  }

void TestControlledSeedRecoveryFields(void)
  {
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(CSprint8dDemoM123StrategyProfile::CanonicalJson(),CUtcTime(1000));
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   CRecoveryPlan recovery=profile.RecoveryPlan();
   CTestAssert::EqualInt(1,recovery.InitialPositionCount(),"initial_position_count must be 1");
   CTestAssert::EqualDouble(0.06,recovery.InitialLotSize(),0.0000001,"initial_lot_size must be 0.06");
  }

void TestMaxTradeRetriesZeroIsParserValid(void)
  {
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(CSprint8dDemoM123StrategyProfile::CanonicalJson(),CUtcTime(1000));
   CTestAssert::True(profileResult.IsOk(),"Profile with max_trade_retries=0 must parse");
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   CTestAssert::EqualInt(0,profile.ExecutionPolicy().MaxTradeRetries(),"max_trade_retries must be 0");
  }

void TestM123RemainingVolumeChainOn006Seed(void)
  {
   const double m1Percent=33.0;
   const double m2Percent=50.0;
   const double m3Percent=34.0;
   SProfitCloseVolumeCalculation m1=
      CProfitCloseCandidateCloseVolumeCalculator::CalculateNextCloseVolume(0.06,m1Percent,0.01,0.01);
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_VOLUME_RESULT_OK,(int)m1.result,"M1 must be valid");
   CTestAssert::EqualDouble(0.01,m1.closeVolume,0.0000001,"M1 close volume");
   CTestAssert::EqualDouble(0.05,m1.remainderVolume,0.0000001,"M1 remainder volume");

   SProfitCloseVolumeCalculation m2=
      CProfitCloseCandidateCloseVolumeCalculator::CalculateNextCloseVolume(m1.remainderVolume,m2Percent,0.01,0.01);
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_VOLUME_RESULT_OK,(int)m2.result,"M2 must be valid");
   CTestAssert::EqualDouble(0.02,m2.closeVolume,0.0000001,"M2 close volume");
   CTestAssert::EqualDouble(0.03,m2.remainderVolume,0.0000001,"M2 remainder volume");

   SProfitCloseVolumeCalculation m3=
      CProfitCloseCandidateCloseVolumeCalculator::CalculateNextCloseVolume(m2.remainderVolume,m3Percent,0.01,0.01);
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_VOLUME_RESULT_OK,(int)m3.result,"M3 must be valid");
   CTestAssert::EqualDouble(0.01,m3.closeVolume,0.0000001,"M3 close volume");
   CTestAssert::EqualDouble(0.02,m3.remainderVolume,0.0000001,"M3 remainder volume");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestCanonicalJsonParsesAndValidates();
   TestCanonicalHashMatchesExpected();
   TestProfitLevelsMatchControlledDemoContract();
   TestControlledSeedRecoveryFields();
   TestMaxTradeRetriesZeroIsParserValid();
   TestM123RemainingVolumeChainOn006Seed();
   CTestAssert::Summary("TestSprint8dDemoM123StrategyProfile");
  }
