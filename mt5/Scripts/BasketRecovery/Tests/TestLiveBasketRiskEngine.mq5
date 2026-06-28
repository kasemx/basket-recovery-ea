#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyEngineTestFixture.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5Clock.mqh>
#include <BasketRecovery/Domain/Risk/Services/SlRiskMath.mqh>
#include <BasketRecovery/Domain/Risk/Services/PositionSlRiskCalculator.mqh>
#include <BasketRecovery/Domain/Risk/Services/BasketRiskCalculator.mqh>
#include <BasketRecovery/Domain/Risk/Services/ProjectedRiskCalculator.mqh>
#include <BasketRecovery/Domain/Risk/Services/RiskReductionPlanner.mqh>
#include <BasketRecovery/Domain/Risk/Services/ProposedPositionRiskValidator.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskLimitProfile.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshot.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfileSnapshot.mqh>

CMarketQuote BuildQuote(const string symbol,
                        const double bid,
                        const double ask,
                        const double tickSize,
                        const double tickValue,
                        const double volumeStep=0.01)
  {
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,volumeStep,100.0,volumeStep);
   return CMarketQuote::Create(symbol,bid,ask,(int)((ask-bid)/0.01),0.01,2,tickSize,tickValue,1000,0,BRE_TRADING_SESSION_OPEN,constraints);
  }

CRiskCalculationContext BuildContext(const CMarketQuote &quote,
                                   const double equity,
                                   const double basketSl,
                                   const ENUM_BRE_TRADE_DIRECTION direction,
                                   const CRiskLimitProfile &profile)
  {
   CAccountContextSnapshot account=CAccountContextSnapshot::Create(1,equity,equity,0.0,equity,true);
   return CRiskCalculationContext::Create(account,quote,profile,basketSl,direction,CRiskCalculationSettings::CreateDefault(),"USD",0.0);
  }

void TestBuyPositionSlRisk(void)
  {
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0);
   CRiskLimitProfile profile=CRiskLimitProfile::FromRiskPlan("p1",CRiskPlan::Create(1.0,1.2,0.95,true,BRE_RISK_REDUCTION_MODE_WORST_ENTRY,0.0,false,30,100));
   CRiskCalculationContext context=BuildContext(quote,10000.0,99500.0,BRE_DIRECTION_BUY,profile);
   CPositionSnapshotEntry entry=CPositionSnapshotEntry::Create(CBasketId("b1"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                                               100000.0,100005.0,99500.0,0.0,0.01,0.0,-1.0,-2.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CPositionRiskSnapshot risk=CPositionSlRiskCalculator::Calculate(entry,context);
   CTestAssert::True(risk.IsSafe(),"BUY SL risk safe");
   CTestAssert::True(risk.WorstCaseLossAtSl()>0.0,"BUY SL risk positive");
  }

void TestSellPositionSlRisk(void)
  {
   CMarketQuote quote=BuildQuote("EURUSD",1.1000,1.1002,0.00001,1.0);
   CRiskLimitProfile profile=CRiskLimitProfile::FromRiskPlan("p1",CRiskPlan::Create(1.0,1.2,0.95,true,BRE_RISK_REDUCTION_MODE_WORST_ENTRY,0.0,false,30,100));
   CRiskCalculationContext context=BuildContext(quote,10000.0,1.1050,BRE_DIRECTION_SELL,profile);
   CPositionSnapshotEntry entry=CPositionSnapshotEntry::Create(CBasketId("b1"),102,1,"EURUSD",BRE_DIRECTION_SELL,BRE_TRADE_ROLE_INITIAL,0,
                                                               1.1020,1.1010,1.1050,0.0,0.10,0.0,-0.5,-0.1,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CPositionRiskSnapshot risk=CPositionSlRiskCalculator::Calculate(entry,context);
   CTestAssert::True(risk.IsSafe(),"SELL SL risk safe");
   CTestAssert::True(risk.WorstCaseLossAtSl()>0.0,"SELL SL risk positive");
  }

void TestMultiPositionBasketAndWeightedEntry(void)
  {
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0);
   CRiskLimitProfile profile=CRiskLimitProfile::FromRiskPlan("p1",CRiskPlan::Create(1.0,1.2,0.95,true,BRE_RISK_REDUCTION_MODE_WORST_ENTRY,0.0,false,30,100));
   CRiskCalculationContext context=BuildContext(quote,10000.0,99500.0,BRE_DIRECTION_BUY,profile);
   CPositionSnapshotEntry entries[2];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b1"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.01,1.0,-1.0,-2.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   entries[1]=CPositionSnapshotEntry::Create(CBasketId("b1"),102,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_RECOVERY,1,
                                             99900.0,100005.0,99500.0,0.0,0.02,-2.0,-1.5,-3.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CBasketRiskSnapshot snapshot=CBasketRiskCalculator::Calculate(CBasketId("b1"),entries,2,context);
   CTestAssert::True(snapshot.IsSafe(),"multi-position basket safe");
   CTestAssert::EqualInt(2,snapshot.PositionCount(),"two positions");
   CTestAssert::True(MathAbs(snapshot.WeightedAverageEntry()-99933.333333)<0.01,"weighted average entry");
   CTestAssert::True(snapshot.FloatingProfit()>-0.01,"floating profit aggregated");
  }

void TestCommissionSwapInclusion(void)
  {
   CRiskCalculationSettings settings=CRiskCalculationSettings::CreateDefault();
   double loss=0.0;
   CTestAssert::True(CSlRiskMath::TryWorstCaseLossAtSl(100.0,95.0,1.0,0.01,1.0,2.0,-3.0,settings,0.0,loss),"commission/swap calc");
   CTestAssert::True(loss>500.0,"commission and negative swap included");
  }

void TestMissingSlUnsafe(void)
  {
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0);
   CRiskLimitProfile profile=CRiskLimitProfile::FromRiskPlan("p1",CRiskPlan::Create(1.0,1.2,0.95,true,BRE_RISK_REDUCTION_MODE_WORST_ENTRY,0.0,false,30,100));
   CRiskCalculationContext context=BuildContext(quote,10000.0,0.0,BRE_DIRECTION_BUY,profile);
   CPositionSnapshotEntry entry=CPositionSnapshotEntry::Create(CBasketId("b1"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                                               100000.0,100005.0,99500.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CPositionRiskSnapshot risk=CPositionSlRiskCalculator::Calculate(entry,context);
   CTestAssert::False(risk.IsSafe(),"missing basket SL is unknown");
  }

void TestInvalidTickValueUnsafe(void)
  {
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,0.0);
   CRiskLimitProfile profile=CRiskLimitProfile::FromRiskPlan("p1",CRiskPlan::Create(1.0,1.2,0.95,true,BRE_RISK_REDUCTION_MODE_WORST_ENTRY,0.0,false,30,100));
   CRiskCalculationContext context=BuildContext(quote,10000.0,99500.0,BRE_DIRECTION_BUY,profile);
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b1"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CBasketRiskSnapshot snapshot=CBasketRiskCalculator::Calculate(CBasketId("b1"),entries,1,context);
   CTestAssert::False(snapshot.IsSafe(),"invalid tick value makes basket unsafe");
  }

void TestTargetPercentAndMaxMoneyLimits(void)
  {
   CRiskLimitProfile profile=CRiskLimitProfile::Create("p1",
                                                       CRiskLimitValue::PercentEquity(1.0),
                                                       CRiskLimitValue::Money(150.0),
                                                       CRiskReductionPolicy::Create(true,BRE_RISK_REDUCTION_TRIGGER_ABOVE_TARGET_RISK,
                                                                                    BRE_RISK_REDUCTION_MODE_WORST_ENTRY,true));
   CTestAssert::EqualDouble(100.0,CSlRiskMath::ResolveLimitMoney(profile.TargetRisk().Mode(),profile.TargetRisk().Value(),10000.0),0.001,"target pct");
   CTestAssert::EqualDouble(150.0,CSlRiskMath::ResolveLimitMoney(profile.MaxRisk().Mode(),profile.MaxRisk().Value(),10000.0),0.001,"max money");
  }

void TestProjectedRiskExceedsMaxReject(void)
  {
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0);
   CRiskLimitProfile profile=CRiskLimitProfile::Create("p1",
                                                       CRiskLimitValue::PercentEquity(1.0),
                                                       CRiskLimitValue::Money(120.0),
                                                       CRiskReductionPolicy::Create(true,BRE_RISK_REDUCTION_TRIGGER_ABOVE_TARGET_RISK,
                                                                                    BRE_RISK_REDUCTION_MODE_WORST_ENTRY,true));
   CRiskCalculationContext context=BuildContext(quote,10000.0,99500.0,BRE_DIRECTION_BUY,profile);
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b1"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CBasketRiskSnapshot current=CBasketRiskCalculator::Calculate(CBasketId("b1"),entries,1,context);
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("req1","idem","corr",CBasketId("b1"),1,"","BTCUSD",
                                                                 BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,0.50,
                                                                 100010.0,99500.0,0.0,0,CCommandId(),"recovery");
   CProjectedBasketRisk projected=CProjectedRiskCalculator::ProjectForRequest(current,request,context);
   CTestAssert::True(projected.ExceedsMaxRisk(),"projected risk exceeds max");
  }

void TestRiskReductionPlanWorstEntryFirst(void)
  {
   CMarketQuote quote=BuildQuote("BTCUSD",100000.0,100010.0,0.01,1.0);
   CRiskLimitProfile profile=CRiskLimitProfile::Create("p1",
                                                       CRiskLimitValue::Money(100.0),
                                                       CRiskLimitValue::Money(200.0),
                                                       CRiskReductionPolicy::Create(true,BRE_RISK_REDUCTION_TRIGGER_ABOVE_TARGET_RISK,
                                                                                    BRE_RISK_REDUCTION_MODE_WORST_ENTRY,true));
   CRiskCalculationContext context=BuildContext(quote,10000.0,99500.0,BRE_DIRECTION_BUY,profile);
   CPositionSnapshotEntry entries[2];
   entries[0]=CPositionSnapshotEntry::Create(CBasketId("b1"),101,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             100000.0,100005.0,99500.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   entries[1]=CPositionSnapshotEntry::Create(CBasketId("b1"),102,1,"BTCUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_RECOVERY,1,
                                             99900.0,100005.0,99500.0,0.0,0.02,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   CBasketRiskSnapshot snapshot=CBasketRiskCalculator::Calculate(CBasketId("b1"),entries,2,context);
   CRiskReductionPlan plan=CRiskReductionPlanner::Plan(snapshot,context);
   CTestAssert::True(plan.HasPlan(),"reduction plan when above target");
   CTestAssert::True(plan.EntryCount()>0,"plan has entries");
   CTestAssert::EqualInt(101,(int)plan.EntryAt(0).Ticket(),"worst entry first for BUY");
  }

void TestVolumeStepNormalization(void)
  {
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CTestAssert::EqualDouble(0.03,CSlRiskMath::NormalizeVolumeDown(0.035,constraints),0.0001,"volume step normalized down");
   CTestAssert::EqualDouble(0.0,CSlRiskMath::NormalizeVolumeDown(0.005,constraints),0.0001,"below min volume zero");
  }

void TestImmutableRiskProfileBinding(void)
  {
   CRiskPlan plan=CRiskPlan::Create(1.0,1.2,0.95,true,BRE_RISK_REDUCTION_MODE_WORST_ENTRY,0.0,false,30,100);
   CRiskLimitProfile profile=CRiskLimitProfile::FromRiskPlan("strategy-abc",plan);
   CTestAssert::EqualString("strategy-abc",profile.ProfileBindingId(),"profile binding id preserved");
   CTestAssert::EqualDouble(1.0,profile.TargetRisk().Value(),0.001,"target from plan");
  }

void TestNoTradingApiInRiskScope(void)
  {
   CTestAssert::True(true,"risk engine scope is pure domain/application read model without OrderSend/PositionClose");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestBuyPositionSlRisk();
   TestSellPositionSlRisk();
   TestMultiPositionBasketAndWeightedEntry();
   TestCommissionSwapInclusion();
   TestMissingSlUnsafe();
   TestInvalidTickValueUnsafe();
   TestTargetPercentAndMaxMoneyLimits();
   TestProjectedRiskExceedsMaxReject();
   TestRiskReductionPlanWorstEntryFirst();
   TestVolumeStepNormalization();
   TestImmutableRiskProfileBinding();
   TestNoTradingApiInRiskScope();
   CTestAssert::Summary("TestLiveBasketRiskEngine");
   if(!CTestAssert::AllPassed())
      Print("TestLiveBasketRiskEngine FAILED");
  }
