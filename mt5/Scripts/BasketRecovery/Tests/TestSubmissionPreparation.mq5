#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Domain/Execution/BrokerCommentStamp.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRequestFingerprint.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionTransitionGate.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionCommentCollisionDetector.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationPolicy.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRestartService.mqh>
#include <BasketRecovery/Application/Execution/TradeTransactionRouter.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionDiagnostics.mqh>
#include <BasketRecovery/Application/Execution/InMemoryPendingExecutionEventBuffer.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Market/InMemoryMarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>
#include <BasketRecovery/Shared/DTOs/NormalizedTradeTransaction.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionCorrelationContext.mqh>

CBasketAggregate BuildActiveBasket(const string basketIdValue,const long version,const string profileHash)
  {
   CUtcTime boundAt(1000);
   string json=CStrategyProfileTestFixture::MinimalValidJson();
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(json,boundAt);
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,json,boundAt);
   CExecutionProfileConfig execution;
   execution.SetMagicNumberBase(202606001);
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                  CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                  execution,boundAt);
   CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId(basketIdValue),legacy,snapshot,
                                                                      "corr-"+basketIdValue,BRE_DIRECTION_BUY,"EURUSD",
                                                                      CSignalId("sig-"+basketIdValue),boundAt,
                                                                      CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   if(version>1)
      basket.SetVersionState(version,CCommandId("cmd-ver"),CEventId("evt-ver"),boundAt);
   return basket;
  }

CMarketQuote BuildFreshQuote(const string symbol,const double bid,const double ask,const int spreadPoints,const int ageMs)
  {
   return CMarketQuote::Create(symbol,bid,ask,spreadPoints,0.01,2,0.01,1.0,TimeCurrent(),ageMs,
                               BRE_TRADING_SESSION_OPEN,
                               CSymbolTradingConstraints::Create(20,10,0.01,100.0,0.01));
  }

void TestDeterministicCommentGeneration(void)
  {
   CBasketId basketId("basket-alpha");
   string first=CBrokerCommentStamp::Build("req-1","idem-1",basketId,BRE_EXEC_INTENT_OPEN_POSITION,31);
   string second=CBrokerCommentStamp::Build("req-1","idem-1",basketId,BRE_EXEC_INTENT_OPEN_POSITION,31);
   CTestAssert::EqualString(first,second,"Comment stamp must be deterministic");
   CTestAssert::True(StringFind(first,"BRE|")==0,"Comment must use BRE prefix");
  }

void TestCommentParseRoundtrip(void)
  {
   string comment=CBrokerCommentStamp::Build("req-rt","idem-rt",CBasketId("basket-rt"),BRE_EXEC_INTENT_REDUCE_POSITION,31);
   CBrokerCommentStampParsed parsed;
   CTestAssert::True(CBrokerCommentStamp::TryParse(comment,parsed),"Comment must parse");
   CTestAssert::EqualString("R",parsed.IntentCode(),"Intent code must roundtrip");
   CTestAssert::True(CBrokerCommentStamp::ValidateChecksum(comment),"Checksum must validate");
  }

void TestChecksumValidationRejectsTamperedComment(void)
  {
   string comment=CBrokerCommentStamp::Build("req-tamper","idem-tamper",CBasketId("b1"),BRE_EXEC_INTENT_OPEN_POSITION,31);
   string tampered=StringSubstr(comment,0,StringLen(comment)-1)+"Z";
   CTestAssert::False(CBrokerCommentStamp::ValidateChecksum(tampered),"Tampered checksum must fail");
  }

void TestMaximumCommentLengthBehavior(void)
  {
   string comment=CBrokerCommentStamp::Build("req-long","idem-long-key-value",
                                           CBasketId("basket-with-very-long-id-value"),
                                           BRE_EXEC_INTENT_OPEN_POSITION,20);
   CTestAssert::True(StringLen(comment)<=20,"Comment must respect max length");
   CTestAssert::True(CBrokerCommentStamp::ValidateChecksum(comment),"Truncated comment must keep valid checksum");
  }

void TestCollisionDetection(void)
  {
   CPendingExecutionRegistry registry;
   CPendingExecutionEntry first;
   first.SetExecutionRequestId("req-a");
   first.SetStatus(BRE_TRADE_EXEC_STATUS_QUEUED);
   first.SetBrokerComment("BRE|AAAA|b1|O|1234");
   first.SetCorrelationToken("AAAA");
   registry.Register(first);

   CTestAssert::True(CPendingExecutionCommentCollisionDetector::HasActiveCommentCollision(registry,
                                                                                          "BRE|AAAA|b1|O|1234",
                                                                                          "req-b"),
                     "Active comment collision must be detected");
  }

void TestBrokerSubmitGateBlocksPreparationSubmitted(void)
  {
   CTestAssert::False(CBrokerSubmissionTransitionGate::CanTransitionToSubmitted(BRE_TRADE_EXEC_STATUS_QUEUED,false),
                      "SUBMITTED requires broker acceptance flag");
   CTestAssert::False(CBrokerSubmissionTransitionGate::CanTransitionToSubmitted(BRE_TRADE_EXEC_STATUS_CREATED,true),
                      "SUBMITTED forbidden from CREATED");
   CTestAssert::True(CBrokerSubmissionTransitionGate::CanTransitionToSubmitted(BRE_TRADE_EXEC_STATUS_QUEUED,true),
                     "Future broker seam may submit from QUEUED only");
  }

void TestRegistryBlocksSubmittedWithoutBrokerSeam(void)
  {
   CPendingExecutionRegistry registry;
   CPendingExecutionEntry entry;
   entry.SetExecutionRequestId("req-sub");
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_QUEUED);
   registry.Register(entry);

   CPendingExecutionEntry updated;
   CTestAssert::False(registry.TryTransitionByRequestId("req-sub",BRE_TRADE_EXEC_STATUS_SUBMITTED,updated),
                      "Registry must block SUBMITTED without broker submit seam");
   CTestAssert::True(registry.TryBrokerSubmitTransition("req-sub",true,updated),
                     "Broker submit seam may transition to SUBMITTED");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_SUBMITTED,(int)updated.Status(),"Broker seam sets SUBMITTED");
  }

void TestValidRequestRemainsQueuedAfterPreparation(void)
  {
   CPendingExecutionRegistry registry;
   CInMemoryPendingExecutionStore store;
   CTestClock clock;
   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,0));
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));

   CSubmissionPreparationValidator validator(&marketData,CMarketSafetyConfig());
   CExecutionSubmissionPreparer preparer(CSubmissionPreparationPolicy::Default(),validator,&registry,&store,&clock);

   CBasketAggregate basket=BuildActiveBasket("prep-basket",1,"hash");
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("req-prep","idem-prep","corr",CBasketId("prep-basket"),1,
                                                                 "hash","EURUSD",BRE_EXEC_INTENT_OPEN_POSITION,
                                                                 BRE_DIRECTION_BUY,0,0.01,0.0,0.0,0.0,1000,
                                                                 CCommandId("cmd"),"test");

   CSubmissionPreparationResult result=preparer.Prepare(request,basket,202606001);
   CTestAssert::True(result.IsSuccess(),"Preparation must succeed for valid request");

   CPendingExecutionEntry entry;
   CTestAssert::True(registry.TryGetByExecutionRequestId("req-prep",entry),"Pending entry must exist");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_QUEUED,(int)entry.Status(),"Prepared request must remain QUEUED");
   CTestAssert::True(entry.HasPreparationMetadata(),"Preparation metadata must be stored");
  }

void TestDuplicateIdempotencyReturnsSameEnvelope(void)
  {
   CPendingExecutionRegistry registry;
   CInMemoryPendingExecutionStore store;
   CTestClock clock;
   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,0));
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
   CExecutionSubmissionPreparer preparer(CSubmissionPreparationPolicy::Default(),
                                         CSubmissionPreparationValidator(&marketData,CMarketSafetyConfig()),
                                         &registry,&store,&clock);
   CBasketAggregate basket=BuildActiveBasket("dup-basket",1,"hash");
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("req-dup","idem-dup","corr",CBasketId("dup-basket"),1,
                                                                 "hash","EURUSD",BRE_EXEC_INTENT_OPEN_POSITION,
                                                                 BRE_DIRECTION_BUY,0,0.01,0.0,0.0,0.0,1000,
                                                                 CCommandId("cmd"),"test");
   CSubmissionPreparationResult first=preparer.Prepare(request,basket,202606001);
   CSubmissionPreparationResult second=preparer.Prepare(request,basket,202606001);
   CTestAssert::True(first.IsSuccess() && second.IsSuccess(),"Both preparations must succeed");
   CTestAssert::True(second.ReusedExistingEnvelope(),"Duplicate idempotency must reuse envelope");
   CTestAssert::EqualString(first.Envelope().BrokerComment(),second.Envelope().BrokerComment(),
                            "Reused envelope comment must match");
  }

void TestExpiredEnvelopeRequiresRebuild(void)
  {
   CPendingExecutionRegistry registry;
   CInMemoryPendingExecutionStore store;
   CTestClock clock;
   clock.SetNow(1000);
   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,0));
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
   CSubmissionPreparationPolicy policy(31,5000,5);
   CExecutionSubmissionPreparer preparer(policy,
                                         CSubmissionPreparationValidator(&marketData,CMarketSafetyConfig()),
                                         &registry,&store,&clock);
   CBasketAggregate basket=BuildActiveBasket("exp-basket",1,"hash");
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("req-exp","idem-exp","corr",CBasketId("exp-basket"),1,
                                                                 "hash","EURUSD",BRE_EXEC_INTENT_OPEN_POSITION,
                                                                 BRE_DIRECTION_BUY,0,0.01,0.0,0.0,0.0,1000,
                                                                 CCommandId("cmd"),"test");
   CTestAssert::True(preparer.Prepare(request,basket,202606001).IsSuccess(),"Initial preparation must succeed");
   clock.SetNow(2000);
   CSubmissionPreparationResult rebuilt=preparer.Prepare(request,basket,202606001);
   CTestAssert::True(rebuilt.IsSuccess(),"Expired envelope must rebuild");
   CTestAssert::False(rebuilt.ReusedExistingEnvelope(),"Expired envelope must not reuse cached envelope");
  }

void TestStaleQuoteRejected(void)
  {
   CPendingExecutionRegistry registry;
   CInMemoryPendingExecutionStore store;
   CTestClock clock;
   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,6000));
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
   CExecutionSubmissionPreparer preparer(CSubmissionPreparationPolicy::Default(),
                                         CSubmissionPreparationValidator(&marketData,CMarketSafetyConfig()),
                                         &registry,&store,&clock);
   CBasketAggregate basket=BuildActiveBasket("stale-basket",1,"hash");
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("req-stale","idem-stale","corr",CBasketId("stale-basket"),1,
                                                                 "hash","EURUSD",BRE_EXEC_INTENT_OPEN_POSITION,
                                                                 BRE_DIRECTION_BUY,0,0.01,0.0,0.0,0.0,1000,
                                                                 CCommandId("cmd"),"test");
   CSubmissionPreparationResult result=preparer.Prepare(request,basket,202606001);
   CTestAssert::False(result.IsSuccess(),"Stale quote must reject preparation");
  }

void TestInvalidVolumeRejected(void)
  {
   CPendingExecutionRegistry registry;
   CInMemoryPendingExecutionStore store;
   CTestClock clock;
   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,0));
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
   CExecutionSubmissionPreparer preparer(CSubmissionPreparationPolicy::Default(),
                                         CSubmissionPreparationValidator(&marketData,CMarketSafetyConfig()),
                                         &registry,&store,&clock);
   CBasketAggregate basket=BuildActiveBasket("vol-basket",1,"hash");
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("req-vol","idem-vol","corr",CBasketId("vol-basket"),1,
                                                                 "hash","EURUSD",BRE_EXEC_INTENT_OPEN_POSITION,
                                                                 BRE_DIRECTION_BUY,0,0.0,0.0,0.0,0.0,1000,
                                                                 CCommandId("cmd"),"test");
   CSubmissionPreparationResult result=preparer.Prepare(request,basket,202606001);
   CTestAssert::False(result.IsSuccess(),"Invalid volume must reject preparation");
  }

void TestRestartPersistenceRestoresQueuedPrepared(void)
  {
   CInMemoryPendingExecutionStore store;
   CPendingExecutionRegistry registry;
   CPendingExecutionEntry entry;
   entry.SetExecutionRequestId("req-restart");
   entry.SetIdempotencyKey("idem-restart");
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_QUEUED);
   entry.SetBrokerComment("BRE|ABCD1234|restart|O|1A2B");
   entry.SetCorrelationToken("ABCD1234");
   entry.SetPreparedAtUtc(1000);
   entry.SetRequestedVolume(0.01);
   CBrokerSubmissionEnvelope envelope;
   envelope.SetExecutionRequestId("req-restart");
   envelope.SetIdempotencyKey("idem-restart");
   envelope.SetBrokerComment(entry.BrokerComment());
   envelope.SetPreparedAtUtc(1000);
   envelope.SetExpirationUtc(2000);
   store.SavePreparedState(entry,envelope);

   CPendingExecutionRegistry restoredRegistry;
   string warnings[];
   int count=CPendingExecutionRestartService::RestorePreparedEntries(&store,&restoredRegistry,warnings);
   CTestAssert::EqualInt(1,count,"Restart must restore one prepared queued entry");
   CPendingExecutionEntry restored;
   CTestAssert::True(restoredRegistry.TryGetByExecutionRequestId("req-restart",restored),"Restored entry must exist");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_QUEUED,(int)restored.Status(),"Restored entry must stay QUEUED");
  }

void TestTransactionCorrelationViaStampedComment(void)
  {
   CPendingExecutionRegistry registry;
   CPendingExecutionEntry entry;
   entry.SetExecutionRequestId("req-tx");
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_SUBMITTED);
   entry.SetSymbol("EURUSD");
   entry.SetRequestedVolume(0.01);
   CBrokerRequestCorrelation broker;
   broker.SetMagicNumber(202606001);
   broker.SetCommentToken(CBrokerCommentStamp::ShortCorrelationToken("req-tx","idem-tx"));
   entry.SetBrokerCorrelation(broker);
   entry.SetBrokerComment(CBrokerCommentStamp::Build("req-tx","idem-tx",CBasketId("b-tx"),BRE_EXEC_INTENT_OPEN_POSITION,31));
   registry.Register(entry);

   CNormalizedTradeTransaction tx;
   tx.SetSymbol("EURUSD");
   tx.SetComment(entry.BrokerComment());
   tx.SetVolume(0.01);
   CTradeTransactionCorrelationContext context=
      CTradeTransactionCorrelationContext::FromNormalized(tx,BRE_TRADE_TX_TYPE_ORDER_ADD,202606001);

   CInMemoryPendingExecutionEventBuffer events(8);
   CTradeTransactionRouter router(&registry,NULL,&events,NULL,NULL);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE routeResult=router.Route(context);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,(int)routeResult,
                         "Stamped comment must correlate via magic+symbol+comment path");
  }

void TestInvalidChecksumCommentIgnored(void)
  {
   CPendingExecutionRegistry registry;
   CPendingExecutionEntry entry;
   entry.SetExecutionRequestId("req-badcs");
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_QUEUED);
   entry.SetSymbol("EURUSD");
   CBrokerRequestCorrelation broker;
   broker.SetMagicNumber(202606001);
   broker.SetCommentToken("BADTOKEN");
   entry.SetBrokerCorrelation(broker);
   registry.Register(entry);

   string comment=CBrokerCommentStamp::Build("req-other","idem-other",CBasketId("b1"),BRE_EXEC_INTENT_OPEN_POSITION,31);
   comment=StringSubstr(comment,0,StringLen(comment)-1)+"Z";

   CNormalizedTradeTransaction tx;
   tx.SetSymbol("EURUSD");
   tx.SetComment(comment);
   CTradeTransactionCorrelationContext context=
      CTradeTransactionCorrelationContext::FromNormalized(tx,BRE_TRADE_TX_TYPE_DEAL_ADD,202606001);
   CTestAssert::EqualString("",context.CorrelationToken(),"Invalid checksum must not extract correlation token");

   CInMemoryPendingExecutionEventBuffer events(8);
   CTradeTransactionRouter router(&registry,NULL,&events,NULL,NULL);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_UNRELATED,(int)router.Route(context),
                         "Invalid checksum comment must remain unrelated");
  }

void OnStart(void)
  {
   CTestAssert::Reset();

   TestDeterministicCommentGeneration();
   TestCommentParseRoundtrip();
   TestChecksumValidationRejectsTamperedComment();
   TestMaximumCommentLengthBehavior();
   TestCollisionDetection();
   TestBrokerSubmitGateBlocksPreparationSubmitted();
   TestRegistryBlocksSubmittedWithoutBrokerSeam();
   TestValidRequestRemainsQueuedAfterPreparation();
   TestDuplicateIdempotencyReturnsSameEnvelope();
   TestExpiredEnvelopeRequiresRebuild();
   TestStaleQuoteRejected();
   TestInvalidVolumeRejected();
   TestRestartPersistenceRestoresQueuedPrepared();
   TestTransactionCorrelationViaStampedComment();
   TestInvalidChecksumCommentIgnored();

   CTestAssert::Summary("TestSubmissionPreparation");
   if(!CTestAssert::AllPassed())
      Print("TestSubmissionPreparation FAILED");
  }
