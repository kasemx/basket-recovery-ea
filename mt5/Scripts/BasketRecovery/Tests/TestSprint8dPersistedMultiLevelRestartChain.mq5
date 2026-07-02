#property script_show_inputs

#include "../../../Include/BasketRecovery/Tests/TestAssert.mqh"
#include "../../../Include/BasketRecovery/Application/Strategy/ProfitLevelCloseCandidatePlanningService.mqh"
#include "../../../Include/BasketRecovery/Domain/Aggregates/BasketAggregate.mqh"
#include "../../../Include/BasketRecovery/Domain/Factories/BasketFactory.mqh"
#include "../../../Include/BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh"
#include "../../../Include/BasketRecovery/Domain/Persistence/BasketPersistenceDto.mqh"
#include "../../../Include/BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh"
#include "../../../Include/BasketRecovery/Domain/Strategy/Aggregates/StrategyProfileSnapshot.mqh"
#include "../../../Include/BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh"
#include "../../../Include/BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh"
#include "../../../Include/BasketRecovery/Domain/Enums/BasketLifecycleState.mqh"
#include "../../../Include/BasketRecovery/Shared/Types/Money.mqh"
#include "../../../Include/BasketRecovery/Shared/Types/Identifiers.mqh"

const string TEST_BASKET_ID="basket-8d4-persisted-chain";
const double M1_REALIZED_PROFIT=1.11;
const double M2_REALIZED_PROFIT=2.22;
const double M3_REALIZED_PROFIT=3.33;
const datetime M1_COMPLETED_AT=1101;
const datetime M2_COMPLETED_AT=1202;
const datetime M3_COMPLETED_AT=1303;

string ThreeLevelStrategyJson(void)
  {
   return "{"
          "\"schema_version\":2,"
          "\"strategy_id\":\"sprint-8d4-profile\","
          "\"metadata\":{\"strategy_name\":\"Sprint 8D4\"},"
          "\"execution_zone\":{\"source\":\"SIGNAL_RANGE\",\"expansion_mode\":\"SYMMETRIC\",\"above_entry_pips\":3,\"below_entry_pips\":3,\"expansion_disabled\":false},"
          "\"recovery_plan\":{\"algorithm\":\"CONSTANT\",\"constant_distance_pips\":0.2,\"constant_lot\":0.01,\"max_steps\":50,\"allow_during_profit_taking\":true,\"disable_after_break_even\":true,\"initial_position_count\":3,\"initial_lot_size\":0.01},"
          "\"risk_plan\":{\"target_risk_pct\":1.0,\"max_risk_pct\":1.2,\"risk_reduction_threshold_pct\":0.95,\"risk_reduction_mode\":\"WORST_ENTRY\",\"wait_details_timeout_minutes\":30,\"risk_eval_debounce_ms\":100},"
          "\"profit_distribution_plan\":{\"require_floating_profit_positive\":true,\"default_close_mode\":\"WORST_ENTRY_FIRST\",\"levels\":["
          "{\"level_id\":\"M1\",\"level_index\":1,\"source\":\"FLOATING_PROFIT_MONEY\",\"price\":10.0,\"trigger_type\":\"FLOATING_PROFIT_MONEY\",\"trigger_value\":10.0,\"close_percent\":33.0,\"close_mode\":\"WORST_ENTRY_FIRST\",\"partial_close\":true,\"enabled\":true},"
          "{\"level_id\":\"M2\",\"level_index\":2,\"source\":\"FLOATING_PROFIT_MONEY\",\"price\":20.0,\"trigger_type\":\"FLOATING_PROFIT_MONEY\",\"trigger_value\":20.0,\"close_percent\":33.0,\"close_mode\":\"WORST_ENTRY_FIRST\",\"partial_close\":true,\"enabled\":true},"
          "{\"level_id\":\"M3\",\"level_index\":3,\"source\":\"FLOATING_PROFIT_MONEY\",\"price\":30.0,\"trigger_type\":\"FLOATING_PROFIT_MONEY\",\"trigger_value\":30.0,\"close_percent\":34.0,\"close_mode\":\"WORST_ENTRY_FIRST\",\"partial_close\":true,\"enabled\":true}"
          "]},"
          "\"break_even_plan\":{\"rules\":[]},"
          "\"execution_policy\":{\"slippage_points\":10,\"max_trade_retries\":3,\"magic_number_base\":202606000,\"command_batch_size\":10,\"trade_request_batch_size\":5,\"rest_poll_interval_ms\":3000}"
          "}";
  }

CStrategyProfile BuildThreeLevelProfileFromJson(void)
  {
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(ThreeLevelStrategyJson(),CUtcTime(1000));
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   return profile;
  }

void SeedDtoIdentityFromBasket(const CBasketAggregate &source,CBasketPersistenceDto &dto)
  {
   dto.basketId=source.Id();
   dto.correlationKey=source.CorrelationKey();
   dto.direction=source.Direction();
   dto.symbol=source.Symbol();
   dto.lifecycleState=source.LifecycleState();

   CBasketModeFlags modeFlags=source.ModeFlags();
   dto.recoveryActive=modeFlags.RecoveryActive();
   dto.recoveryPermanentlyDisabled=source.RecoveryPermanentlyDisabled();
   dto.breakEvenActive=modeFlags.BreakEvenActive();
   dto.trailingActive=modeFlags.TrailingActive();
   dto.locked=modeFlags.Locked();
   dto.riskReductionActive=modeFlags.RiskReductionActive();
   dto.maxRiskLockout=modeFlags.MaxRiskLockout();

   if(source.HasProfileSnapshot())
     {
      CProfileSnapshot legacy=source.ProfileSnapshot();
      dto.hasProfileSnapshot=true;
      dto.profileName=legacy.ProfileName();
      dto.risk=legacy.Risk();
      dto.recovery=legacy.Recovery();
      dto.takeProfit=legacy.TakeProfit();
      dto.breakEven=legacy.BreakEven();
      dto.execution=legacy.Execution();
      dto.profileBoundAt=legacy.BoundAt();
     }

   dto.version=source.Version();
   dto.lastCommandId=source.VersionState().LastCommandId();
   dto.lastEventId=source.VersionState().LastEventId();
   dto.lastModifiedUtc=source.VersionState().LastModifiedUtc();
  }

bool RestoreFreshAggregateFromSource(const CBasketAggregate &source,CBasketAggregate &restoredOut)
  {
   CBasketPersistenceDto dto;
   SeedDtoIdentityFromBasket(source,dto);
   source.CopyRuntimeStateToDto(dto);
   restoredOut=CBasketAggregate();
   return restoredOut.RestoreFromDto(dto);
  }

CBasketAggregate BuildBasketWithReachedLevels(void)
  {
   CStrategyProfile profile=BuildThreeLevelProfileFromJson();
   string canonicalJson=ThreeLevelStrategyJson();
   CUtcTime boundAt(1000);
   CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,canonicalJson,boundAt);
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                  CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                  CExecutionProfileConfig(),boundAt);
   CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId(TEST_BASKET_ID),legacy,snapshot,
                                                                      "corr-"+TEST_BASKET_ID,BRE_DIRECTION_BUY,"EURUSD",
                                                                      CSignalId("sig-"+TEST_BASKET_ID),boundAt,
                                                                      CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   basket.ApplyProfitLevelReached("M1",CUtcTime(1001),CCommandId("reach-m1"),CEventId("reach-evt-m1"));
   basket.ApplyProfitLevelReached("M2",CUtcTime(1002),CCommandId("reach-m2"),CEventId("reach-evt-m2"));
   basket.ApplyProfitLevelReached("M3",CUtcTime(1003),CCommandId("reach-m3"),CEventId("reach-evt-m3"));
   return basket;
  }

void MarkLevelCompleted(CBasketAggregate &basket,
                        const string levelId,
                        const double realizedProfit,
                        const datetime completedAt)
  {
   basket.ApplyProfitLevelCloseRequested(levelId,CCommandId("req-"+levelId),CEventId("req-evt-"+levelId),
                                         CUtcTime(completedAt-1));
   basket.ApplyProfitLevelCloseCompleted(levelId,CMoney(realizedProfit),CCommandId("close-"+levelId),
                                         CEventId("close-evt-"+levelId),CUtcTime(completedAt));
  }

void AssertLevelRuntimeState(const CBasketAggregate &basket,
                             const string levelId,
                             const bool expectedReached,
                             const bool expectedCloseRequested,
                             const bool expectedCloseCompleted,
                             const double expectedRealizedProfit,
                             const datetime expectedCompletedAtUtc,
                             const string messagePrefix)
  {
   CBasketProfitLevelProgress progress;
   string msg="";
   msg=messagePrefix+" progress must exist";
   CTestAssert::True(basket.FindProfitLevelProgress(levelId,progress),msg);
   msg=messagePrefix+" reached";
   CTestAssert::True(progress.Reached()==expectedReached,msg);
   msg=messagePrefix+" closeRequested";
   CTestAssert::True(progress.CloseRequested()==expectedCloseRequested,msg);
   msg=messagePrefix+" closeCompleted";
   CTestAssert::True(progress.CloseCompleted()==expectedCloseCompleted,msg);
   msg=messagePrefix+" realizedProfit";
   CTestAssert::EqualDouble(expectedRealizedProfit,progress.RealizedProfit().Amount(),0.0000001,msg);
   msg=messagePrefix+" completedAtUtc";
   CTestAssert::EqualInt((int)expectedCompletedAtUtc,(int)progress.CompletedAtUtc().Value(),msg);
  }

bool TryGetProfileFromBasket(const CBasketAggregate &basket,CStrategyProfile &profile)
  {
   return basket.StrategyProfile(profile);
  }

void TestPersistedMultiLevelRestartChain(void)
  {
   CBasketAggregate basket=BuildBasketWithReachedLevels();

   MarkLevelCompleted(basket,"M1",M1_REALIZED_PROFIT,M1_COMPLETED_AT);
   CBasketAggregate restoredAfterM1;
   CTestAssert::True(RestoreFreshAggregateFromSource(basket,restoredAfterM1),
                     "first persist/restore must succeed");

   CStrategyProfile profileAfterM1;
   CTestAssert::True(TryGetProfileFromBasket(restoredAfterM1,profileAfterM1),
                     "restored basket must expose strategy profile");

   AssertLevelRuntimeState(restoredAfterM1,"M1",true,true,true,M1_REALIZED_PROFIT,M1_COMPLETED_AT,
                           "after first restore M1");

   string selectedAfterM1="";
   CTestAssert::True(CProfitLevelCloseCandidatePlanningService::SelectFirstEligibleLevelFromBasket(restoredAfterM1,
                                                                                                   profileAfterM1,
                                                                                                   selectedAfterM1),
                     "after first restore planner must select a level");
   CTestAssert::EqualString("M2",selectedAfterM1,"after first restore planner must select M2");
   CTestAssert::True(selectedAfterM1!="M1","after first restore planner must not select M1");

   MarkLevelCompleted(restoredAfterM1,"M2",M2_REALIZED_PROFIT,M2_COMPLETED_AT);
   CBasketAggregate restoredAfterM2;
   CTestAssert::True(RestoreFreshAggregateFromSource(restoredAfterM1,restoredAfterM2),
                     "second persist/restore must succeed");

   CStrategyProfile profileAfterM2;
   CTestAssert::True(TryGetProfileFromBasket(restoredAfterM2,profileAfterM2),
                     "second restored basket must expose strategy profile");

   AssertLevelRuntimeState(restoredAfterM2,"M1",true,true,true,M1_REALIZED_PROFIT,M1_COMPLETED_AT,
                           "after second restore M1");
   AssertLevelRuntimeState(restoredAfterM2,"M2",true,true,true,M2_REALIZED_PROFIT,M2_COMPLETED_AT,
                           "after second restore M2");

   string selectedAfterM2="";
   CTestAssert::True(CProfitLevelCloseCandidatePlanningService::SelectFirstEligibleLevelFromBasket(restoredAfterM2,
                                                                                                   profileAfterM2,
                                                                                                   selectedAfterM2),
                     "after second restore planner must select a level");
   CTestAssert::EqualString("M3",selectedAfterM2,"after second restore planner must select M3");
   CTestAssert::True(selectedAfterM2!="M1" && selectedAfterM2!="M2",
                     "after second restore planner must not select M1 or M2");

   MarkLevelCompleted(restoredAfterM2,"M3",M3_REALIZED_PROFIT,M3_COMPLETED_AT);
   CBasketAggregate restoredAfterM3;
   CTestAssert::True(RestoreFreshAggregateFromSource(restoredAfterM2,restoredAfterM3),
                     "final persist/restore must succeed");

   CStrategyProfile profileAfterM3;
   CTestAssert::True(TryGetProfileFromBasket(restoredAfterM3,profileAfterM3),
                     "final restored basket must expose strategy profile");

   AssertLevelRuntimeState(restoredAfterM3,"M1",true,true,true,M1_REALIZED_PROFIT,M1_COMPLETED_AT,
                           "after final restore M1");
   AssertLevelRuntimeState(restoredAfterM3,"M2",true,true,true,M2_REALIZED_PROFIT,M2_COMPLETED_AT,
                           "after final restore M2");
   AssertLevelRuntimeState(restoredAfterM3,"M3",true,true,true,M3_REALIZED_PROFIT,M3_COMPLETED_AT,
                           "after final restore M3");

   string selectedAfterM3="";
   CTestAssert::False(CProfitLevelCloseCandidatePlanningService::SelectFirstEligibleLevelFromBasket(restoredAfterM3,
                                                                                                    profileAfterM3,
                                                                                                    selectedAfterM3),
                      "after final restore planner must return no eligible level");
   CTestAssert::EqualString("",selectedAfterM3,"after final restore no level should be selected");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestPersistedMultiLevelRestartChain();
   CTestAssert::Summary("TestSprint8dPersistedMultiLevelRestartChain");
  }
