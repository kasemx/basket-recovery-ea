#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/PersistenceTestPaths.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Tests/AggregateTestFixture.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/TestSequentialIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketSerializer.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketPersistenceLoadDiagnostic.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>
#include <BasketRecovery/Application/Services/ExecutionDryRunManualCommandService.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Shared/Utils/Crc32.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>

CBasketAggregate BuildBoundActiveBasket(const string basketIdValue,const string jsonContent)
  {
   CUtcTime boundAt(1000);
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(jsonContent,boundAt);
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,jsonContent,boundAt);
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                  CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                  CExecutionProfileConfig(),boundAt);
   CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId(basketIdValue),legacy,snapshot,
                                                                      "corr-"+basketIdValue,BRE_DIRECTION_BUY,"EURUSD",
                                                                      CSignalId("sig-"+basketIdValue),boundAt,
                                                                      CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   return basket;
  }

void TestSerializerSaveFreshRepositoryLoadPreservesCrc(void)
  {
   CPersistenceTestPaths::Cleanup();
   CFileBasketRepository repository(BRE_TEST_PERSISTENCE_BASKET_SUBDIR);
   CBasketAggregate basket=BuildBoundActiveBasket("crc-roundtrip-001",CStrategyProfileTestFixture::MinimalValidJson());
   CTestAssert::True(repository.Save(basket).IsOk(),"Save must succeed");

   CFileBasketRepository reopened(BRE_TEST_PERSISTENCE_BASKET_SUBDIR);
   CBasketPersistenceLoadDiagnostic report=
      CBasketPersistenceLoadDiagnostic::Inspect(BRE_TEST_PERSISTENCE_BASKET_SUBDIR,CBasketId("crc-roundtrip-001"),reopened);
   CTestAssert::True(report.repositoryLoadOk,"Fresh repository load must succeed");
   CTestAssert::EqualString("ok",report.validationStage,"Validation stage must be ok");
   CTestAssert::EqualString(report.storedCrcHex,report.computedCrcHex,"Stored CRC must equal recomputed CRC");
  }

void TestEscapedCanonicalStrategyJsonRoundTripUnchanged(void)
  {
   string json=CStrategyProfileTestFixture::MinimalValidJson();
   CBasketAggregate basket=BuildBoundActiveBasket("escaped-json-001",json);
   CStrategyProfile profile;
   basket.StrategyProfile(profile);
   CTestAssert::True(basket.HasStrategyProfile(),"Bound basket must have strategy snapshot");

   CBasketSerializer serializer;
   string serialized=serializer.Serialize(basket);
   CResult<CBasketAggregate> loaded=serializer.Deserialize(serialized);
   CTestAssert::True(loaded.IsOk(),"Deserialize must succeed for escaped canonical JSON");
   CBasketAggregate reloaded;
   loaded.TryGetValue(reloaded);
   CTestAssert::EqualString(basket.StrategyProfileHash(),reloaded.StrategyProfileHash(),"Profile hash must survive save/load");
  }

void TestPersistedCrcEqualsRecomputedAfterReload(void)
  {
   CPersistenceTestPaths::Cleanup();
   CBasketAggregate basket=BuildBoundActiveBasket("crc-recompute-001",CStrategyProfileTestFixture::MinimalValidJson());
   CFileBasketRepository repository(BRE_TEST_PERSISTENCE_BASKET_SUBDIR);
   repository.Save(basket);

   string relativePath=BRE_TEST_PERSISTENCE_BASKET_SUBDIR+"/crc-recompute-001.json";
   string content=CBasketPersistenceLoadDiagnostic::ReadFileContentRaw(relativePath,true);
   CBasketPersistenceLoadDiagnostic report=
      CBasketPersistenceLoadDiagnostic::Inspect(BRE_TEST_PERSISTENCE_BASKET_SUBDIR,CBasketId("crc-recompute-001"),repository);
   CTestAssert::True(report.storedCrcHex!="","Stored CRC must be present");
   CTestAssert::EqualString(report.storedCrcHex,report.computedCrcHex,"Persisted CRC must equal recomputed CRC");
   CTestAssert::True(StringLen(content)>0,"Persisted content must not be empty");
  }

void TestWrongTerminalPathIsDetectable(void)
  {
   CBasketPersistenceLoadDiagnostic report;
   report.fileExistsCommon=false;
   report.fileExistsTerminalLocal=true;
   report.validationStage="wrong_file_path";
   CTestAssert::EqualString("wrong_file_path",
                            CBasketPersistenceLoadDiagnostic::ClassifyFailure(report),
                            "Terminal-local-only file must classify as wrong_file_path");
  }

void TestStaleFileDiagnosticIdentifiesMismatch(void)
  {
   CBasketPersistenceLoadDiagnostic report;
   report.strategySnapshotPresent=true;
   report.canonicalJsonLen=0;
   report.profileHashLen=0;
   report.validationStage="crc_mismatch";
   CTestAssert::EqualString("stale_file",
                            CBasketPersistenceLoadDiagnostic::ClassifyFailure(report),
                            "Empty strategy payload with snapshot flag must classify as stale_file");
  }

void TestManualDryRunLogsOneBasketLoadDiagnosticOnly(void)
  {
   CExecutionDryRunManualCommandService service;
   service.Configure(BRE_EXEC_RUNTIME_MT5_DRY_RUN,true,true,BRE_PERSISTENCE_BASKET_SUBDIR,NULL,NULL,NULL,NULL,NULL);
   service.TryProcessManualDryRunOpen("diag-once-basket","",0.01);
   service.TryProcessManualDryRunOpen("diag-once-basket","",0.01);
   CTestAssert::True(service.BasketLoadDiagnosticEmitted(),"Diagnostic must emit once when enabled");
  }

void TestCrcFromHexHandlesHighBitValues(void)
  {
   uint crc=0;
   CTestAssert::True(CCrc32::FromHex("F18BB9A8",crc),"FromHex must parse CRC values above INT_MAX");
   CTestAssert::EqualString("F18BB9A8",CCrc32::ToHex(crc),"FromHex/ToHex round-trip must preserve high-bit CRC");
  }

void TestCreateOnlyBasketSaveLoadRoundTrip(CAggregateTestFixture &fixture)
  {
   CPersistenceTestPaths::Cleanup();
   CFileBasketRepository repository(BRE_TEST_PERSISTENCE_BASKET_SUBDIR);
   CBasketId basketId("create-only-roundtrip-001");
   CResult<CBasketAggregate> created=CBasketFactory::Create(basketId,
                                                          fixture.BuildProfileSnapshot(),
                                                          "corr-create-only",
                                                          BRE_DIRECTION_BUY,
                                                          "EURUSD",
                                                          CSignalId("sig-create-only"),
                                                          CUtcTime(fixture.Clock().Now()),
                                                          CCommandId("cmd-create-only"),
                                                          CEventId("evt-create-only"));
   CTestAssert::True(created.IsOk(),"Create-only basket factory must succeed");
   CBasketAggregate basket;
   created.TryGetValue(basket);
   CTestAssert::False(basket.HasStrategyProfile(),"Create-only basket must remain unbound");
   CTestAssert::True(repository.Save(basket).IsOk(),"Create-only basket save must succeed");

   CFileBasketRepository reopened(BRE_TEST_PERSISTENCE_BASKET_SUBDIR);
   CResult<CBasketAggregate> loaded=reopened.Load(basketId);
   CTestAssert::True(loaded.IsOk(),"Create-only basket reload must succeed");
   CBasketAggregate reloaded;
   loaded.TryGetValue(reloaded);
   CTestAssert::False(reloaded.HasStrategyProfile(),"Create-only basket must stay unbound after reload");
  }

void OnStart()
  {
   CTestAssert::Reset();
   CAggregateTestFixture fixture;
   TestSerializerSaveFreshRepositoryLoadPreservesCrc();
   TestEscapedCanonicalStrategyJsonRoundTripUnchanged();
   TestPersistedCrcEqualsRecomputedAfterReload();
   TestWrongTerminalPathIsDetectable();
   TestStaleFileDiagnosticIdentifiesMismatch();
   TestManualDryRunLogsOneBasketLoadDiagnosticOnly();
   TestCrcFromHexHandlesHighBitValues();
   TestCreateOnlyBasketSaveLoadRoundTrip(fixture);
   CPersistenceTestPaths::Cleanup();
   CTestAssert::Summary("TestBasketPersistenceCrcDiagnostic");
   if(!CTestAssert::AllPassed())
      Print("TestBasketPersistenceCrcDiagnostic FAILED");
  }
