#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ExecutionZoneResolver.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ExecutionZone.mqh>

void TestSellRangeExpansion(void)
  {
   CExecutionZone zone=CExecutionZone::CreateSignalRange(BRE_ZONE_EXPANSION_ABOVE_ONLY,2.0,0.0,false,0.0,false);
   CExecutionZoneResolver resolver;
   CEffectiveRecoveryZone effective=resolver.Resolve(zone,BRE_DIRECTION_SELL,4014.0,4017.0,0.1);
   CTestAssert::EqualDouble(4014.0,effective.Low(),0.0001,"SELL zone low must stay at signal low");
   CTestAssert::EqualDouble(4019.0,effective.High(),0.0001,"SELL zone high must expand by 2 pips");
  }

void TestBuyRangeExpansion(void)
  {
   CExecutionZone zone=CExecutionZone::CreateSignalRange(BRE_ZONE_EXPANSION_BELOW_ONLY,0.0,2.0,false,0.0,false);
   CExecutionZoneResolver resolver;
   CEffectiveRecoveryZone effective=resolver.Resolve(zone,BRE_DIRECTION_BUY,4014.0,4017.0,0.1);
   CTestAssert::EqualDouble(4012.0,effective.Low(),0.0001,"BUY zone low must expand by 2 pips");
   CTestAssert::EqualDouble(4017.0,effective.High(),0.0001,"BUY zone high must stay at signal high");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestSellRangeExpansion();
   TestBuyRangeExpansion();
   CTestAssert::Summary("TestExecutionZoneResolver");
  }
