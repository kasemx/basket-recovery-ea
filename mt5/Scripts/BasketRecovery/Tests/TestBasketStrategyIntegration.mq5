#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Tests/PersistenceTestPaths.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketSerializer.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketMigration.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Application/Services/StrategyDecisionCommandMapper.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Basket/BasketRuntimeGuard.mqh>

CStrategyProfileSnapshot BuildBoundSnapshot(const string jsonContent,const CUtcTime &boundAt)
  {
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(jsonContent,boundAt);
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   return CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,jsonContent,boundAt);
  }

CBasketAggregate BuildBoundBasket(const string basketIdValue,const string jsonContent)
  {
   CUtcTime boundAt(1000);
   CStrategyProfileSnapshot snapshot=BuildBoundSnapshot(jsonContent,boundAt);
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                  CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                  CExecutionProfileConfig(),boundAt);
   CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId(basketIdValue),legacy,snapshot,
                                                                      "corr-"+basketIdValue,BRE_DIRECTION_BUY,"XAUUSD",
                                                                      CSignalId("sig-"+basketIdValue),boundAt,
                                                                      CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate aggregate;
   created.TryGetValue(aggregate);
   return aggregate;
  }

void TestBindOnceAndRebindFails(void)
  {
   string json=CStrategyProfileTestFixture::MinimalValidJson();
   CBasketAggregate basket=BuildBoundBasket("bind-once-001",json);
   CTestAssert::True(basket.HasStrategyProfile(),"Basket must have bound strategy");
   CTestAssert::EqualString("json-test",basket.StrategyId(),"Strategy id must match snapshot");

   CStrategyProfileSnapshot second=BuildBoundSnapshot(json,CUtcTime(2000));
   CVoidResult rebind=basket.BindStrategyProfile(second);
   CTestAssert::True(rebind.IsFail(),"Rebinding must fail");
   CTestAssert::EqualInt(BRE_ERR_STRATEGY_ALREADY_BOUND,rebind.ErrorCode(),"Rebind must report already bound");
  }

void TestProfileFileChangeDoesNotAffectSavedBasket(void)
  {
   CPersistenceTestPaths::Cleanup();
   string originalJson=CStrategyProfileTestFixture::MinimalValidJson();
   CBasketAggregate basket=BuildBoundBasket("immutable-001",originalJson);
   string originalHash=basket.StrategyProfileHash();
   CFileBasketRepository repository(BRE_TEST_PERSISTENCE_BASKET_SUBDIR);
   CTestAssert::True(repository.Save(basket).IsOk(),"Save bound basket must succeed");

   string modifiedJson=originalJson;
   StringReplace(modifiedJson,"\"target_risk_pct\":1.0","\"target_risk_pct\":2.5");
   CStrategyProfileSnapshot modifiedSnapshot=BuildBoundSnapshot(modifiedJson,CUtcTime(3000));
   CTestAssert::False(modifiedSnapshot.ProfileHash()==originalHash,"Modified profile hash must differ");

   CResult<CBasketAggregate> loaded=repository.Load(CBasketId("immutable-001"));
   CBasketAggregate reloaded;
   loaded.TryGetValue(reloaded);
   CTestAssert::EqualString(originalHash,reloaded.StrategyProfileHash(),"Reloaded basket must keep original hash");
   CStrategyProfile profile;
   CTestAssert::True(reloaded.StrategyProfile(profile),"Reloaded basket must expose bound profile");
   CTestAssert::EqualDouble(1.0,profile.RiskPlan().TargetRiskPct(),0.0001,"Bound profile risk must remain original");
  }

void TestMigrationV1ToV3(void)
  {
   CBasketSerializer serializer;
   string json=CStrategyProfileTestFixture::MinimalValidJson();
   CBasketAggregate basket=BuildBoundBasket("migrate-src",json);
   string v3Json=serializer.Serialize(basket);
   StringReplace(v3Json,"\"schema_version\":3","\"schema_version\":1");
   CResult<string> migrated=CBasketMigration::MigrateToCurrent(v3Json);
   CTestAssert::True(migrated.IsOk(),"v1 to v3 migration must succeed");
   string migratedJson;
   migrated.TryGetValue(migratedJson);
   CTestAssert::True(StringFind(migratedJson,"\"schema_version\":3")>=0,"Migrated payload must be schema v3");
   CResult<CBasketAggregate> restored=serializer.Deserialize(migratedJson);
   CTestAssert::True(restored.IsOk(),"Migrated basket deserialize must succeed");
  }

void TestProfitLevelsGeneric(void)
  {
   CBasketAggregate basket=BuildBoundBasket("profit-levels",CStrategyProfileTestFixture::MinimalValidJson());
   CUtcTime now(5000);
   CTestAssert::True(basket.ApplyProfitLevelReached("L1",now,CCommandId("cmd-l1"),CEventId("evt-l1")).IsOk(),"L1 reach must succeed");
   CTestAssert::True(basket.ApplyProfitLevelReached("L2",now,CCommandId("cmd-l2"),CEventId("evt-l2")).IsOk(),"L2 reach must succeed");
   CTestAssert::True(basket.ApplyProfitLevelReached("CUSTOM_20",now,CCommandId("cmd-20"),CEventId("evt-20")).IsOk(),"Custom level must succeed");
   CTestAssert::True(basket.ApplyProfitLevelReached("L1",now,CCommandId("cmd-dup"),CEventId("evt-dup")).IsFail(),"Duplicate L1 must fail");
   CTestAssert::EqualInt(BRE_STATE_ACTIVE,basket.LifecycleState(),"Profit level must not change lifecycle");
  }

void TestBreakEvenModeOnly(void)
  {
   CBasketAggregate basket=BuildBoundBasket("be-mode",CStrategyProfileTestFixture::MinimalValidJson());
   CTestAssert::True(basket.ApplyBreakEvenActivated("BE1",CCommandId("cmd-be"),CEventId("evt-be"),CUtcTime(6000)).IsOk(),
                     "Break-even apply must succeed");
   CTestAssert::True(basket.ModeFlags().BreakEvenActive(),"Break-even mode flag must be active");
   CTestAssert::EqualInt(BRE_STATE_ACTIVE,basket.LifecycleState(),"Break-even must not create lifecycle state");
  }

void TestStaleVersionAndHashGuards(void)
  {
   CBasketAggregate basket=BuildBoundBasket("guard-basket",CStrategyProfileTestFixture::MinimalValidJson());
   CVoidResult stale=CBasketRuntimeGuard::ValidateStrategyCommandContext(basket,basket.Version()-1,basket.StrategyProfileHash());
   CTestAssert::True(stale.IsFail(),"Stale version must fail");
   CVoidResult hashMismatch=CBasketRuntimeGuard::ValidateStrategyCommandContext(basket,basket.Version(),"wrong-hash");
   CTestAssert::True(hashMismatch.IsFail(),"Hash mismatch must fail");
  }

void TestDecisionMapperIdempotency(void)
  {
   CBasketAggregate basket=BuildBoundBasket("mapper-idem",CStrategyProfileTestFixture::MinimalValidJson());
   ulong tickets[];
   ArrayResize(tickets,0);
   CClosePositionsDecision closeDecision=CClosePositionsDecision::Create("idem-close-001","L1",33.0,
                                                                         BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,tickets,0);
   CStrategyDecisionSet set=CStrategyDecisionSet::Create();
   set.Add(CStrategyDecision::FromClosePositions(closeDecision));
   set.Add(CStrategyDecision::FromClosePositions(closeDecision));

   CStrategyDecisionCommandMapper mapper;
   ICommand *commands[];
   CResult<int> mapped=mapper.MapDecisionSet(set,basket.Id(),basket.Version(),basket.StrategyProfileHash(),
                                             basket.CorrelationKey(),commands);
   int count=0;
   mapped.TryGetValue(count);
   CTestAssert::EqualInt(1,count,"Duplicate idempotency keys must deduplicate to one command");
   CTestAssert::EqualString("idem-close-001",commands[0].IdempotencyKey(),"Mapped command must preserve idempotency key");
  }

void OnStart()
  {
   CTestAssert::Reset();
   TestBindOnceAndRebindFails();
   TestProfileFileChangeDoesNotAffectSavedBasket();
   TestMigrationV1ToV3();
   TestProfitLevelsGeneric();
   TestBreakEvenModeOnly();
   TestStaleVersionAndHashGuards();
   TestDecisionMapperIdempotency();
   CPersistenceTestPaths::Cleanup();
   CTestAssert::Summary("TestBasketStrategyIntegration");
   if(!CTestAssert::AllPassed())
      Print("TestBasketStrategyIntegration FAILED");
  }
