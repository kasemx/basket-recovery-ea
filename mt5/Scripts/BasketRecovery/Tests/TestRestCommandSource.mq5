#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/MockRestHttpClient.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestClient.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestClientConfig.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestCommandSource.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestCommandJsonParser.mqh>
#include <BasketRecovery/Application/Services/CommandIngestionService.mqh>
#include <BasketRecovery/Infrastructure/Commands/InMemoryCommandQueue.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

string BuildCreateBasketJson(const string commandId,const string idempotencyKey)
  {
   return "{"
          +"\"commands\":[{"
          +"\"command_id\":\""+commandId+"\","
          +"\"command_type\":\"CreateBasketCommand\","
          +"\"idempotency_key\":\""+idempotencyKey+"\","
          +"\"basket_id\":\"\","
          +"\"correlation_key\":\"corr-rest-001\","
          +"\"symbol\":\"XAUUSD\","
          +"\"direction\":\"BUY\","
          +"\"signal_id\":\"sig-rest-001\","
          +"\"priority\":30,"
          +"\"source\":\"REST\","
          +"\"enqueued_at\":946684800"
          +"}],"
          +"\"cursor\":\"cursor-001\""
          +"}";
  }

void TestFetchAndEnqueue(void)
  {
   CMockRestHttpClient *mockHttpClient=new CMockRestHttpClient();
   mockHttpClient.SetNextGetResponse(BuildCreateBasketJson("cmd-rest-001","idem-rest-001"));
   CRestClient *restClient=new CRestClient(mockHttpClient,true);

   CRestClientConfig config;
   config.SetBaseUrl("http://127.0.0.1:8080");
   config.SetAccountId(12345678);

   CRestCommandSource *commandSource=new CRestCommandSource(restClient,config,true);
   CInMemoryCommandQueue commandQueue;
   CCommandIngestionService ingestionService(commandSource,&commandQueue,NULL);

   CTestAssert::True(ingestionService.PollAndEnqueue().IsOk(),"Poll and enqueue must succeed");
   CTestAssert::EqualInt(1,commandQueue.PendingCount(),"One command must be queued");
   CTestAssert::EqualInt(1,ingestionService.LastEnqueuedCount(),"One command must be enqueued");
   CTestAssert::EqualInt(1,ingestionService.LastAckCount(),"One command must be acked");
   CTestAssert::True(StringFind(mockHttpClient.LastGetUrl(),"/api/v1/commands/pending")>=0,"GET must target pending endpoint");
   CTestAssert::True(StringFind(mockHttpClient.LastPostUrl(),"/api/v1/commands/cmd-rest-001/ack")>=0,"POST must target ack endpoint");
  }

void TestDuplicateIdempotency(void)
  {
   CMockRestHttpClient *mockHttpClient=new CMockRestHttpClient();
   mockHttpClient.SetNextGetResponse(BuildCreateBasketJson("cmd-rest-dup-001","idem-rest-dup"));
   mockHttpClient.SetNextGetResponse(BuildCreateBasketJson("cmd-rest-dup-002","idem-rest-dup"));

   CRestClient *restClient=new CRestClient(mockHttpClient,true);
   CRestClientConfig config;
   config.SetBaseUrl("http://127.0.0.1:8080");
   config.SetAccountId(12345678);

   CRestCommandSource *commandSource=new CRestCommandSource(restClient,config,true);
   CInMemoryCommandQueue commandQueue;
   CCommandIngestionService ingestionService(commandSource,&commandQueue,NULL);

   CTestAssert::True(ingestionService.PollAndEnqueue().IsOk(),"First poll must succeed");
   CTestAssert::EqualInt(1,commandQueue.PendingCount(),"First poll must enqueue one command");

   CTestAssert::True(ingestionService.PollAndEnqueue().IsOk(),"Second poll must succeed");
   CTestAssert::EqualInt(1,commandQueue.PendingCount(),"Duplicate idempotency key must not enqueue twice");
   CTestAssert::EqualInt(1,ingestionService.LastDuplicateCount(),"Second poll must count duplicate");
  }

void TestInvalidCommandRejected(void)
  {
   CRestCommandJsonParser parser;
   ICommand *commands[];
   int rejectedCount=0;
   string cursor="";
   string invalidJson="{"
                      +"\"commands\":[{"
                      +"\"command_id\":\"cmd-invalid\","
                      +"\"command_type\":\"CreateBasketCommand\""
                      +"}]"
                      +"}";

   CResult<int> parseResult=parser.ParsePendingResponse(invalidJson,commands,rejectedCount,cursor);
   CTestAssert::False(parseResult.IsOk(),"Invalid command payload must be rejected");
   CTestAssert::EqualInt(BRE_ERR_REST_VALIDATION_FAILED,parseResult.ErrorCode(),"Invalid payload must return validation error");
   CTestAssert::EqualInt(1,rejectedCount,"Invalid payload must increment rejected count");
  }

void TestNoContentResponse(void)
  {
   CMockRestHttpClient *mockHttpClient=new CMockRestHttpClient();
   mockHttpClient.SetNextGetResponse("",204);
   CRestClient *restClient=new CRestClient(mockHttpClient,true);

   CRestClientConfig config;
   config.SetBaseUrl("http://127.0.0.1:8080");
   config.SetAccountId(12345678);

   CRestCommandSource *commandSource=new CRestCommandSource(restClient,config,true);
   ICommand *commands[];
   CResult<int> fetchResult=commandSource.FetchPending(commands);
   CTestAssert::True(fetchResult.IsOk(),"No content response must succeed");
   int count=0;
   CTestAssert::True(fetchResult.TryGetValue(count),"No content count must exist");
   CTestAssert::EqualInt(0,count,"No content must return zero commands");
   delete commandSource;
  }

void TestCircuitBreakerOpens(void)
  {
   CMockRestHttpClient *mockHttpClient=new CMockRestHttpClient();
   mockHttpClient.FailNextGet();

   CRestClient *restClient=new CRestClient(mockHttpClient,true);
   CRestClientConfig config;
   config.SetBaseUrl("http://127.0.0.1:8080");
   config.SetAccountId(12345678);

   CRestCommandSource *commandSource=new CRestCommandSource(restClient,config,true);
   ICommand *commands[];
   for(int i=0;i<5;i++)
      commandSource.FetchPending(commands);

   CTestAssert::False(commandSource.IsAvailable(),"Circuit breaker must open after repeated failures");
   delete commandSource;
  }

void OnStart()
  {
   CTestAssert::Reset();

   TestFetchAndEnqueue();
   TestDuplicateIdempotency();
   TestInvalidCommandRejected();
   TestNoContentResponse();
   TestCircuitBreakerOpens();

   CTestAssert::Summary("TestRestCommandSource");
   if(!CTestAssert::AllPassed())
      Print("TestRestCommandSource FAILED");
  }
