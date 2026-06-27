#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/AggregateTestFixture.mqh>
#include <BasketRecovery/Domain/Requests/TransitionRequest.mqh>
#include <BasketRecovery/Domain/ValueObjects/AuditRecord.mqh>
#include <BasketRecovery/Application/Commands/CreateBasketCommand.mqh>
#include <BasketRecovery/Application/Commands/ActivateBasketCommand.mqh>
#include <BasketRecovery/Application/Commands/CloseBasketCommand.mqh>
#include <BasketRecovery/Domain/Validation/BasketValidator.mqh>

void TestCreateAggregate(CAggregateTestFixture &fixture)
  {
   CCreateBasketCommand *command=new CCreateBasketCommand();
   command.SetId(CCommandId("cmd-aggregate-create"));
   command.SetBasketId(CBasketId("aggregate-basket-001"));
   command.SetIdempotencyKey("create:aggregate:001");
   command.SetSymbol("XAUUSD");
   command.SetDirection(BRE_DIRECTION_BUY);
   command.SetSignalId(CSignalId("sig-aggregate-001"));
   command.SetCorrelationKey("corr-aggregate-001");

   CResult<CCommandExecutionResult> result=fixture.CreateHandler().Execute(command);
   CTestAssert::True(result.IsOk(),"Create handler must succeed");
   CTestAssert::True(fixture.Repository().Exists(CBasketId("aggregate-basket-001")),"Created basket must exist");

   CResult<CBasketAggregate> loaded=fixture.Repository().Load(CBasketId("aggregate-basket-001"));
   CBasketAggregate aggregate;
   loaded.TryGetValue(aggregate);
   CTestAssert::EqualInt(BRE_STATE_PENDING_OPEN,aggregate.LifecycleState(),"Created basket must be PENDING_OPEN");
   CTestAssert::EqualInt(1,aggregate.Version(),"Initial version must be 1");
   CTestAssert::True(CBasketValidator::Validate(aggregate).IsOk(),"Created aggregate must validate");
  }

void TestActivateAggregate(CAggregateTestFixture &fixture)
  {
   CCreateBasketCommand *createCommand=new CCreateBasketCommand();
   createCommand.SetBasketId(CBasketId("aggregate-basket-002"));
   createCommand.SetSymbol("XAUUSD");
   createCommand.SetDirection(BRE_DIRECTION_BUY);
   createCommand.SetSignalId(CSignalId("sig-aggregate-002"));
   fixture.CreateHandler().Execute(createCommand);

   CResult<CBasketAggregate> loaded=fixture.Repository().Load(CBasketId("aggregate-basket-002"));
   CBasketAggregate aggregate;
   loaded.TryGetValue(aggregate);
   fixture.MoveToWaitDetails(aggregate);
   loaded=fixture.Repository().Load(CBasketId("aggregate-basket-002"));
   loaded.TryGetValue(aggregate);

   CActivateBasketCommand *activateCommand=new CActivateBasketCommand();
   activateCommand.SetBasketId(aggregate.Id());
   activateCommand.SetDetails(fixture.BuildSignalDetails());

   CResult<CCommandExecutionResult> result=fixture.ActivateHandler().Execute(activateCommand);
   CTestAssert::True(result.IsOk(),"Activate handler must succeed");

   loaded=fixture.Repository().Load(CBasketId("aggregate-basket-002"));
   loaded.TryGetValue(aggregate);
   CTestAssert::EqualInt(BRE_STATE_ACTIVE,aggregate.LifecycleState(),"Activated basket must be ACTIVE");
   CTestAssert::True(aggregate.Version()>=3,"Activate must increment version for details and lifecycle");
   CTestAssert::True(aggregate.SignalDetails().HasDetails(),"Signal details must be bound");
  }

void TestCloseAggregate(CAggregateTestFixture &fixture)
  {
   CCreateBasketCommand *createCommand=new CCreateBasketCommand();
   createCommand.SetBasketId(CBasketId("aggregate-basket-003"));
   createCommand.SetSymbol("XAUUSD");
   createCommand.SetDirection(BRE_DIRECTION_BUY);
   fixture.CreateHandler().Execute(createCommand);

   CResult<CBasketAggregate> loaded=fixture.Repository().Load(CBasketId("aggregate-basket-003"));
   CBasketAggregate aggregate;
   loaded.TryGetValue(aggregate);

   CCloseBasketCommand *closeCommand=new CCloseBasketCommand();
   closeCommand.SetBasketId(aggregate.Id());
   closeCommand.SetReason("operator_request");

   CResult<CCommandExecutionResult> result=fixture.CloseHandler().Execute(closeCommand);
   CTestAssert::True(result.IsOk(),"Close handler must succeed");

   loaded=fixture.Repository().Load(CBasketId("aggregate-basket-003"));
   loaded.TryGetValue(aggregate);
   CTestAssert::EqualInt(BRE_STATE_CLOSING,aggregate.LifecycleState(),"Closed basket must be CLOSING");
  }

void TestInvalidTransition(CAggregateTestFixture &fixture)
  {
   CCreateBasketCommand *createCommand=new CCreateBasketCommand();
   createCommand.SetBasketId(CBasketId("aggregate-basket-004"));
   createCommand.SetSymbol("XAUUSD");
   createCommand.SetDirection(BRE_DIRECTION_BUY);
   fixture.CreateHandler().Execute(createCommand);

   CResult<CBasketAggregate> loaded=fixture.Repository().Load(CBasketId("aggregate-basket-004"));
   CBasketAggregate aggregate;
   loaded.TryGetValue(aggregate);

   CTransitionRequest request=CTransitionRequest::ForLifecycle(aggregate.Id(),
                                                               CCommandId("cmd-invalid"),
                                                               CEventId("evt-invalid"),
                                                               BRE_EVENT_BASKET_ACTIVATED);
   CResult<CCommandExecutionResult> result=fixture.TransitionHandler().ProcessLifecycle(aggregate,request,CUtcTime(fixture.Clock().Now()));
   CTestAssert::True(result.IsOk(),"Invalid transition returns result envelope");

   CCommandExecutionResult executionResult;
   result.TryGetValue(executionResult);
   CTestAssert::EqualInt(BRE_EVENT_TRANSITION_REJECTED,executionResult.EventAt(0).EventType(),"Invalid transition must emit rejection");
   CTestAssert::EqualInt(BRE_STATE_PENDING_OPEN,aggregate.LifecycleState(),"State must remain unchanged");
  }

void TestAuditHistory(CAggregateTestFixture &fixture)
  {
   CCreateBasketCommand *createCommand=new CCreateBasketCommand();
   createCommand.SetBasketId(CBasketId("aggregate-basket-005"));
   createCommand.SetSymbol("XAUUSD");
   createCommand.SetDirection(BRE_DIRECTION_BUY);
   fixture.CreateHandler().Execute(createCommand);

   CResult<CBasketAggregate> loaded=fixture.Repository().Load(CBasketId("aggregate-basket-005"));
   CBasketAggregate aggregate;
   loaded.TryGetValue(aggregate);

   CAuditRecord record;
   CTestAssert::True(aggregate.CommandHistoryAt(0,record),"Audit record must exist");
   CTestAssert::EqualInt(1,record.Version(),"Audit version must match first mutation");
   CTestAssert::False(record.CommandId().IsEmpty(),"Audit command id must be set");
   CTestAssert::False(record.EventId().IsEmpty(),"Audit event id must be set");
  }

void OnStart()
  {
   CTestAssert::Reset();
   CAggregateTestFixture fixture;
   CTestAssert::True(fixture.Initialize(),"Aggregate test fixture must initialize");

   TestCreateAggregate(fixture);
   TestActivateAggregate(fixture);
   TestCloseAggregate(fixture);
   TestInvalidTransition(fixture);
   TestAuditHistory(fixture);

   CTestAssert::Summary("TestBasketAggregate");
   if(!CTestAssert::AllPassed())
      Print("TestBasketAggregate FAILED");
  }
