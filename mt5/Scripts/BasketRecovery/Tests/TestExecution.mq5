#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Infrastructure/Execution/MockTradeExecutor.mqh>
#include <BasketRecovery/Infrastructure/Execution/TradeResultMapper.mqh>
#include <BasketRecovery/Infrastructure/Execution/TradeRequestBuilder.mqh>
#include <BasketRecovery/Infrastructure/Execution/ExecutionPolicy.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5TradeExecutor.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

CTradeContext BuildTestContext(void)
  {
   CTradeContext context;
   context.SetBasketId(CBasketId("basket-exec-001"));
   context.SetSignalId(CSignalId("sig-exec-001"));
   context.SetRecoveryStep(0);
   context.SetTradeRole(BRE_TRADE_ROLE_INITIAL);
   context.SetMagic(202606001);
   context.SetCorrelationId("corr-exec-001");
   context.SetIdempotencyKey("open:basket-exec-001:initial:0");
   return context;
  }

CTradeRequest BuildTestRequest(void)
  {
   CTradeRequest request;
   request.SetId(CRequestId("req-exec-001"));
   request.SetType(BRE_TRADE_REQUEST_OPEN_MARKET);
   request.SetBasketId(CBasketId("basket-exec-001"));
   request.SetSymbol(_Symbol);
   request.SetDirection(BRE_DIRECTION_BUY);
   request.SetLot(0.01);
   request.SetComment("test-open");
   return request;
  }

void TestMockExecutorOpenSuccess(void)
  {
   CMockTradeExecutor executor;
   CTradeContext context=BuildTestContext();
   SOpenPositionParams params;
   params.symbol=_Symbol;
   params.direction=BRE_DIRECTION_BUY;
   params.volume=0.01;
   params.stopLoss=0.0;
   params.takeProfit=0.0;

   CResult<CExecutionResult> result=executor.OpenPosition(context,params,BuildTestRequest());
   CTestAssert::True(result.IsOk(),"Mock open must succeed");
   CExecutionResult executionResult;
   CTestAssert::True(result.TryGetValue(executionResult),"Mock open result must exist");
   CTestAssert::True(executionResult.Success(),"Mock open execution must succeed");
   CTestAssert::EqualInt(1,executor.CallCount(),"Mock open call count must be 1");
  }

void TestMockExecutorRejection(void)
  {
   CMockTradeExecutor executor;
   executor.SetSimulateSuccess(false);
   SOpenPositionParams params;
   params.symbol=_Symbol;
   params.direction=BRE_DIRECTION_BUY;
   params.volume=0.01;

   CResult<CExecutionResult> result=executor.OpenPosition(BuildTestContext(),params,BuildTestRequest());
   CTestAssert::False(result.IsOk(),"Mock rejected open must fail");
   CTestAssert::EqualInt(BRE_ERR_EXEC_REJECTED,result.ErrorCode(),"Mock rejection error code must match");
  }

void TestResultMapperSuccess(void)
  {
   MqlTradeResult tradeResult;
   ZeroMemory(tradeResult);
   tradeResult.retcode=TRADE_RETCODE_DONE;
   tradeResult.deal=123456;
   tradeResult.order=654321;
   tradeResult.price=1900.0;
   tradeResult.volume=0.01;

   CExecutionResult mapped=CTradeResultMapper::Map(tradeResult,1,25);
   CTestAssert::True(mapped.Success(),"Mapped successful trade result must succeed");
   CTestAssert::EqualInt(BRE_EXECUTION_STATUS_FILLED,(int)mapped.Status(),"Mapped status must be FILLED");
   CTestAssert::False(mapped.Retryable(),"Successful result must not be retryable");
  }

void TestResultMapperRetryable(void)
  {
   MqlTradeResult tradeResult;
   ZeroMemory(tradeResult);
   tradeResult.retcode=TRADE_RETCODE_REQUOTE;

   CExecutionResult mapped=CTradeResultMapper::Map(tradeResult,2,40);
   CTestAssert::False(mapped.Success(),"Requote result must fail");
   CTestAssert::True(mapped.Retryable(),"Requote result must be retryable");
  }

void TestRequestBuilderOpenFields(void)
  {
   CExecutionPolicy policy;
   policy.SetSlippagePoints(15);
   CTradeRequestBuilder builder(policy);
   CTradeContext context=BuildTestContext();
   CTradeRequest request=BuildTestRequest();

   MqlTradeRequest tradeRequest;
   CTestAssert::True(builder.BuildOpenRequest(context,request,tradeRequest),"Open request build must succeed");
   CTestAssert::EqualInt(TRADE_ACTION_DEAL,(int)tradeRequest.action,"Open request action must be DEAL");
   CTestAssert::EqualInt(ORDER_TYPE_BUY,(int)tradeRequest.type,"Open request type must be BUY");
   CTestAssert::EqualInt(15,(int)tradeRequest.deviation,"Open request deviation must match policy");
   CTestAssert::EqualInt(202606001,(int)tradeRequest.magic,"Open request magic must match context");
   CTestAssert::EqualInt(ORDER_TIME_GTC,(int)tradeRequest.type_time,"Open request time type must be GTC");
  }

void TestDryRunExecutor(void)
  {
   CExecutionPolicy policy;
   policy.SetEnableExecution(true);
   policy.SetDryRunMode(true);
   CMt5TradeExecutor executor(policy,NULL);

   SOpenPositionParams params;
   params.symbol=_Symbol;
   params.direction=BRE_DIRECTION_BUY;
   params.volume=0.01;

   CResult<CExecutionResult> result=executor.OpenPosition(BuildTestContext(),params,BuildTestRequest());
   CTestAssert::True(result.IsOk(),"Dry run open must succeed without broker send");
   CExecutionResult executionResult;
   result.TryGetValue(executionResult);
   CTestAssert::EqualInt(BRE_EXECUTION_STATUS_DRY_RUN,(int)executionResult.Status(),"Dry run status must be DRY_RUN");
  }

void TestExecutionDisabled(void)
  {
   CExecutionPolicy policy;
   policy.SetEnableExecution(false);
   policy.SetDryRunMode(false);
   policy.SetSimulationMode(false);
   CMt5TradeExecutor executor(policy,NULL);

   SOpenPositionParams params;
   params.symbol=_Symbol;
   params.direction=BRE_DIRECTION_BUY;
   params.volume=0.01;

   CResult<CExecutionResult> result=executor.OpenPosition(BuildTestContext(),params,BuildTestRequest());
   CTestAssert::False(result.IsOk(),"Disabled execution must fail");
   CTestAssert::EqualInt(BRE_ERR_EXEC_DISABLED,result.ErrorCode(),"Disabled execution error code must match");
  }

void TestCloseBasketMock(void)
  {
   CMockTradeExecutor executor;
   ulong tickets[2]={100001,100002};
   SClosePositionParams params;
   params.ticket=tickets[0];
   params.volume=0.01;
   params.symbol=_Symbol;

   CResult<CExecutionResult> result=executor.CloseBasket(BuildTestContext(),tickets,2,BuildTestRequest());
   CTestAssert::True(result.IsOk(),"Mock close basket must succeed");
   CTestAssert::EqualInt(2,executor.CallCount(),"Mock close basket must call close twice");
  }

void OnStart()
  {
   CTestAssert::Reset();

   TestMockExecutorOpenSuccess();
   TestMockExecutorRejection();
   TestResultMapperSuccess();
   TestResultMapperRetryable();
   TestRequestBuilderOpenFields();
   TestDryRunExecutor();
   TestExecutionDisabled();
   TestCloseBasketMock();

   CTestAssert::Summary("TestExecution");
   if(!CTestAssert::AllPassed())
      Print("TestExecution FAILED");
  }
