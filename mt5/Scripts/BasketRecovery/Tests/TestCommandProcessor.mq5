#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/Handlers/KernelTestCreateBasketHandler.mqh>
#include <BasketRecovery/Tests/Handlers/KernelTestBasketCreatedEventHandler.mqh>
#include <BasketRecovery/Application/Kernel/CommandProcessor.mqh>
#include <BasketRecovery/Application/Kernel/CommandDispatcher.mqh>
#include <BasketRecovery/Application/Kernel/EventDispatcher.mqh>
#include <BasketRecovery/Infrastructure/Commands/InMemoryCommandQueue.mqh>
#include <BasketRecovery/Infrastructure/Idempotency/InMemoryIdempotencyStore.mqh>
#include <BasketRecovery/Application/Commands/CreateBasketCommand.mqh>

void TestSinglePhaseCommandToEvent(void)
  {
   CInMemoryCommandQueue commandQueue;
   CInMemoryIdempotencyStore idempotencyStore;
   CCommandDispatcher commandDispatcher;
   CEventDispatcher eventDispatcher;
   CKernelTestCreateBasketCommandHandler createHandler;
   commandDispatcher.RegisterHandler(&createHandler,10);

   CCommandProcessor processor(&commandQueue,&commandDispatcher,&eventDispatcher,&idempotencyStore);
   processor.SetMaxIterations(4);
   processor.SetMaxCommandsPerPhase(4);

   CCreateBasketCommand *command=new CCreateBasketCommand();
   command.SetId(CCommandId("cmd-processor-001"));
   command.SetIdempotencyKey("create:processor:001");
   command.SetBasketId(CBasketId("basket-processor-001"));
   command.SetCorrelationKey("corr-processor-001");
   commandQueue.Enqueue(command);

   int commandsProcessed=0;
   int eventsProcessed=0;
   CTestAssert::True(processor.RunCycle(commandsProcessed,eventsProcessed).IsOk(),"Processor cycle must succeed");
   CTestAssert::EqualInt(1,commandsProcessed,"One command must be processed");
   CTestAssert::EqualInt(1,eventsProcessed,"One event must be generated in phase one");
   CTestAssert::True(idempotencyStore.IsProcessed("create:processor:001"),"Idempotency key must be stored");
   CTestAssert::EqualInt(0,commandQueue.PendingCount(),"Processed command must be removed from queue");
  }

void TestTwoPhaseCommandEventCommandChain(void)
  {
   CInMemoryCommandQueue commandQueue;
   CInMemoryIdempotencyStore idempotencyStore;
   CCommandDispatcher commandDispatcher;
   CEventDispatcher eventDispatcher;
   CKernelTestCreateBasketCommandHandler createHandler;
   CKernelTestBasketCreatedEventHandler createdEventHandler;
   commandDispatcher.RegisterHandler(&createHandler,10);
   eventDispatcher.RegisterHandler(&createdEventHandler);

   CCommandProcessor processor(&commandQueue,&commandDispatcher,&eventDispatcher,&idempotencyStore);
   processor.SetMaxIterations(4);

   CCreateBasketCommand *command=new CCreateBasketCommand();
   command.SetId(CCommandId("cmd-processor-002"));
   command.SetIdempotencyKey("create:processor:002");
   command.SetBasketId(CBasketId("basket-processor-002"));
   commandQueue.Enqueue(command);

   int commandsProcessed=0;
   int eventsProcessed=0;
   CTestAssert::True(processor.RunCycle(commandsProcessed,eventsProcessed).IsOk(),"Two-phase cycle must succeed");
   CTestAssert::EqualInt(1,commandsProcessed,"Initial command must be processed");
   CTestAssert::EqualInt(1,commandQueue.PendingCount(),"Event phase must enqueue activate command");
  }

void TestDuplicateCommandSkipped(void)
  {
   CInMemoryCommandQueue commandQueue;
   CInMemoryIdempotencyStore idempotencyStore;
   CCommandDispatcher commandDispatcher;
   CEventDispatcher eventDispatcher;
   CKernelTestCreateBasketCommandHandler createHandler;
   commandDispatcher.RegisterHandler(&createHandler,10);

   CCommandProcessor processor(&commandQueue,&commandDispatcher,&eventDispatcher,&idempotencyStore);

   idempotencyStore.MarkProcessed("create:processor:003");

   CCreateBasketCommand *command=new CCreateBasketCommand();
   command.SetId(CCommandId("cmd-processor-003"));
   command.SetIdempotencyKey("create:processor:003");
   commandQueue.Enqueue(command);

   int commandsProcessed=0;
   int eventsProcessed=0;
   CTestAssert::True(processor.RunCycle(commandsProcessed,eventsProcessed).IsOk(),"Duplicate skip cycle must succeed");
   CTestAssert::EqualInt(0,commandsProcessed,"Duplicate command must not execute handler");
   CTestAssert::EqualInt(0,eventsProcessed,"Duplicate command must not generate events");
  }

void TestLoopLimitProtection(void)
  {
   CInMemoryCommandQueue commandQueue;
   CInMemoryIdempotencyStore idempotencyStore;
   CCommandDispatcher commandDispatcher;
   CEventDispatcher eventDispatcher;
   CKernelTestCreateBasketCommandHandler createHandler;
   CKernelTestBasketCreatedEventHandler createdEventHandler;
   commandDispatcher.RegisterHandler(&createHandler,10);
   eventDispatcher.RegisterHandler(&createdEventHandler);

   CCommandProcessor processor(&commandQueue,&commandDispatcher,&eventDispatcher,&idempotencyStore);
   processor.SetMaxIterations(1);

   CCreateBasketCommand *command=new CCreateBasketCommand();
   command.SetId(CCommandId("cmd-processor-004"));
   command.SetIdempotencyKey("create:processor:004");
   commandQueue.Enqueue(command);

   int commandsProcessed=0;
   int eventsProcessed=0;
   CVoidResult result=processor.RunCycle(commandsProcessed,eventsProcessed);
   CTestAssert::True(result.IsFail(),"Loop limit must fail when chained commands remain");
  }

void OnStart()
  {
   CTestAssert::Reset();

   TestSinglePhaseCommandToEvent();
   TestTwoPhaseCommandEventCommandChain();
   TestDuplicateCommandSkipped();
   TestLoopLimitProtection();

   CTestAssert::Summary("TestCommandProcessor");
   if(!CTestAssert::AllPassed())
      Print("TestCommandProcessor FAILED");
  }
