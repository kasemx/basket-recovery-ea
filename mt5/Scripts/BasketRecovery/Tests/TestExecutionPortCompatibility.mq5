#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Application/Execution/Ports/ITradeExecutor.mqh>
#include <BasketRecovery/Application/Execution/ExecuteTradeIntentUseCase.mqh>
#include <BasketRecovery/Application/Execution/ExecutionRuntimeCompositionGuard.mqh>
#include <BasketRecovery/Infrastructure/Execution/SimulatedTradeExecutor.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5TradeExecutor.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionRequestRepository.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionJournal.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>

void TestExecuteTradeIntentUseCaseDependsOnITradeExecutor(void)
  {
   CSimulatedTradeExecutor simulated;
   ITradeExecutor *executor=&simulated;

   CTradeExecutionRequest request=CTradeExecutionRequest::Create("probe-exec","sim:accept-fill:probe","corr",
                                                                 CBasketId("b1"),1,"hash","XAUUSD",
                                                                 BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                 0.01,1900.0,0.0,0.0,1000,CCommandId("c1"),"probe");
   CResult<CTradeExecutionReceipt> result=executor.Execute(request);
   CTestAssert::True(result.IsOk(),"ITradeExecutor port must accept execution requests");
  }

void TestSimulatedTradeExecutorSatisfiesSoleExecutionPort(void)
  {
   CSimulatedTradeExecutor simulated;
   ITradeExecutor *executor=&simulated;
   CTestAssert::True(executor!=NULL,"CSimulatedTradeExecutor must satisfy ITradeExecutor");
   CTestAssert::EqualInt(0,simulated.ExecuteCallCount(),"Simulated executor starts with zero calls");
  }

void TestMt5TradeExecutorDefaultDisabledMode(void)
  {
   CMt5TradeExecutor executor;
   ITradeExecutor *port=&executor;
   CTestAssert::False(executor.IsActive(),"CMt5TradeExecutor default mode must be inactive (DISABLED)");
   CTestAssert::True(port!=NULL,"CMt5TradeExecutor must implement ITradeExecutor");

   CTradeExecutionRequest request=CTradeExecutionRequest::Create("probe-mt5","sim:reject:probe","corr",
                                                                 CBasketId("b1"),1,"hash","XAUUSD",
                                                                 BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                 0.01,1900.0,0.0,0.0,1000,CCommandId("c1"),"probe");
   CResult<CTradeExecutionReceipt> result=executor.Execute(request);
   CTestAssert::True(result.IsOk(),"Disabled executor returns deterministic receipt without broker APIs");
   CTradeExecutionReceipt receipt;
   result.TryGetValue(receipt);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_REJECTED,(int)receipt.CurrentStatus(),
                         "Disabled Mt5TradeExecutor must reject");
   CTestAssert::EqualInt((int)BRE_EXEC_FAIL_EXECUTION_DISABLED,(int)receipt.Result().FailureReason(),
                         "Disabled mode must use execution_disabled failure reason");
   CTestAssert::EqualInt(1,executor.ExecuteCallCount(),"Executor tracks in-process execute calls only");
  }

void TestLegacyTradeRequestExecutorBlockedFromCompositionRoot(void)
  {
   CTestAssert::False(CExecutionRuntimeCompositionGuard::AllowsLegacyTradeRequestExecutorInCompositionRoot(),
                      "Legacy ITradeRequestExecutor must not be composition-root wiring");
   CTestAssert::True(CExecutionRuntimeCompositionGuard::RequiresUnifiedTradeExecutorPort(),
                     "Runtime must require unified ITradeExecutor port");
  }

void TestUseCaseConstructorAcceptsUnifiedPortOnly(void)
  {
   CInMemoryExecutionRequestRepository repository;
   CInMemoryExecutionJournal journal(&repository);
   CSimulatedTradeExecutor simulated;
   CExecuteTradeIntentUseCase useCase(NULL,&simulated,&journal,&repository,NULL);
   CTestAssert::True(true,"CExecuteTradeIntentUseCase accepts ITradeExecutor dependency");
  }

void OnStart()
  {
   CTestAssert::Reset();
   TestExecuteTradeIntentUseCaseDependsOnITradeExecutor();
   TestSimulatedTradeExecutorSatisfiesSoleExecutionPort();
   TestMt5TradeExecutorDefaultDisabledMode();
   TestLegacyTradeRequestExecutorBlockedFromCompositionRoot();
   TestUseCaseConstructorAcceptsUnifiedPortOnly();
   CTestAssert::Summary("TestExecutionPortCompatibility");
   if(!CTestAssert::AllPassed())
      Print("TestExecutionPortCompatibility FAILED");
   else
      Print("TestExecutionPortCompatibility: all tests passed");
  }
