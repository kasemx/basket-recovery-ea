#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Domain/Execution/BrokerExecutionCommentFactory.mqh>
#include <BasketRecovery/Domain/Execution/BrokerCommentStamp.mqh>
#include <BasketRecovery/Domain/Execution/BrokerCommentCollisionDiagnostic.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionCommentCollisionDetector.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationPolicy.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5EnvelopeTradeRequestTranslator.mqh>
#include <BasketRecovery/Infrastructure/Market/InMemoryMarketDataProvider.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/BrokerRequestCorrelation.mqh>
#include <BasketRecovery/Domain/Market/AccountContextSnapshot.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Enums/TradeRole.mqh>
#include <BasketRecovery/Domain/Execution/SubmissionPreparationFailureReason.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Application/Execution/BasketTicketOwnershipHydrator.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotStatus.mqh>

const string SHARED_IDEMPOTENCY_KEY="profit-level-close:sprint8c-demo-xauusd-002:level:M1:q:0";
const string SPRINT8C_REQUEST_ID="profit-close-manual:564527484-5DF6-07FF";
const string SPRINT8C_FOREIGN_REQUEST_ID="profit-close-manual:505998484-7A85-16DA";
const ulong SPRINT8C_TICKET=1516503131;
const ulong SPRINT8C_FOREIGN_TICKET=1516350243;
const double SPRINT8C_POSITION_VOLUME=0.02;
const double SPRINT8C_CLOSE_VOLUME=0.01;

class CProfitClosePreparerTestHarness
  {
public:
   CPendingExecutionRegistry               registry;
   CInMemoryPendingExecutionStore          store;
   CTestClock                              clock;
   CInMemoryMarketDataProvider             marketData;
   CInMemorySnapshotStore                  snapshotStore;
   CExecutionSubmissionPreparer            preparer;

                     CProfitClosePreparerTestHarness(void)
     : snapshotStore(&clock),
       preparer(CSubmissionPreparationPolicy::Default(),
                CSubmissionPreparationValidator(&marketData,CMarketSafetyConfig()),
                &registry,&store,&clock)
     {
      marketData.SetQuote(BuildFreshQuote("XAUUSD"));
      marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
      preparer.ConfigureRiskReadModel(&snapshotStore,&marketData);
     }

   void              SeedLiveSellPosition(const CBasketAggregate &basket,
                                          const ulong ticket,
                                          const double volume)
     {
      CPositionSnapshotEntry entries[1];
      entries[0]=CPositionSnapshotEntry::Create(basket.Id(),
                                                ticket,
                                                202606001,
                                                "XAUUSD",
                                                BRE_DIRECTION_SELL,
                                                BRE_TRADE_ROLE_INITIAL,
                                                0,
                                                2650.0,
                                                2650.5,
                                                0.0,
                                                0.0,
                                                volume,
                                                0.0,
                                                0.0,
                                                0.0,
                                                TimeCurrent(),
                                                BRE_POSITION_SNAPSHOT_OPEN,
                                                "corr-"+IntegerToString((long)ticket));
      snapshotStore.ReplaceEntries(basket.Id(),entries,1);
     }
  };

CBasketAggregate BuildActiveBasket(const string basketIdValue)
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
                                                                      "corr-"+basketIdValue,BRE_DIRECTION_BUY,"XAUUSD",
                                                                      CSignalId("sig-"+basketIdValue),boundAt,
                                                                      CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   return basket;
  }

CMarketQuote BuildFreshQuote(const string symbol)
  {
   return CMarketQuote::Create(symbol,2650.0,2650.5,10,0.01,2,0.01,1.0,TimeCurrent(),10,
                               BRE_TRADING_SESSION_OPEN,
                               CSymbolTradingConstraints::Create(20,10,0.01,100.0,0.01));
  }

CTradeExecutionRequest BuildProfitCloseRequest(const string executionRequestId,
                                               const ulong ticket,
                                               const double volume,
                                               const CBasketAggregate &basket)
  {
   CTradeExecutionRequest request=CTradeExecutionRequest::Create(executionRequestId,
                                                                 SHARED_IDEMPOTENCY_KEY,
                                                                 "candidate-"+executionRequestId,
                                                                 basket.Id(),
                                                                 basket.Version(),
                                                                 "",
                                                                 "XAUUSD",
                                                                 BRE_EXEC_INTENT_CLOSE_POSITION,
                                                                 BRE_DIRECTION_BUY,
                                                                 ticket,
                                                                 volume,
                                                                 0.0,
                                                                 0.0,
                                                                 0.0,
                                                                 TimeCurrent(),
                                                                 CCommandId(""),
                                                                 CTradeRoleHelper::ToString(BRE_TRADE_ROLE_PROFIT_LEVEL_CLOSE));
   return request;
  }

CSubmissionPreparationResult PrepareProfitCloseRequest(CProfitClosePreparerTestHarness &harness,
                                                       CBasketAggregate &basket,
                                                       const string executionRequestId,
                                                       const ulong ticket,
                                                       const double closeVolume)
  {
   harness.SeedLiveSellPosition(basket,ticket,SPRINT8C_POSITION_VOLUME);
   CBasketTicketOwnershipHydrator::SyncMembershipFromSnapshotStore(basket,&harness.snapshotStore);
   CTradeExecutionRequest request=BuildProfitCloseRequest(executionRequestId,ticket,closeVolume,basket);
   return harness.preparer.PrepareForValidationSeed(request,basket,202606001);
  }

void SeedPending(CPendingExecutionRegistry &registry,
                 const string executionRequestId,
                 const string brokerComment,
                 const ENUM_BRE_TRADE_EXECUTION_STATUS status,
                 const ulong ticket=0)
  {
   CPendingExecutionEntry entry;
   entry.SetExecutionRequestId(executionRequestId);
   entry.SetStatus(status);
   entry.SetBrokerComment(brokerComment);
   entry.SetCorrelationToken(CBrokerExecutionCommentFactory::ExtractFingerprint(brokerComment));
   if(ticket>0)
     {
      CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
      broker.SetPositionTicket(ticket);
      entry.SetBrokerCorrelation(broker);
     }
   registry.Register(entry);
  }

void TestSameRequestIdSameTicketProducesSameComment(void)
  {
   string first=CBrokerExecutionCommentFactory::BuildProfitCloseComment("profit-close-manual:req-a",1516503131);
   string second=CBrokerExecutionCommentFactory::BuildProfitCloseComment("profit-close-manual:req-a",1516503131);
   CTestAssert::EqualString(first,second,"Same request id and ticket must produce same comment");
  }

void TestDifferentRequestIdsSameTicketProduceDifferentComments(void)
  {
   string first=CBrokerExecutionCommentFactory::BuildProfitCloseComment("profit-close-manual:req-a",1516503131);
   string second=CBrokerExecutionCommentFactory::BuildProfitCloseComment("profit-close-manual:req-b",1516503131);
   CTestAssert::False(first==second,"Different request ids must produce different comments");
  }

void TestDifferentTicketSameRequestIdProducesDifferentComment(void)
  {
   string first=CBrokerExecutionCommentFactory::BuildProfitCloseComment("profit-close-manual:req-a",1516503131);
   string second=CBrokerExecutionCommentFactory::BuildProfitCloseComment("profit-close-manual:req-a",1516350243);
   CTestAssert::False(first==second,"Different tickets must produce different comments");
  }

void TestCommentLengthWithinBrokerLimit(void)
  {
   string comment=CBrokerExecutionCommentFactory::BuildProfitCloseComment(SPRINT8C_REQUEST_ID,SPRINT8C_TICKET);
   CTestAssert::True(CBrokerExecutionCommentFactory::ValidateLength(comment),"Comment must fit conservative broker limit");
   CTestAssert::True(StringFind(comment,"BRE|PC|")==0,"Profit close comment must use BRE|PC prefix");
  }

void TestTerminalHistoricalPendingDoesNotBlock(void)
  {
   CPendingExecutionRegistry registry;
   string comment=CBrokerExecutionCommentFactory::BuildProfitCloseComment(SPRINT8C_REQUEST_ID,SPRINT8C_TICKET);
   SeedPending(registry,"profit-close-manual:old-filled",comment,BRE_TRADE_EXEC_STATUS_FILLED,1516350243);
   CBrokerCommentCollisionDiagnostic diagnostic;
   CTestAssert::False(CPendingExecutionCommentCollisionDetector::EvaluateCommentCollision(registry,
                                                                                          comment,
                                                                                          SPRINT8C_REQUEST_ID,
                                                                                          diagnostic),
                      "Completed historical pending must not block");
  }

void TestForeignPendingDifferentCommentDoesNotBlock(void)
  {
   CPendingExecutionRegistry registry;
   SeedPending(registry,"profit-close-manual:foreign-other",
               CBrokerExecutionCommentFactory::BuildProfitCloseComment("profit-close-manual:foreign-other",1516350243),
               BRE_TRADE_EXEC_STATUS_QUEUED,1516350243);
   string comment=CBrokerExecutionCommentFactory::BuildProfitCloseComment(SPRINT8C_REQUEST_ID,SPRINT8C_TICKET);
   CBrokerCommentCollisionDiagnostic diagnostic;
   CTestAssert::False(CPendingExecutionCommentCollisionDetector::EvaluateCommentCollision(registry,
                                                                                          comment,
                                                                                          SPRINT8C_REQUEST_ID,
                                                                                          diagnostic),
                      "Foreign pending with different comment must not block");
  }

void TestForeignPendingExactSameCommentBlocks(void)
  {
   CPendingExecutionRegistry registry;
   string comment=CBrokerExecutionCommentFactory::BuildProfitCloseComment(SPRINT8C_REQUEST_ID,SPRINT8C_TICKET);
   SeedPending(registry,"profit-close-manual:foreign-exact",comment,BRE_TRADE_EXEC_STATUS_QUEUED,1516350243);
   CBrokerCommentCollisionDiagnostic diagnostic;
   CTestAssert::True(CPendingExecutionCommentCollisionDetector::EvaluateCommentCollision(registry,
                                                                                         comment,
                                                                                         "profit-close-manual:other-request",
                                                                                         diagnostic),
                     "Foreign pending with exact same comment must block");
   CTestAssert::EqualString(CBrokerCommentCollisionDiagnostic::SourceUnresolvedForeignPending(),diagnostic.Source(),
                            "Collision source must identify foreign pending");
  }

void TestSameAuthorizedPendingDoesNotSelfBlock(void)
  {
   CPendingExecutionRegistry registry;
   string comment=CBrokerExecutionCommentFactory::BuildProfitCloseComment(SPRINT8C_REQUEST_ID,SPRINT8C_TICKET);
   SeedPending(registry,SPRINT8C_REQUEST_ID,comment,BRE_TRADE_EXEC_STATUS_QUEUED,SPRINT8C_TICKET);
   CBrokerCommentCollisionDiagnostic diagnostic;
   CTestAssert::False(CPendingExecutionCommentCollisionDetector::EvaluateCommentCollision(registry,
                                                                                          comment,
                                                                                          SPRINT8C_REQUEST_ID,
                                                                                          diagnostic),
                      "Same authorized pending must not self-block");
   CTestAssert::True(diagnostic.IsSameAuthorizedRequest(),"Same authorized request must be flagged");
  }

void TestEmptyCommentsDoNotFalsePositive(void)
  {
   CPendingExecutionRegistry registry;
   SeedPending(registry,"profit-close-manual:empty-comment","",BRE_TRADE_EXEC_STATUS_QUEUED,1516350243);
   string comment=CBrokerExecutionCommentFactory::BuildProfitCloseComment(SPRINT8C_REQUEST_ID,SPRINT8C_TICKET);
   CBrokerCommentCollisionDiagnostic diagnostic;
   CTestAssert::False(CPendingExecutionCommentCollisionDetector::EvaluateCommentCollision(registry,
                                                                                          comment,
                                                                                          SPRINT8C_REQUEST_ID,
                                                                                          diagnostic),
                      "Empty foreign comments must not false-positive collide");
   CTestAssert::False(CPendingExecutionCommentCollisionDetector::EvaluateCommentCollision(registry,
                                                                                          "",
                                                                                          SPRINT8C_REQUEST_ID,
                                                                                          diagnostic),
                      "Empty candidate comment must not collide");
  }

void TestSprint8cRequestPassesDespiteSharedIdempotencyStampCollision(void)
  {
   CProfitClosePreparerTestHarness harness;
   CBasketAggregate basket=BuildActiveBasket("sprint8c-comment-test");

   string legacyComment=CBrokerCommentStamp::Build(SPRINT8C_FOREIGN_REQUEST_ID,
                                                   SHARED_IDEMPOTENCY_KEY,
                                                   basket.Id(),
                                                   BRE_EXEC_INTENT_CLOSE_POSITION,
                                                   31);
   SeedPending(harness.registry,SPRINT8C_FOREIGN_REQUEST_ID,legacyComment,BRE_TRADE_EXEC_STATUS_QUEUED,SPRINT8C_FOREIGN_TICKET);

   CSubmissionPreparationResult result=PrepareProfitCloseRequest(harness,
                                                                 basket,
                                                                 SPRINT8C_REQUEST_ID,
                                                                 SPRINT8C_TICKET,
                                                                 SPRINT8C_CLOSE_VOLUME);
   string sprint8cFailureDetail=result.IsSuccess() ? "OK" : result.FailureMessage();
   string sprint8cMessage="Sprint 8C request must pass despite stale shared-idempotency pending | "+sprint8cFailureDetail;
   CTestAssert::True(result.IsSuccess(),sprint8cMessage);
   CTestAssert::EqualInt((int)BRE_EXEC_INTENT_CLOSE_POSITION,(int)result.Envelope().IntentType(),
                         "Prepared envelope must remain CLOSE_POSITION");
   CTestAssert::True(StringFind(result.Envelope().BrokerComment(),"BRE|PC|")==0,
                     "Prepared envelope must use profit-close comment factory");
   CTestAssert::EqualString("OK",harness.preparer.LastCommentSubmitDiagnostics().CollisionCheckResult(),
                            "Collision check must report OK");
  }

void TestCollisionFailureCausesZeroBrokerMutation(void)
  {
   CProfitClosePreparerTestHarness harness;
   CBasketAggregate basket=BuildActiveBasket("sprint8c-comment-test");
   const string newExecutionRequestId="profit-close-manual:TEST-NEW-REQUEST";
   const string foreignExecutionRequestId="profit-close-manual:TEST-FOREIGN-REQUEST";
   const string foreignAlternateExecutionRequestId="profit-close-manual:TEST-FOREIGN-REQUEST-ALT";

   string newComment=CBrokerExecutionCommentFactory::BuildProfitCloseComment(newExecutionRequestId,SPRINT8C_TICKET);
   string alternateComment=CBrokerExecutionCommentFactory::BuildProfitCloseComment(newExecutionRequestId,SPRINT8C_TICKET,1);
   SeedPending(harness.registry,foreignExecutionRequestId,newComment,BRE_TRADE_EXEC_STATUS_QUEUED,SPRINT8C_FOREIGN_TICKET);
   SeedPending(harness.registry,foreignAlternateExecutionRequestId,alternateComment,BRE_TRADE_EXEC_STATUS_QUEUED,SPRINT8C_FOREIGN_TICKET);

   harness.SeedLiveSellPosition(basket,SPRINT8C_TICKET,SPRINT8C_POSITION_VOLUME);
   CBasketTicketOwnershipHydrator::SyncMembershipFromSnapshotStore(basket,&harness.snapshotStore);
   CTradeExecutionRequest request=BuildProfitCloseRequest(newExecutionRequestId,
                                                           SPRINT8C_TICKET,
                                                           SPRINT8C_CLOSE_VOLUME,
                                                           basket);
   CSubmissionPreparationResult result=harness.preparer.PrepareForValidationSeed(request,basket,202606001);
   CTestAssert::False(result.IsSuccess(),"Exact comment collision must reject preparation");
   CTestAssert::EqualInt((int)BRE_PREP_FAIL_COMMENT_COLLISION,(int)result.FailureReason(),"Failure reason must be comment collision");
   CTestAssert::EqualString("BLOCKED",harness.preparer.LastCommentSubmitDiagnostics().CollisionCheckResult(),
                            "Collision diagnostics must report BLOCKED");
   CBrokerCommentCollisionDiagnostic collision=harness.preparer.LastCommentSubmitDiagnostics().CollisionDiagnostic();
   CTestAssert::EqualString(CBrokerCommentCollisionDiagnostic::SourceUnresolvedForeignPending(),collision.Source(),
                            "Collision source must identify foreign pending");
   CTestAssert::EqualString(foreignExecutionRequestId,collision.MatchedRequestId(),
                            "Collision must identify foreign execution request id");
   CTestAssert::False(collision.IsSameAuthorizedRequest(),"Foreign collision must not be same authorized request");
   CTestAssert::True(harness.preparer.LastCommentSubmitDiagnostics().ResolutionAttempted(),
                     "Collision resolution alternate attempt must be exercised before final block");
   bool hasCollisionPrefix=(StringFind(result.FailureMessage(),"Broker comment collision:")==0);
   CTestAssert::True(hasCollisionPrefix,"Failure message must include precise collision source");
   CPendingExecutionEntry foreignEntry;
   CTestAssert::True(harness.registry.TryGetByExecutionRequestId(foreignExecutionRequestId,foreignEntry),
                     "Foreign pending must remain untouched");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_QUEUED,(int)foreignEntry.Status(),
                         "Foreign pending status must remain QUEUED without broker mutation");
   CPendingExecutionEntry rejectedEntry;
   if(harness.registry.TryGetByExecutionRequestId(newExecutionRequestId,rejectedEntry))
     {
      CTestAssert::False(rejectedEntry.Status()==BRE_TRADE_EXEC_STATUS_SUBMITTED ||
                         rejectedEntry.Status()==BRE_TRADE_EXEC_STATUS_ACCEPTED,
                         "Rejected request must not reach broker-submitted status");
     }
  }

void TestSuccessPathProducesExpectedCloseRequest(void)
  {
   CProfitClosePreparerTestHarness harness;
   CBasketAggregate basket=BuildActiveBasket("sprint8c-comment-test");

   CSubmissionPreparationResult result=PrepareProfitCloseRequest(harness,
                                                                 basket,
                                                                 SPRINT8C_REQUEST_ID,
                                                                 SPRINT8C_TICKET,
                                                                 SPRINT8C_CLOSE_VOLUME);
   string successFailureDetail=result.IsSuccess() ? "OK" : result.FailureMessage();
   string successMessage="Preparation must succeed for unique profit-close request | "+successFailureDetail;
   CTestAssert::True(result.IsSuccess(),successMessage);
   CTestAssert::EqualInt((int)BRE_EXEC_INTENT_CLOSE_POSITION,(int)result.Envelope().IntentType(),
                         "Prepared envelope must remain CLOSE_POSITION");
   CTestAssert::True(StringFind(result.Envelope().BrokerComment(),"BRE|PC|")==0,
                     "Prepared comment uses BRE|PC|");

   CMt5EnvelopeTradeRequestTranslator translator;
   MqlTradeRequest mt5Request;
   string errorMessage="";
   CMarketQuote quote=BuildFreshQuote("XAUUSD");
   bool translated=translator.TryTranslateCloseMarketDeal(result.Envelope(),
                                                          quote.Bid(),
                                                          quote.Ask(),
                                                          20,
                                                          mt5Request,
                                                          errorMessage);
   string translateFailureMessage="Close request translation must succeed: "+errorMessage;
   CTestAssert::True(translated,translateFailureMessage);
   CTestAssert::EqualInt((int)TRADE_ACTION_DEAL,(int)mt5Request.action,"Action must be TRADE_ACTION_DEAL");
   CTestAssert::EqualInt((long)SPRINT8C_TICKET,(long)mt5Request.position,"Position must bind target ticket");
   CTestAssert::EqualString("XAUUSD",mt5Request.symbol,"Symbol must be XAUUSD");
   bool volumeOk=MathAbs(mt5Request.volume-0.01)<0.0000001;
   CTestAssert::True(volumeOk,"Volume must be 0.01");
   CTestAssert::EqualInt((int)ORDER_TYPE_BUY,(int)mt5Request.type,"Partial close of SELL uses BUY order type");
   bool fillingResolved=(mt5Request.type_filling==ORDER_FILLING_IOC ||
                          mt5Request.type_filling==ORDER_FILLING_FOK ||
                          mt5Request.type_filling==ORDER_FILLING_RETURN);
   CTestAssert::True(fillingResolved,"Filling mode must be resolved for market deal");
  }

void OnStart()
  {
   TestSameRequestIdSameTicketProducesSameComment();
   TestDifferentRequestIdsSameTicketProduceDifferentComments();
   TestDifferentTicketSameRequestIdProducesDifferentComment();
   TestCommentLengthWithinBrokerLimit();
   TestTerminalHistoricalPendingDoesNotBlock();
   TestForeignPendingDifferentCommentDoesNotBlock();
   TestForeignPendingExactSameCommentBlocks();
   TestSameAuthorizedPendingDoesNotSelfBlock();
   TestEmptyCommentsDoNotFalsePositive();
   TestSprint8cRequestPassesDespiteSharedIdempotencyStampCollision();
   TestCollisionFailureCausesZeroBrokerMutation();
   TestSuccessPathProducesExpectedCloseRequest();
   CTestAssert::Summary("TestBrokerExecutionCommentFactory");
  }
