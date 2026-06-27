#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/Handlers/KernelTestCreateBasketHandler.mqh>
#include <BasketRecovery/Tests/Handlers/KernelTestBasketCreatedEventHandler.mqh>
#include <BasketRecovery/Application/Kernel/CommandDispatcher.mqh>
#include <BasketRecovery/Application/Kernel/EventDispatcher.mqh>
#include <BasketRecovery/Application/Commands/CreateBasketCommand.mqh>

void TestCommandDispatcherRouting(void)
  {
   CCommandDispatcher dispatcher;
   CKernelTestCreateBasketCommandHandler handler;
   dispatcher.RegisterHandler(&handler,10);

   CCreateBasketCommand command;
   command.SetId(CCommandId("cmd-dispatch-001"));
   command.SetIdempotencyKey("create:dispatch:001");
   command.SetBasketId(CBasketId("basket-dispatch-001"));

   CTestAssert::True(handler.CanHandle(&command),"Handler must accept create basket command");

   CResult<CCommandExecutionResult> result=dispatcher.Dispatch(&command);
   CTestAssert::True(result.IsOk(),"Command dispatch must succeed");

   CCommandExecutionResult executionResult;
   CTestAssert::True(result.TryGetValue(executionResult),"Execution result must be present");
   CTestAssert::EqualInt(1,executionResult.EventCount(),"Create handler must emit one event");
   CTestAssert::EqualInt(BRE_EVENT_BASKET_CREATED,executionResult.EventAt(0).EventType(),"Event type must be BasketCreated");
   executionResult.ClearEvents();
  }

void TestEventDispatcherRouting(void)
  {
   CEventDispatcher dispatcher;
   CKernelTestBasketCreatedEventHandler handler;
   dispatcher.RegisterHandler(&handler);

   CDomainEvent event;
   event.SetEventType(BRE_EVENT_BASKET_CREATED);
   event.SetBasketId(CBasketId("basket-event-001"));

   CTestAssert::True(handler.CanHandle(&event),"Event handler must accept BasketCreated");

   CResult<CEventHandlingResult> result=dispatcher.Dispatch(&event);
   CTestAssert::True(result.IsOk(),"Event dispatch must succeed");

   CEventHandlingResult handlingResult;
   CTestAssert::True(result.TryGetValue(handlingResult),"Handling result must be present");
   CTestAssert::EqualInt(1,handlingResult.CommandCount(),"Event handler must emit one command");
   CTestAssert::EqualInt(BRE_COMMAND_ACTIVATE_BASKET,handlingResult.CommandAt(0).Type(),"Generated command must be ActivateBasket");
   handlingResult.ClearCommands();
  }

void TestMissingHandlerErrors(void)
  {
   CCommandDispatcher commandDispatcher;
   CCreateBasketCommand command;
   command.SetId(CCommandId("cmd-missing-001"));

   CResult<CCommandExecutionResult> commandResult=commandDispatcher.Dispatch(&command);
   CTestAssert::True(commandResult.IsFail(),"Missing command handler must fail");

   CEventDispatcher eventDispatcher;
   CDomainEvent event;
   event.SetEventType(BRE_EVENT_TP1_REACHED);

   CResult<CEventHandlingResult> eventResult=eventDispatcher.Dispatch(&event);
   CTestAssert::True(eventResult.IsOk(),"Event dispatch without handler returns empty success");
  }

void OnStart()
  {
   CTestAssert::Reset();

   TestCommandDispatcherRouting();
   TestEventDispatcherRouting();
   TestMissingHandlerErrors();

   CTestAssert::Summary("TestDispatchers");
   if(!CTestAssert::AllPassed())
      Print("TestDispatchers FAILED");
  }
