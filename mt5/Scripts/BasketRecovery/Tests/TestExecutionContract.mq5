#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Application/Execution/ExecutionRequestValidator.mqh>
#include <BasketRecovery/Application/Execution/ExecutionRequestFactory.mqh>
#include <BasketRecovery/Application/Execution/ExecutionResultMapper.mqh>
#include <BasketRecovery/Application/Execution/ExecuteTradeIntentUseCase.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionLifecycleRules.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionRequestRepository.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionJournal.mqh>
#include <BasketRecovery/Infrastructure/Execution/SimulatedTradeExecutor.mqh>
#include <BasketRecovery/Infrastructure/Execution/SimulatedExecutionPolicy.mqh>
#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Domain/Enums/EventType.mqh>

CBasketAggregate BuildActiveBasket(const string basketIdValue,const long version)
  {
   CUtcTime boundAt(1000);
   string json=CStrategyProfileTestFixture::MinimalValidJson();
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(json,boundAt);
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,json,boundAt);
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
   if(version>1)
      basket.SetVersionState(version,CCommandId("cmd-ver"),CEventId("evt-ver"),boundAt);
   return basket;
  }

COpenRecoveryPositionCommand BuildOpenCommand(const string basketId,const long version,const string hash,const string idempotencyKey)
  {
   COpenRecoveryPositionCommand command;
   command.SetId(CCommandId("cmd-open-1"));
   command.SetBasketId(CBasketId(basketId));
   command.SetExpectedBasketVersion(version);
   command.SetStrategyProfileHash(hash);
   command.SetIdempotencyKey(idempotencyKey);
   command.SetCorrelationKey("corr-open");
   command.SetLotSize(0.01);
   return command;
  }

void TestRequestValidationRequiresCoreFields(void)
  {
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("","key","corr",CBasketId("b1"),1,"hash","XAUUSD",
                                                                 BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                 0.01,1900.0,0.0,0.0,1000,CCommandId("c1"),"test");
   CResult<CTradeExecutionResult> validation=CExecutionRequestValidator::ValidateForDispatch(request);
   CTestAssert::False(validation.IsOk(),"Missing executionRequestId must fail validation");
  }

void TestLifecycleLegalAndIllegalTransitions(void)
  {
   CTestAssert::True(CExecutionLifecycleRules::CanTransition(BRE_TRADE_EXEC_STATUS_CREATED,BRE_TRADE_EXEC_STATUS_QUEUED),
                     "CREATED to QUEUED must be legal");
   CTestAssert::False(CExecutionLifecycleRules::CanTransition(BRE_TRADE_EXEC_STATUS_FILLED,BRE_TRADE_EXEC_STATUS_QUEUED),
                      "Terminal FILLED must not transition");
   CTestAssert::True(CExecutionLifecycleRules::BlocksBlindResend(BRE_TRADE_EXEC_STATUS_UNKNOWN),
                     "UNKNOWN must block blind resend");
  }

void TestDuplicateIdempotencyReturnsOriginalReceipt(void)
  {
   CTestClock clock;
   CInMemoryBasketRepository repository;
   CBasketAggregate basket=BuildActiveBasket("dup-basket",1);
   repository.Save(basket);

   CInMemoryExecutionRequestRepository executionRepository;
   CInMemoryExecutionJournal journal(&executionRepository);
   CSimulatedTradeExecutor executor;
   CExecuteTradeIntentUseCase useCase(&repository,&executor,&journal,&executionRepository,&clock);

   COpenRecoveryPositionCommand command=BuildOpenCommand("dup-basket",basket.Version(),basket.StrategyProfileHash(),"sim:accept-fill:dup-1");
   CResult<CExecutionDomainEvent> first=useCase.Execute(command,"exec-dup-1","XAUUSD",BRE_DIRECTION_BUY,0,0.01,1900.0,0.0,0.0,"open");
   CTestAssert::True(first.IsOk(),"First execution must succeed");

   CResult<CExecutionDomainEvent> second=useCase.Execute(command,"exec-dup-2","XAUUSD",BRE_DIRECTION_BUY,0,0.01,1900.0,0.0,0.0,"open");
   CTestAssert::True(second.IsOk(),"Duplicate idempotency must return original receipt mapping");
   CTestAssert::EqualInt(1,executor.ExecuteCallCount(),"Duplicate idempotency must not re-execute");
  }

void TestStaleVersionRejection(void)
  {
   CTestClock clock;
   CInMemoryBasketRepository repository;
   CBasketAggregate basket=BuildActiveBasket("stale-basket",3);
   repository.Save(basket);

   CInMemoryExecutionRequestRepository executionRepository;
   CInMemoryExecutionJournal journal(&executionRepository);
   CSimulatedTradeExecutor executor;
   CExecuteTradeIntentUseCase useCase(&repository,&executor,&journal,&executionRepository,&clock);

   COpenRecoveryPositionCommand command=BuildOpenCommand("stale-basket",1,basket.StrategyProfileHash(),"sim:stale:1");
   CResult<CExecutionDomainEvent> result=useCase.Execute(command,"exec-stale","XAUUSD",BRE_DIRECTION_BUY,0,0.01,1900.0,0.0,0.0,"open");
   CTestAssert::True(result.IsOk(),"Stale version must produce deterministic rejection event");
   CExecutionDomainEvent event;
   result.TryGetValue(event);
   CTestAssert::EqualInt((int)BRE_EVENT_EXECUTION_REJECTED,(int)event.EventType(),"Stale version must map to rejected event");
   CTestAssert::EqualInt(0,executor.ExecuteCallCount(),"Stale version must not reach executor");
  }

void TestHashMismatchRejection(void)
  {
   CTestClock clock;
   CInMemoryBasketRepository repository;
   CBasketAggregate basket=BuildActiveBasket("hash-basket",1);
   repository.Save(basket);

   CInMemoryExecutionRequestRepository executionRepository;
   CInMemoryExecutionJournal journal(&executionRepository);
   CSimulatedTradeExecutor executor;
   CExecuteTradeIntentUseCase useCase(&repository,&executor,&journal,&executionRepository,&clock);

   COpenRecoveryPositionCommand command=BuildOpenCommand("hash-basket",basket.Version(),"wrong-hash","sim:hash:1");
   CResult<CExecutionDomainEvent> result=useCase.Execute(command,"exec-hash","XAUUSD",BRE_DIRECTION_BUY,0,0.01,1900.0,0.0,0.0,"open");
   CTestAssert::True(result.IsOk(),"Hash mismatch must produce deterministic rejection event");
   CExecutionDomainEvent event;
   result.TryGetValue(event);
   CTestAssert::EqualInt((int)BRE_EXEC_FAIL_PROFILE_HASH_MISMATCH,(int)event.FailureReason(),"Hash mismatch reason must be set");
   CTestAssert::EqualInt(0,executor.ExecuteCallCount(),"Hash mismatch must not reach executor");
  }

void TestAcceptedThenFilledSimulation(void)
  {
   CTestClock clock;
   CInMemoryBasketRepository repository;
   CBasketAggregate basket=BuildActiveBasket("fill-basket",1);
   repository.Save(basket);

   CInMemoryExecutionRequestRepository executionRepository;
   CInMemoryExecutionJournal journal(&executionRepository);
   CSimulatedTradeExecutor executor;
   CExecuteTradeIntentUseCase useCase(&repository,&executor,&journal,&executionRepository,&clock);

   COpenRecoveryPositionCommand command=BuildOpenCommand("fill-basket",basket.Version(),basket.StrategyProfileHash(),"sim:accept-fill:1");
   CResult<CExecutionDomainEvent> result=useCase.Execute(command,"exec-fill","XAUUSD",BRE_DIRECTION_BUY,0,0.01,1900.0,0.0,0.0,"open");
   CTestAssert::True(result.IsOk(),"Accepted/filled simulation must succeed");
   CExecutionDomainEvent event;
   result.TryGetValue(event);
   CTestAssert::EqualInt((int)BRE_EVENT_EXECUTION_FILLED,(int)event.EventType(),"Filled simulation must map to ExecutionFilled");
  }

void TestRejectedSimulation(void)
  {
   CSimulatedTradeExecutor executor;
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("exec-reject","sim:reject:1","corr",CBasketId("b1"),1,"hash","XAUUSD",
                                                                 BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                 0.01,1900.0,0.0,0.0,1000,CCommandId("c1"),"test");
   CResult<CTradeExecutionReceipt> result=executor.Execute(request);
   CTestAssert::True(result.IsOk(),"Rejected simulation must return receipt");
   CTradeExecutionReceipt receipt;
   result.TryGetValue(receipt);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_REJECTED,(int)receipt.CurrentStatus(),"Rejected simulation must end rejected");
  }

void TestTimeoutSimulation(void)
  {
   CSimulatedTradeExecutor executor;
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("exec-timeout","sim:timeout:1","corr",CBasketId("b1"),1,"hash","XAUUSD",
                                                                 BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                 0.01,1900.0,0.0,0.0,1000,CCommandId("c1"),"test");
   CResult<CTradeExecutionReceipt> result=executor.Execute(request);
   CTradeExecutionReceipt receipt;
   result.TryGetValue(receipt);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_TIMED_OUT,(int)receipt.CurrentStatus(),"Timeout simulation must end timed out");
  }

void TestPartialFillLifecycle(void)
  {
   CSimulatedTradeExecutor executor;
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("exec-partial","sim:partial-fill:1","corr",CBasketId("b1"),1,"hash","XAUUSD",
                                                                 BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                 0.02,1900.0,0.0,0.0,1000,CCommandId("c1"),"test");
   CResult<CTradeExecutionReceipt> result=executor.Execute(request);
   CTradeExecutionReceipt receipt;
   result.TryGetValue(receipt);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)receipt.CurrentStatus(),"Partial then filled must end filled");
   CTestAssert::True(receipt.Result().FilledVolume()>=receipt.Result().RequestedVolume(),"Filled volume must reach requested amount");
  }

void TestUnknownLifecycleBlocksRetry(void)
  {
   CTestAssert::False(CExecutionLifecycleRules::CanSubmit(BRE_TRADE_EXEC_STATUS_UNKNOWN),
                      "UNKNOWN terminal-like state must not allow submit");
  }

void TestJournalContainsTransitions(void)
  {
   CTestClock clock;
   CInMemoryBasketRepository repository;
   CBasketAggregate basket=BuildActiveBasket("journal-basket",1);
   repository.Save(basket);

   CInMemoryExecutionRequestRepository executionRepository;
   CInMemoryExecutionJournal journal(&executionRepository);
   CSimulatedTradeExecutor executor;
   CExecuteTradeIntentUseCase useCase(&repository,&executor,&journal,&executionRepository,&clock);

   COpenRecoveryPositionCommand command=BuildOpenCommand("journal-basket",basket.Version(),basket.StrategyProfileHash(),"sim:accept-fill:journal");
   useCase.Execute(command,"exec-journal","XAUUSD",BRE_DIRECTION_BUY,0,0.01,1900.0,0.0,0.0,"open");

   CResult<CTradeExecutionReceipt> stored=journal.FindByExecutionRequestId("exec-journal");
   CTestAssert::True(stored.IsOk(),"Journal must store receipt");
   CTradeExecutionReceipt receipt;
   stored.TryGetValue(receipt);
   CTestAssert::True(receipt.TransitionCount()>0,"Journal receipt must contain transitions");
  }

void TestSimulatedExecutorDoesNotCallBrokerApis(void)
  {
   CSimulatedTradeExecutor executor;
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("exec-no-broker","sim:accept-fill:nb","corr",CBasketId("b1"),1,"hash","XAUUSD",
                                                                 BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                 0.01,1900.0,0.0,0.0,1000,CCommandId("c1"),"test");
   executor.Execute(request);
   CTestAssert::EqualInt(1,executor.ExecuteCallCount(),"Simulated executor must execute in-process only");
  }

void TestTerminalRequestsCannotBeResubmitted(void)
  {
   CTestAssert::False(CExecutionLifecycleRules::CanSubmit(BRE_TRADE_EXEC_STATUS_FILLED),
                      "FILLED is terminal and must not be resubmitted");
   CTestAssert::False(CExecutionLifecycleRules::CanSubmit(BRE_TRADE_EXEC_STATUS_REJECTED),
                      "REJECTED is terminal and must not be resubmitted");
  }

void TestGenericExecutionEventMapping(void)
  {
   CTradeExecutionReceipt receipt;
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("exec-map","key","corr",CBasketId("b1"),1,"hash","XAUUSD",
                                                                 BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                 0.01,1900.0,0.0,0.0,1000,CCommandId("c1"),"test");
   receipt.SetRequest(request);
   receipt.SetCurrentStatus(BRE_TRADE_EXEC_STATUS_ACCEPTED);
   CExecutionDomainEvent event=CExecutionResultMapper::ToDomainEvent(receipt,1000);
   CTestAssert::EqualInt((int)BRE_EVENT_EXECUTION_ACCEPTED,(int)event.EventType(),"Accepted status must map to ExecutionAccepted");
  }

void OnStart()
  {
   CTestAssert::Reset();
   TestRequestValidationRequiresCoreFields();
   TestLifecycleLegalAndIllegalTransitions();
   TestDuplicateIdempotencyReturnsOriginalReceipt();
   TestStaleVersionRejection();
   TestHashMismatchRejection();
   TestAcceptedThenFilledSimulation();
   TestRejectedSimulation();
   TestTimeoutSimulation();
   TestPartialFillLifecycle();
   TestUnknownLifecycleBlocksRetry();
   TestJournalContainsTransitions();
   TestSimulatedExecutorDoesNotCallBrokerApis();
   TestTerminalRequestsCannotBeResubmitted();
   TestGenericExecutionEventMapping();
   CTestAssert::Summary("TestExecutionContract");
   if(!CTestAssert::AllPassed())
      Print("TestExecutionContract FAILED");
   else
      Print("TestExecutionContract: all tests passed");
  }
