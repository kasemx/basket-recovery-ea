#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Tests/PersistenceTestPaths.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/TestSequentialIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileCommandPersistence.mqh>
#include <BasketRecovery/Infrastructure/Persistence/PersistentCommandQueue.mqh>
#include <BasketRecovery/Infrastructure/Persistence/CommandSerializer.mqh>
#include <BasketRecovery/Infrastructure/Persistence/CommandSerializerStrategy.mqh>
#include <BasketRecovery/Infrastructure/Commands/InMemoryCommandQueue.mqh>
#include <BasketRecovery/Infrastructure/Idempotency/InMemoryIdempotencyStore.mqh>
#include <BasketRecovery/Infrastructure/Market/InMemoryMarketQuoteProvider.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Application/Kernel/CommandProcessor.mqh>
#include <BasketRecovery/Application/Kernel/CommandDispatcher.mqh>
#include <BasketRecovery/Application/Kernel/EventDispatcher.mqh>
#include <BasketRecovery/Application/Kernel/KernelHandlerRegistration.mqh>
#include <BasketRecovery/Application/Kernel/ApplicationTimerPipeline.mqh>
#include <BasketRecovery/Application/Handlers/Commands/EvaluateStrategyCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/Commands/StrategyExecutionStubHandlers.mqh>
#include <BasketRecovery/Application/Handlers/Commands/DisableRecoveryCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/Commands/MarkProfitLevelCompletedCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/Commands/CreateBasketCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/Commands/ActivateBasketCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/Commands/CloseBasketCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/StateTransitionHandler.mqh>
#include <BasketRecovery/Application/Handlers/Events/StrategyRuntimeEventHandlers.mqh>
#include <BasketRecovery/Application/Handlers/Events/StrategyRuntimeEventHandlersPart2.mqh>
#include <BasketRecovery/Application/Kernel/TransitionEngine.mqh>
#include <BasketRecovery/Application/Kernel/TransitionRuleRegistry.mqh>
#include <BasketRecovery/Application/Kernel/DefaultTransitionRuleTable.mqh>
#include <BasketRecovery/Domain/StateMachine/AlwaysTrueTransitionGuard.mqh>
#include <BasketRecovery/Application/UseCases/EvaluateBasketStrategyUseCase.mqh>
#include <BasketRecovery/Application/UseCases/BindMigratedBasketStrategyUseCase.mqh>
#include <BasketRecovery/Application/FastPath/SymbolBasketIndex.mqh>
#include <BasketRecovery/Application/Services/TimerFallbackEvaluationService.mqh>
#include <BasketRecovery/Application/Services/SystemHealthCheckService.mqh>
#include <BasketRecovery/Application/FastPath/FastCommandStagingBuffer.mqh>
#include <BasketRecovery/Application/FastPath/InMemoryHotPathDiagnostics.mqh>
#include <BasketRecovery/Application/Ports/IStrategyEngine.mqh>
#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Domain/Events/StrategyDomainEvent.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

CStrategyProfileSnapshot BuildBoundSnapshot(const string jsonContent,const CUtcTime &boundAt)
  {
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(jsonContent,boundAt);
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   return CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,jsonContent,boundAt);
  }

CBasketAggregate BuildBoundActiveBasket(const string basketIdValue,const string jsonContent)
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
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   return basket;
  }

CBasketAggregate BuildMigrationRequiredBasket(const string basketIdValue)
  {
   CUtcTime boundAt(1000);
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                  CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                  CExecutionProfileConfig(),boundAt);
   CResult<CBasketAggregate> created=CBasketFactory::Create(CBasketId(basketIdValue),legacy,
                                                          "corr-"+basketIdValue,BRE_DIRECTION_BUY,"XAUUSD",
                                                          CSignalId("sig-"+basketIdValue),boundAt,
                                                          CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.RestoreStrategyBinding(CStrategyProfileSnapshot::CreateUnbound(),true);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   return basket;
  }

void FillStrategyCommandBase(CStrategyCommandBase *command,
                             const CBasketAggregate &basket,
                             const string idempotencyKey)
  {
   command.SetId(CCommandId("cmd-"+idempotencyKey));
   command.SetBasketId(basket.Id());
   command.SetCorrelationKey(basket.CorrelationKey());
   command.SetExpectedBasketVersion(basket.Version());
   command.SetStrategyProfileHash(basket.StrategyProfileHash());
   command.SetIdempotencyKey(idempotencyKey);
   command.SetEnqueuedAt(1000);
  }

ICommand* BuildStrategyCommandSample(const ENUM_BRE_COMMAND_TYPE commandType,const CBasketAggregate &basket)
  {
   ICommand *command=NULL;
   switch(commandType)
     {
      case BRE_COMMAND_EVALUATE_STRATEGY:
         command=new CEvaluateStrategyCommand();
         break;
      case BRE_COMMAND_OPEN_RECOVERY_POSITION:
        {
         COpenRecoveryPositionCommand *typed=new COpenRecoveryPositionCommand();
         typed.SetStepIndex(2);
         typed.SetLotSize(0.01);
         command=typed;
         break;
        }
      case BRE_COMMAND_CLOSE_POSITIONS:
        {
         CClosePositionsCommand *typed=new CClosePositionsCommand();
         typed.SetLevelId("L1");
         typed.SetClosePercent(33.0);
         typed.SetCloseMode(BRE_CLOSE_MODE_WORST_ENTRY_FIRST);
         typed.SetPartialClose(true);
         command=typed;
         break;
        }
      case BRE_COMMAND_MOVE_BASKET_STOP_LOSS:
        {
         CMoveBasketStopLossCommand *typed=new CMoveBasketStopLossCommand();
         typed.SetRuleId("BE1");
         typed.SetStopLossPrice(2345.67);
         command=typed;
         break;
        }
      case BRE_COMMAND_DISABLE_RECOVERY:
         command=new CDisableRecoveryCommand();
         break;
      case BRE_COMMAND_REDUCE_BASKET_RISK:
        {
         CReduceBasketRiskCommand *typed=new CReduceBasketRiskCommand();
         typed.SetClosePercent(25.0);
         command=typed;
         break;
        }
      case BRE_COMMAND_MARK_PROFIT_LEVEL_COMPLETED:
        {
         CMarkProfitLevelCompletedCommand *typed=new CMarkProfitLevelCompletedCommand();
         typed.SetLevelId("L1");
         typed.SetRealizedProfit(42.5);
         command=typed;
         break;
        }
      default:
         return NULL;
     }
   FillStrategyCommandBase((CStrategyCommandBase*)command,basket,"serialize-"+IntegerToString((long)commandType));
   return command;
  }

void TestStrategyCommandSerializationRoundTrip(void)
  {
   string json=CStrategyProfileTestFixture::MinimalValidJson();
   CBasketAggregate basket=BuildBoundActiveBasket("serialize-basket",json);
   CCommandSerializer serializer;
   ENUM_BRE_COMMAND_TYPE types[7]=
     {
      BRE_COMMAND_EVALUATE_STRATEGY,
      BRE_COMMAND_OPEN_RECOVERY_POSITION,
      BRE_COMMAND_CLOSE_POSITIONS,
      BRE_COMMAND_MOVE_BASKET_STOP_LOSS,
      BRE_COMMAND_DISABLE_RECOVERY,
      BRE_COMMAND_REDUCE_BASKET_RISK,
      BRE_COMMAND_MARK_PROFIT_LEVEL_COMPLETED
     };

   for(int i=0;i<7;i++)
     {
      ICommand *original=BuildStrategyCommandSample(types[i],basket);
      CTestAssert::True(original!=NULL,"Strategy command sample must be created");
      ICommand *commands[1];
      commands[0]=original;
      string payload=serializer.SerializePendingCommands(commands,1);
      ICommand *restored[];
      CResult<int> restoredCount=serializer.DeserializePendingCommands(payload,restored);
      int count=0;
      restoredCount.TryGetValue(count);
      string roundTripMessage="Strategy command round-trip count must be 1 for type "+IntegerToString((long)types[i]);
      CTestAssert::EqualInt(1,count,roundTripMessage);
      CTestAssert::EqualInt((long)types[i],(long)restored[0].Type(),"Restored command type must match");
      CTestAssert::EqualString(original.BasketId().Value(),restored[0].BasketId().Value(),"Basket id must round-trip");
      CTestAssert::EqualString(original.IdempotencyKey(),restored[0].IdempotencyKey(),"Idempotency key must round-trip");
      CTestAssert::EqualString(original.CorrelationKey(),restored[0].CorrelationKey(),"Correlation key must round-trip");
      CStrategyCommandBase *originalStrategy=(CStrategyCommandBase*)original;
      CStrategyCommandBase *restoredStrategy=(CStrategyCommandBase*)restored[0];
      CTestAssert::EqualInt((long)originalStrategy.ExpectedBasketVersion(),(long)restoredStrategy.ExpectedBasketVersion(),
                            "Expected basket version must round-trip");
      CTestAssert::EqualString(originalStrategy.StrategyProfileHash(),restoredStrategy.StrategyProfileHash(),
                               "Strategy profile hash must round-trip");
      delete original;
      delete restored[0];
     }
  }

void TestStrategyCommandRestartRecovery(void)
  {
   CPersistenceTestPaths::Cleanup();
   string json=CStrategyProfileTestFixture::MinimalValidJson();
   CBasketAggregate basket=BuildBoundActiveBasket("restart-cmd-basket",json);
   CFileCommandPersistence persistence(BRE_TEST_PERSISTENCE_COMMANDS_FILE);
   CPersistentCommandQueue queue(&persistence);

   ENUM_BRE_COMMAND_TYPE types[7]=
     {
      BRE_COMMAND_EVALUATE_STRATEGY,
      BRE_COMMAND_OPEN_RECOVERY_POSITION,
      BRE_COMMAND_CLOSE_POSITIONS,
      BRE_COMMAND_MOVE_BASKET_STOP_LOSS,
      BRE_COMMAND_DISABLE_RECOVERY,
      BRE_COMMAND_REDUCE_BASKET_RISK,
      BRE_COMMAND_MARK_PROFIT_LEVEL_COMPLETED
     };

   for(int i=0;i<7;i++)
     {
      ICommand *command=BuildStrategyCommandSample(types[i],basket);
      CCommandBase *commandBase=(CCommandBase*)command;
      commandBase.SetIdempotencyKey("restart-"+IntegerToString((long)types[i]));
      string enqueueMessage="Restart recovery enqueue must succeed for type "+IntegerToString((long)types[i]);
      CTestAssert::True(queue.Enqueue(command).IsOk(),enqueueMessage);
     }

   CPersistentCommandQueue recovered(&persistence);
   CTestAssert::True(recovered.RecoverFromPersistence().IsOk(),"Strategy command restart recovery must succeed");
   CTestAssert::EqualInt(7,recovered.PendingCount(),"All seven strategy commands must be restored");
  }

void TestEvaluateStrategyDispatchAndEnqueue(void)
  {
   CInMemoryBasketRepository repository;
   CInMemoryCommandQueue queue;
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;
   CStrategyEngineAdapter strategyEngine;
   CInMemoryMarketQuoteProvider marketProvider;

   string json=CStrategyProfileTestFixture::MinimalValidJson();
   CBasketAggregate basket=BuildBoundActiveBasket("eval-dispatch",json);
   long versionBefore=basket.Version();
   repository.Save(basket);
   marketProvider.SetQuote("XAUUSD",2350.0,2350.2,0.01);

   CInMemorySnapshotStore snapshotStore(&clock);

   CEvaluateBasketStrategyUseCase useCase(&repository,&strategyEngine,&queue,&clock,&idGenerator,&snapshotStore);
   CEvaluateStrategyCommandHandler evaluateHandler(&useCase,&marketProvider);
   CCommandDispatcher dispatcher;
   dispatcher.RegisterHandler(&evaluateHandler,40);

   CInMemoryIdempotencyStore idempotencyStore;
   CEventDispatcher eventDispatcher;
   CCommandProcessor processor(&queue,&dispatcher,&eventDispatcher,&idempotencyStore);

   CEvaluateStrategyCommand *command=new CEvaluateStrategyCommand();
   FillStrategyCommandBase(command,basket,"eval-dispatch-key");
   queue.Enqueue(command);

   int commandsProcessed=0;
   int eventsProcessed=0;
   CTestAssert::True(processor.RunCycle(commandsProcessed,eventsProcessed).IsOk(),"Evaluate dispatch cycle must succeed");
   CTestAssert::EqualInt(1,commandsProcessed,"Evaluate command must be processed");

   CResult<CBasketAggregate> reloaded=repository.Load(basket.Id());
   CBasketAggregate updated;
   reloaded.TryGetValue(updated);
   CTestAssert::True(updated.Version()>versionBefore,"Evaluation must bump basket version via audit");
  }

void TestEvaluateRejectsStaleVersion(void)
  {
   CInMemoryBasketRepository repository;
   CInMemoryCommandQueue queue;
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;
   CStrategyEngineAdapter strategyEngine;
   CInMemoryMarketQuoteProvider marketProvider;

   CBasketAggregate basket=BuildBoundActiveBasket("eval-stale",CStrategyProfileTestFixture::MinimalValidJson());
   repository.Save(basket);
   marketProvider.SetQuote("XAUUSD",2350.0,2350.2,0.01);

   CInMemorySnapshotStore snapshotStore(&clock);

   CEvaluateBasketStrategyUseCase useCase(&repository,&strategyEngine,&queue,&clock,&idGenerator,&snapshotStore);
   CEvaluateStrategyCommandHandler evaluateHandler(&useCase,&marketProvider);
   CCommandDispatcher dispatcher;
   dispatcher.RegisterHandler(&evaluateHandler,40);
   CInMemoryIdempotencyStore idempotencyStore;
   CCommandProcessor processor(&queue,&dispatcher,new CEventDispatcher(),&idempotencyStore);

   CEvaluateStrategyCommand *command=new CEvaluateStrategyCommand();
   FillStrategyCommandBase(command,basket,"eval-stale-key");
   command.SetExpectedBasketVersion(basket.Version()-1);
   queue.Enqueue(command);

   int commandsProcessed=0;
   int eventsProcessed=0;
   processor.RunCycle(commandsProcessed,eventsProcessed);
   CTestAssert::False(idempotencyStore.IsProcessed("eval-stale-key"),"Stale version must not mark idempotency processed");
  }

void TestEvaluateRejectsHashMismatch(void)
  {
   CInMemoryBasketRepository repository;
   CInMemoryCommandQueue queue;
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;
   CStrategyEngineAdapter strategyEngine;
   CInMemoryMarketQuoteProvider marketProvider;

   CBasketAggregate basket=BuildBoundActiveBasket("eval-hash",CStrategyProfileTestFixture::MinimalValidJson());
   repository.Save(basket);
   marketProvider.SetQuote("XAUUSD",2350.0,2350.2,0.01);

   CInMemorySnapshotStore snapshotStore(&clock);

   CEvaluateBasketStrategyUseCase useCase(&repository,&strategyEngine,&queue,&clock,&idGenerator,&snapshotStore);
   CEvaluateStrategyCommandHandler evaluateHandler(&useCase,&marketProvider);
   CCommandDispatcher dispatcher;
   dispatcher.RegisterHandler(&evaluateHandler,40);
   CInMemoryIdempotencyStore idempotencyStore;
   CCommandProcessor processor(&queue,&dispatcher,new CEventDispatcher(),&idempotencyStore);

   CEvaluateStrategyCommand *command=new CEvaluateStrategyCommand();
   FillStrategyCommandBase(command,basket,"eval-hash-key");
   command.SetStrategyProfileHash("wrong-hash");
   queue.Enqueue(command);

   int commandsProcessed=0;
   int eventsProcessed=0;
   processor.RunCycle(commandsProcessed,eventsProcessed);
   CTestAssert::False(idempotencyStore.IsProcessed("eval-hash-key"),"Hash mismatch must not mark idempotency processed");
  }

void TestEvaluateRejectsMigrationRequired(void)
  {
   CInMemoryBasketRepository repository;
   CInMemoryCommandQueue queue;
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;
   CStrategyEngineAdapter strategyEngine;
   CInMemoryMarketQuoteProvider marketProvider;

   CBasketAggregate basket=BuildMigrationRequiredBasket("eval-migration");
   repository.Save(basket);

   CInMemorySnapshotStore snapshotStore(&clock);

   CEvaluateBasketStrategyUseCase useCase(&repository,&strategyEngine,&queue,&clock,&idGenerator,&snapshotStore);
   CEvaluateStrategyCommandHandler evaluateHandler(&useCase,&marketProvider);
   CCommandDispatcher dispatcher;
   dispatcher.RegisterHandler(&evaluateHandler,40);
   CInMemoryIdempotencyStore idempotencyStore;
   CCommandProcessor processor(&queue,&dispatcher,new CEventDispatcher(),&idempotencyStore);

   CEvaluateStrategyCommand *command=new CEvaluateStrategyCommand();
   command.SetId(CCommandId("cmd-migration-eval"));
   command.SetBasketId(basket.Id());
   command.SetCorrelationKey(basket.CorrelationKey());
   command.SetExpectedBasketVersion(basket.Version());
   command.SetStrategyProfileHash("");
   command.SetIdempotencyKey("eval-migration-key");
   queue.Enqueue(command);

   int commandsProcessed=0;
   int eventsProcessed=0;
   processor.RunCycle(commandsProcessed,eventsProcessed);
   CTestAssert::False(idempotencyStore.IsProcessed("eval-migration-key"),"Migration-required basket must reject evaluation");
  }

void TestControlledMigrationSuccess(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;

   CBasketAggregate basket=BuildMigrationRequiredBasket("migration-success");
   repository.Save(basket);

   string json=CStrategyProfileTestFixture::MinimalValidJson();
   CStrategyProfileJsonParser parser;
   CStrategyProfile profile;
   parser.Parse(json,CUtcTime(2000)).TryGetValue(profile);

   CBindMigratedBasketStrategyUseCase useCase(&repository,&clock,&idGenerator);
   CDomainEventResult result=useCase.Execute(basket.Id(),json,profile);
   CTestAssert::True(result.IsOk(),"Controlled migration must succeed");

   CResult<CBasketAggregate> loaded=repository.Load(basket.Id());
   CBasketAggregate migrated;
   loaded.TryGetValue(migrated);
   CTestAssert::False(migrated.StrategyMigrationRequired(),"Migration must clear migration-required flag");
   CTestAssert::True(migrated.HasStrategyProfile(),"Migration must bind explicit strategy snapshot");
   CTestAssert::EqualString("json-test",migrated.StrategyId(),"Migration must use explicit profile id");

   CDomainEvent *event=NULL;
   result.TryGetEvent(event);
   if(event!=NULL)
     {
      CTestAssert::EqualInt((long)BRE_EVENT_STRATEGY_PROFILE_BOUND,(long)event.EventType(),"Migration must emit profile bound event");
      delete event;
     }
  }

void TestDuplicateProfitLevelReachedRejection(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;
   CProfitLevelReachedEventHandler handler(&repository,&clock,&idGenerator);

   CBasketAggregate basket=BuildBoundActiveBasket("dup-profit",CStrategyProfileTestFixture::MinimalValidJson());
   basket.ApplyProfitLevelReached("L1",CUtcTime(5000),CCommandId("cmd-l1"),CEventId("evt-l1"));
   repository.Save(basket);

   CStrategyDomainEvent *event=new CStrategyDomainEvent();
   event.SetEventType(BRE_EVENT_PROFIT_LEVEL_REACHED);
   event.SetBasketId(basket.Id());
   event.SetLevelId("L1");
   CResult<CEventHandlingResult> result=handler.Handle(event);
   delete event;
   CTestAssert::True(result.IsFail(),"Duplicate profit level reached must fail");
   CTestAssert::EqualInt(BRE_ERR_PROFIT_LEVEL_ALREADY_REACHED,result.ErrorCode(),"Duplicate profit level error code must match");
  }

void TestDuplicateBreakEvenRuleRejection(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;
   CBreakEvenActivatedEventHandler handler(&repository,&clock,&idGenerator);

   CBasketAggregate basket=BuildBoundActiveBasket("dup-be",CStrategyProfileTestFixture::MinimalValidJson());
   basket.ApplyBreakEvenActivated("BE1",CCommandId("cmd-be"),CEventId("evt-be"),CUtcTime(6000));
   repository.Save(basket);

   CStrategyDomainEvent *event=new CStrategyDomainEvent();
   event.SetEventType(BRE_EVENT_BREAK_EVEN_ACTIVATED);
   event.SetBasketId(basket.Id());
   event.SetRuleId("BE1");
   CResult<CEventHandlingResult> result=handler.Handle(event);
   delete event;
   CTestAssert::True(result.IsFail(),"Duplicate break-even rule must fail");
   CTestAssert::EqualInt(BRE_ERR_BREAK_EVEN_ALREADY_EXECUTED,result.ErrorCode(),"Duplicate break-even error code must match");
  }

void TestExecutionStubProducesPendingEvent(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   CClosePositionsCommandHandler closeHandler(&repository,&clock);
   CCommandDispatcher dispatcher;
   dispatcher.RegisterHandler(&closeHandler,50);

   CBasketAggregate basket=BuildBoundActiveBasket("stub-close",CStrategyProfileTestFixture::MinimalValidJson());
   repository.Save(basket);

   CClosePositionsCommand *command=new CClosePositionsCommand();
   FillStrategyCommandBase(command,basket,"stub-close-key");
   command.SetLevelId("L1");
   command.SetClosePercent(33.0);

   CResult<CCommandExecutionResult> result=dispatcher.Dispatch(command);
   delete command;
   CTestAssert::True(result.IsOk(),"Execution stub handler must succeed");

   CCommandExecutionResult executionResult;
   result.TryGetValue(executionResult);
   CTestAssert::EqualInt(1,executionResult.EventCount(),"Execution stub must emit one event");
   CDomainEvent *event=executionResult.ReleaseEventAt(0);
   CTestAssert::True(event!=NULL,"Execution pending event must exist");
   CTestAssert::EqualInt((long)BRE_EVENT_EXECUTION_PENDING,(long)event.EventType(),"Event must be execution pending");
   delete event;
  }

void TestActiveOnlyStrategyEvaluationScheduling(void)
  {
   CInMemoryBasketRepository repository;
   CSymbolBasketIndex symbolIndex;

   CBasketAggregate active=BuildBoundActiveBasket("sched-active",CStrategyProfileTestFixture::MinimalValidJson());
   CBasketAggregate pending=BuildBoundActiveBasket("sched-pending",CStrategyProfileTestFixture::MinimalValidJson());
   pending.SetLifecycleState(BRE_STATE_PENDING_OPEN);
   CBasketAggregate migration=BuildMigrationRequiredBasket("sched-migration");
   repository.Save(active);
   repository.Save(pending);
   repository.Save(migration);
   symbolIndex.Rebuild(&repository);

   CBasketId basketIds[];
   int count=symbolIndex.FindActiveBasketIds("XAUUSD",basketIds,10);
   CTestAssert::EqualInt(1,count,"Symbol index must return only ACTIVE baskets for symbol");
   CTestAssert::EqualString("sched-active",basketIds[0].Value(),"Symbol index must map active basket id");
  }

void TestTimerPipelineOrdering(void)
  {
   CInMemoryBasketRepository repository;
   CInMemoryCommandQueue queue;
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;
   CInMemoryIdempotencyStore idempotencyStore;

   CBasketAggregate basket=BuildBoundActiveBasket("timer-order",CStrategyProfileTestFixture::MinimalValidJson());
   repository.Save(basket);

   CClosePositionsCommandHandler closeHandler(&repository,&clock);
   CCommandDispatcher commandDispatcher;
   commandDispatcher.RegisterHandler(&closeHandler,50);
   CEventDispatcher eventDispatcher;
   CCommandProcessor processor(&queue,&commandDispatcher,&eventDispatcher,&idempotencyStore);

   CFastCommandStagingBuffer stagingQueue;
   CTimerFallbackEvaluationService fallback(&repository,NULL,NULL,&stagingQueue,NULL,
                                            CFastPathConfig::Create(1,2000,250,5,60000));
   CInMemoryHotPathDiagnostics diagnostics;
   CSystemHealthCheckService healthCheck(&diagnostics,60000);
   CApplicationTimerPipeline pipeline(NULL,&processor,NULL,NULL,&fallback,&healthCheck,&stagingQueue,0);

   CClosePositionsCommand *closeCommand=new CClosePositionsCommand();
   FillStrategyCommandBase(closeCommand,basket,"timer-close-first");
   closeCommand.SetLevelId("L1");
   closeCommand.SetClosePercent(33.0);
   queue.Enqueue(closeCommand);

   int commandsProcessed=0;
   int eventsProcessed=0;
   int evaluationsScheduled=0;
   CTestAssert::True(pipeline.OnTimer(commandsProcessed,eventsProcessed,evaluationsScheduled).IsOk(),"Timer pipeline must succeed");
   CTestAssert::EqualInt(1,commandsProcessed,"Timer pipeline must process queued command on slow path");
   CTestAssert::True(idempotencyStore.IsProcessed("timer-close-first"),"Queued command must be processed in timer cycle");
   CTestAssert::EqualInt(0,evaluationsScheduled,"Timer must not schedule primary strategy evaluation");
  }

CProfileSnapshot BuildDefaultProfileSnapshot(void)
  {
   return CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                   CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                   CExecutionProfileConfig(),CUtcTime(1000));
  }

void AssertDispatchFindsHandler(CCommandDispatcher &dispatcher,ICommand *command,const string label)
  {
   CResult<CCommandExecutionResult> result=dispatcher.Dispatch(command);
   string message=label+" must resolve a handler";
   CTestAssert::True(result.ErrorCode()!=BRE_ERR_HANDLER_NOT_FOUND,message);
  }

void AssertExecutionStubPending(CCommandDispatcher &dispatcher,
                              ICommand *command,
                              const string label)
  {
   CResult<CCommandExecutionResult> result=dispatcher.Dispatch(command);
   string successMessage=label+" stub must succeed";
   CTestAssert::True(result.IsOk(),successMessage);
   CCommandExecutionResult executionResult;
   result.TryGetValue(executionResult);
   CDomainEvent *event=executionResult.ReleaseEventAt(0);
   string eventMessage=label+" must emit event";
   CTestAssert::True(event!=NULL,eventMessage);
   string pendingMessage=label+" must be execution pending";
   CTestAssert::EqualInt((long)BRE_EVENT_EXECUTION_PENDING,(long)event.EventType(),pendingMessage);
   delete event;
  }

void TestHandlerRegistrationMap(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;
   CTransitionRuleRegistry registry;
   CAlwaysTrueTransitionGuard guard;
   CDefaultTransitionRuleTable::RegisterDefaultRules(registry,&guard);
   CTransitionEngine engine(&registry);
   CStateTransitionHandler transitionHandler(&engine);
   CProfileSnapshot profileSnapshot=BuildDefaultProfileSnapshot();

   CStrategyEngineAdapter strategyEngine;
   CInMemoryCommandQueue queue;
   CInMemoryMarketQuoteProvider marketProvider;
   CInMemorySnapshotStore snapshotStore(&clock);

   CEvaluateBasketStrategyUseCase useCase(&repository,&strategyEngine,&queue,&clock,&idGenerator,&snapshotStore);

   CCreateBasketCommandHandler createHandler(&repository,&clock,&idGenerator,profileSnapshot);
   CActivateBasketCommandHandler activateHandler(&repository,&transitionHandler,&clock,&idGenerator);
   CCloseBasketCommandHandler closeHandler(&repository,&transitionHandler,&clock,&idGenerator);
   CEvaluateStrategyCommandHandler evaluateHandler(&useCase,&marketProvider);
   COpenRecoveryPositionCommandHandler openHandler(&repository,&clock);
   CClosePositionsCommandHandler closePositionsHandler(&repository,&clock);
   CMoveBasketStopLossCommandHandler moveHandler(&repository,&clock);
   CReduceBasketRiskCommandHandler reduceHandler(&repository,&clock);
   CDisableRecoveryCommandHandler disableHandler(&repository,&clock,&idGenerator);
   CMarkProfitLevelCompletedCommandHandler markHandler(&repository,&clock,&idGenerator);

   CCommandDispatcher dispatcher;
   CKernelHandlerRegistration::RegisterCommandHandlers(dispatcher,
      &createHandler,&activateHandler,&closeHandler,&evaluateHandler,
      &openHandler,&closePositionsHandler,&moveHandler,&reduceHandler,
      &disableHandler,&markHandler);

   CTestAssert::EqualInt(10,dispatcher.HandlerCount(),"Kernel registration must wire ten command handlers");

   string json=CStrategyProfileTestFixture::MinimalValidJson();
   CBasketAggregate basket=BuildBoundActiveBasket("handler-map",json);
   repository.Save(basket);

   ENUM_BRE_COMMAND_TYPE strategyTypes[7]=
     {
      BRE_COMMAND_EVALUATE_STRATEGY,
      BRE_COMMAND_OPEN_RECOVERY_POSITION,
      BRE_COMMAND_CLOSE_POSITIONS,
      BRE_COMMAND_MOVE_BASKET_STOP_LOSS,
      BRE_COMMAND_DISABLE_RECOVERY,
      BRE_COMMAND_REDUCE_BASKET_RISK,
      BRE_COMMAND_MARK_PROFIT_LEVEL_COMPLETED
     };

   for(int i=0;i<7;i++)
     {
      ICommand *command=BuildStrategyCommandSample(strategyTypes[i],basket);
      string label="Command type "+IntegerToString((long)strategyTypes[i]);
      AssertDispatchFindsHandler(dispatcher,command,label);
      delete command;
     }
  }

void TestAllExecutionStubHandlersProducePendingEvent(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   CCommandDispatcher dispatcher;
   COpenRecoveryPositionCommandHandler openHandler(&repository,&clock);
   CClosePositionsCommandHandler closeHandler(&repository,&clock);
   CMoveBasketStopLossCommandHandler moveHandler(&repository,&clock);
   CReduceBasketRiskCommandHandler reduceHandler(&repository,&clock);
   dispatcher.RegisterHandler(&openHandler,50);
   dispatcher.RegisterHandler(&closeHandler,50);
   dispatcher.RegisterHandler(&moveHandler,50);
   dispatcher.RegisterHandler(&reduceHandler,50);

   CBasketAggregate basket=BuildBoundActiveBasket("stub-all",CStrategyProfileTestFixture::MinimalValidJson());
   repository.Save(basket);

   ENUM_BRE_COMMAND_TYPE stubTypes[4]=
     {
      BRE_COMMAND_OPEN_RECOVERY_POSITION,
      BRE_COMMAND_CLOSE_POSITIONS,
      BRE_COMMAND_MOVE_BASKET_STOP_LOSS,
      BRE_COMMAND_REDUCE_BASKET_RISK
     };

   for(int i=0;i<4;i++)
     {
      ICommand *command=BuildStrategyCommandSample(stubTypes[i],basket);
      string label="Stub type "+IntegerToString((long)stubTypes[i]);
      AssertExecutionStubPending(dispatcher,command,label);
      delete command;
     }
  }

void TestMigrationRejectsAlreadyBoundBasket(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;
   string json=CStrategyProfileTestFixture::MinimalValidJson();

   CBasketAggregate basket=BuildBoundActiveBasket("migration-already-bound",json);
   repository.Save(basket);

   CStrategyProfileJsonParser parser;
   CStrategyProfile profile;
   parser.Parse(json,CUtcTime(2000)).TryGetValue(profile);

   CBindMigratedBasketStrategyUseCase useCase(&repository,&clock,&idGenerator);
   CDomainEventResult result=useCase.Execute(basket.Id(),json,profile);
   CTestAssert::True(result.IsFail(),"Already-bound basket must reject controlled migration");
   CTestAssert::EqualInt(BRE_ERR_STRATEGY_ALREADY_BOUND,result.ErrorCode(),"Already-bound error code must match");
  }

void OnStart()
  {
   CTestAssert::Reset();
   TestStrategyCommandSerializationRoundTrip();
   TestStrategyCommandRestartRecovery();
   TestEvaluateStrategyDispatchAndEnqueue();
   TestEvaluateRejectsStaleVersion();
   TestEvaluateRejectsHashMismatch();
   TestEvaluateRejectsMigrationRequired();
   TestControlledMigrationSuccess();
   TestDuplicateProfitLevelReachedRejection();
   TestDuplicateBreakEvenRuleRejection();
   TestExecutionStubProducesPendingEvent();
   TestAllExecutionStubHandlersProducePendingEvent();
   TestHandlerRegistrationMap();
   TestMigrationRejectsAlreadyBoundBasket();
   TestActiveOnlyStrategyEvaluationScheduling();
   TestTimerPipelineOrdering();
   CPersistenceTestPaths::Cleanup();
   CTestAssert::Summary("TestStrategyCommandWiring");
   if(!CTestAssert::AllPassed())
      Print("TestStrategyCommandWiring FAILED");
  }
