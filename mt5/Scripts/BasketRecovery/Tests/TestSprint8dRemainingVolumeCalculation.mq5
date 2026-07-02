#property script_show_inputs

#include "../../../Include/BasketRecovery/Tests/TestAssert.mqh"
#include "../../../Include/BasketRecovery/Domain/Execution/ProfitCloseCandidateCloseVolumeCalculator.mqh"
#include "../../../Include/BasketRecovery/Application/Strategy/ProfitLevelCloseCandidatePlanningService.mqh"

void TestRemaining010Half(void)
  {
   SProfitCloseVolumeCalculation calc=CProfitCloseCandidateCloseVolumeCalculator::CalculateNextCloseVolume(0.10,50.0,0.01,0.01);
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_VOLUME_RESULT_OK,(int)calc.result,"0.10@50% must be valid");
   CTestAssert::EqualDouble(0.05,calc.closeVolume,0.0000001,"close volume");
   CTestAssert::EqualDouble(0.05,calc.remainderVolume,0.0000001,"remainder volume");
  }

void TestRemaining003HalfNormalizesDown(void)
  {
   SProfitCloseVolumeCalculation calc=CProfitCloseCandidateCloseVolumeCalculator::CalculateNextCloseVolume(0.03,50.0,0.01,0.01);
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_VOLUME_RESULT_OK,(int)calc.result,"0.03@50% must be valid");
   CTestAssert::EqualDouble(0.01,calc.closeVolume,0.0000001,"0.015 must normalize to 0.01");
   CTestAssert::EqualDouble(0.02,calc.remainderVolume,0.0000001,"remainder must be 0.02");
  }

void TestRemaining002Half(void)
  {
   SProfitCloseVolumeCalculation calc=CProfitCloseCandidateCloseVolumeCalculator::CalculateNextCloseVolume(0.02,50.0,0.01,0.01);
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_VOLUME_RESULT_OK,(int)calc.result,"0.02@50% must be valid");
   CTestAssert::EqualDouble(0.01,calc.closeVolume,0.0000001,"close volume");
   CTestAssert::EqualDouble(0.01,calc.remainderVolume,0.0000001,"remainder volume");
  }

void TestRemaining001HalfNoValidPartial(void)
  {
   SProfitCloseVolumeCalculation calc=CProfitCloseCandidateCloseVolumeCalculator::CalculateNextCloseVolume(0.01,50.0,0.01,0.01);
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_VOLUME_RESULT_NO_VALID_CLOSE_VOLUME,(int)calc.result,
                         "0.01@50% must return NO_VALID_CLOSE_VOLUME");
  }

void TestDustRemainderPromotesFullClose(void)
  {
   const double dustClosePercent=(0.05/0.06)*100.0;
   SProfitCloseVolumeCalculation calc=CProfitCloseCandidateCloseVolumeCalculator::CalculateNextCloseVolume(0.06,dustClosePercent,0.05,0.01);
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_VOLUME_RESULT_OK,(int)calc.result,
                         "dust remainder policy must keep valid result");
   CTestAssert::EqualString("PROMOTE_TO_FULL_CLOSE_WHEN_REMAINDER_BELOW_MIN",
                            CProfitCloseCandidateCloseVolumeCalculator::DustRemainderPolicyLabel(),
                            "dust remainder policy label");
   CTestAssert::EqualDouble(0.06,calc.closeVolume,0.0000001,
                            "remainder below min lot must escalate to full close");
   CTestAssert::EqualDouble(0.0,calc.remainderVolume,0.0000001,"full close remainder must be zero");
  }

void TestExactStepPreserves006(void)
  {
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CTestAssert::EqualDouble(0.06,
                            CProfitCloseCandidateCloseVolumeCalculator::NormalizeVolume(0.06,constraints),
                            0.0000001,
                            "0.06 must preserve exact lot-step multiple");
  }

void TestExactStepPreserves003(void)
  {
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CTestAssert::EqualDouble(0.03,
                            CProfitCloseCandidateCloseVolumeCalculator::NormalizeVolume(0.03,constraints),
                            0.0000001,
                            "0.03 must preserve exact lot-step multiple");
  }

void TestNonStepNormalizesDown0025(void)
  {
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CTestAssert::EqualDouble(0.02,
                            CProfitCloseCandidateCloseVolumeCalculator::NormalizeVolume(0.025,constraints),
                            0.0000001,
                            "0.025 must normalize down to 0.02");
   CTestAssert::EqualDouble(0.02,
                            CProfitCloseCandidateCloseVolumeCalculator::NormalizeVolume(0.0201,constraints),
                            0.0000001,
                            "0.0201 must normalize down to 0.02");
   CTestAssert::EqualDouble(0.02,
                            CProfitCloseCandidateCloseVolumeCalculator::NormalizeVolume(0.029,constraints),
                            0.0000001,
                            "0.029 must normalize down to 0.02");
  }

void TestFullChainSeed006M1M2M3(void)
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
   CTestAssert::True(m3.closeVolume+0.0000001<m3.sourceRemainingVolume,"M3 must not promote to full close");
  }

void TestPlannerUsesRemainingVolumeForM2(void)
  {
   string levelIds[];
   bool enabled[];
   bool reached[];
   bool completed[];
   ArrayResize(levelIds,3);
   ArrayResize(enabled,3);
   ArrayResize(reached,3);
   ArrayResize(completed,3);
   levelIds[0]="M1";
   levelIds[1]="M2";
   levelIds[2]="M3";
   enabled[0]=true;
   enabled[1]=true;
   enabled[2]=true;
   reached[0]=true;
   reached[1]=true;
   reached[2]=false;
   completed[0]=true;
   completed[1]=false;
   completed[2]=false;

   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelCloseCandidatePlanningService::SNextProfitLevelVolumePlan plan=
      CProfitLevelCloseCandidatePlanningService::PlanNextLevelCloseVolume("basket-8d",
                                                                           levelIds,
                                                                           enabled,
                                                                           reached,
                                                                           completed,
                                                                           0.10,
                                                                           50.0,
                                                                           constraints,
                                                                           123);
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_VOLUME_RESULT_OK,(int)plan.result,"planner volume plan must be valid");
   CTestAssert::EqualString("M2",plan.levelId,"planner must choose M2");
   CTestAssert::EqualDouble(0.05,plan.closeVolume,0.0000001,"planner must use remaining-volume calculator");
   CTestAssert::EqualDouble(0.10,plan.sourceRemainingVolume,0.0000001,"plan must carry source remaining volume");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestRemaining010Half();
   TestRemaining003HalfNormalizesDown();
   TestRemaining002Half();
   TestRemaining001HalfNoValidPartial();
   TestDustRemainderPromotesFullClose();
   TestExactStepPreserves006();
   TestExactStepPreserves003();
   TestNonStepNormalizesDown0025();
   TestFullChainSeed006M1M2M3();
   TestPlannerUsesRemainingVolumeForM2();
   CTestAssert::Summary("TestSprint8dRemainingVolumeCalculation");
  }
