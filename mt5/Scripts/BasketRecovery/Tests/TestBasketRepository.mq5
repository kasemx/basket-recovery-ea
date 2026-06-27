#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/TestSequentialIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Validation/BasketValidator.mqh>
#include <BasketRecovery/Tests/AggregateTestFixture.mqh>

void TestSaveLoadRoundTrip(CAggregateTestFixture &fixture)
  {
   CTestSequentialIdGenerator idGenerator;
   CBasketId basketId("repo-basket-001");
   CResult<CBasketAggregate> created=CBasketFactory::Create(basketId,
                                                          fixture.BuildProfileSnapshot(),
                                                          "corr-repo-001",
                                                          BRE_DIRECTION_BUY,
                                                          "XAUUSD",
                                                          CSignalId("sig-001"),
                                                          CUtcTime(fixture.Clock().Now()),
                                                          CCommandId("cmd-create-001"),
                                                          CEventId("evt-create-001"));
   CTestAssert::True(created.IsOk(),"Factory create must succeed");

   CBasketAggregate aggregate;
   CTestAssert::True(created.TryGetValue(aggregate),"Aggregate value must exist");
   CTestAssert::True(fixture.Repository().Save(aggregate).IsOk(),"Save must succeed");
   CTestAssert::True(fixture.Repository().Exists(basketId),"Exists must return true");

   CResult<CBasketAggregate> loaded=fixture.Repository().Load(basketId);
   CTestAssert::True(loaded.IsOk(),"Load must succeed");
   CBasketAggregate loadedAggregate;
   CTestAssert::True(loaded.TryGetValue(loadedAggregate),"Loaded aggregate must exist");
   CTestAssert::EqualInt(BRE_STATE_PENDING_OPEN,loadedAggregate.LifecycleState(),"Loaded lifecycle must match");
   CTestAssert::EqualInt(aggregate.Version(),loadedAggregate.Version(),"Loaded version must match");
  }

void TestUpdateAndDelete(CAggregateTestFixture &fixture)
  {
   CBasketId basketId("repo-basket-002");
   CResult<CBasketAggregate> created=CBasketFactory::Create(basketId,
                                                          fixture.BuildProfileSnapshot(),
                                                          "corr-repo-002",
                                                          BRE_DIRECTION_SELL,
                                                          "EURUSD",
                                                          CSignalId("sig-002"),
                                                          CUtcTime(fixture.Clock().Now()),
                                                          CCommandId("cmd-create-002"),
                                                          CEventId("evt-create-002"));
   CBasketAggregate aggregate;
   created.TryGetValue(aggregate);
   fixture.Repository().Save(aggregate);
   fixture.MoveToWaitDetails(aggregate);

   CResult<CBasketAggregate> loaded=fixture.Repository().Load(basketId);
   CBasketAggregate updated;
   loaded.TryGetValue(updated);
   CTestAssert::EqualInt(BRE_STATE_WAIT_DETAILS,updated.LifecycleState(),"Updated lifecycle must be WAIT_DETAILS");
   CTestAssert::True(updated.Version()>aggregate.Version(),"Version must increase after transition");

   CTestAssert::True(fixture.Repository().Delete(basketId).IsOk(),"Delete must succeed");
   CTestAssert::False(fixture.Repository().Exists(basketId),"Basket must not exist after delete");
  }

void TestHistoryRoundTrip(CAggregateTestFixture &fixture)
  {
   CBasketId basketId("repo-basket-003");
   CResult<CBasketAggregate> created=CBasketFactory::Create(basketId,
                                                          fixture.BuildProfileSnapshot(),
                                                          "corr-repo-003",
                                                          BRE_DIRECTION_BUY,
                                                          "XAUUSD",
                                                          CSignalId("sig-003"),
                                                          CUtcTime(fixture.Clock().Now()),
                                                          CCommandId("cmd-create-003"),
                                                          CEventId("evt-create-003"));
   CBasketAggregate aggregate;
   created.TryGetValue(aggregate);
   fixture.Repository().Save(aggregate);

   CResult<CBasketAggregate> loaded=fixture.Repository().Load(basketId);
   CBasketAggregate loadedAggregate;
   loaded.TryGetValue(loadedAggregate);
   CTestAssert::EqualInt(1,loadedAggregate.CommandHistoryCount(),"Command and event history must persist");
   CTestAssert::EqualInt(1,loadedAggregate.EventHistoryCount(),"Event history must persist");
  }

void OnStart()
  {
   CTestAssert::Reset();
   CAggregateTestFixture fixture;
   CTestAssert::True(fixture.Initialize(),"Aggregate test fixture must initialize");

   TestSaveLoadRoundTrip(fixture);
   TestUpdateAndDelete(fixture);
   TestHistoryRoundTrip(fixture);

   CTestAssert::Summary("TestBasketRepository");
   if(!CTestAssert::AllPassed())
      Print("TestBasketRepository FAILED");
  }
