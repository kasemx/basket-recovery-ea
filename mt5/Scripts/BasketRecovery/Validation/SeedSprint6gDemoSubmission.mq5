#property script_show_inputs
#property description "Sprint 6G: seed ACTIVE basket and prepared QUEUED OPEN_POSITION request for demo OrderSendAsync validation."

#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Application/Services/ExecutionDryRunTestBasketSeedService.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationPolicy.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Market/Mt5MarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5Clock.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5UniqueIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>
#include <BasketRecovery/Domain/Execution/SubmissionPreparationResult.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>

input string InpPreferredSymbol        = "BTCUSD";
input string InpBasketId               = "sprint6g-demo-btc-001";
input string InpExecutionRequestId     = "sprint6g-req-001";
input int    InpAuthorizationTokenExpirySeconds = 3600;
input int    InpEnvelopeValiditySeconds         = 3600;

string ResolveTradingSymbol(const string preferred)
  {
   string candidates[];
   ArrayResize(candidates,4);
   candidates[0]=preferred;
   candidates[1]=preferred+"m";
   candidates[2]=preferred+".";
   candidates[3]=_Symbol;
   for(int i=0;i<ArraySize(candidates);i++)
     {
      if(candidates[i]=="") continue;
      if(SymbolSelect(candidates[i],true) && SymbolInfoDouble(candidates[i],SYMBOL_BID)>0.0)
         return candidates[i];
     }
   return preferred;
  }

void WriteLine(const int handle,const string line)
  {
   if(handle!=INVALID_HANDLE)
      FileWriteString(handle,line+"\r\n");
   Print(line);
  }

int CountSymbolPositions(const string symbol)
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==symbol)
         count++;
     }
   return count;
  }

int CountSymbolOrders(const string symbol)
  {
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)==symbol)
         count++;
     }
   return count;
  }

string ClassifyServer(const string server,const ENUM_ACCOUNT_TRADE_MODE tradeMode)
  {
   if(tradeMode==ACCOUNT_TRADE_MODE_DEMO)
      return "DEMO";
   if(tradeMode==ACCOUNT_TRADE_MODE_REAL)
      return "REAL";
   string upper=server;
   StringToUpper(upper);
   if(StringFind(upper,"DEMO")>=0)
      return "DEMO";
   if(StringFind(upper,"LIVE")>=0)
      return "LIVE";
   return "UNKNOWN";
  }

void OnStart(void)
  {
   string reportRel="BasketRecovery/validation/sprint-6g-seed-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
     {
      Print("Failed to open report file");
      return;
     }

   string symbol=ResolveTradingSymbol(InpPreferredSymbol);
   double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   if(minVolume<=0.0)
      minVolume=0.01;

   ENUM_ACCOUNT_TRADE_MODE tradeMode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   string accountModeLabel="UNKNOWN";
   if(tradeMode==ACCOUNT_TRADE_MODE_DEMO)
      accountModeLabel="DEMO";
   else if(tradeMode==ACCOUNT_TRADE_MODE_REAL)
      accountModeLabel="REAL";

   string accountServer=AccountInfoString(ACCOUNT_SERVER);
   string serverClassification=ClassifyServer(accountServer,tradeMode);
   int positionsBefore=PositionsTotal();
   int ordersBefore=OrdersTotal();
   int symbolPositionsBefore=CountSymbolPositions(symbol);
   int symbolOrdersBefore=CountSymbolOrders(symbol);

   WriteLine(reportHandle,"seed_terminal_data_path="+TerminalInfoString(TERMINAL_DATA_PATH));
   WriteLine(reportHandle,"account_trade_mode="+accountModeLabel);
   WriteLine(reportHandle,"account_server="+accountServer);
   WriteLine(reportHandle,"server_classification="+serverClassification);
   WriteLine(reportHandle,"account_trade_allowed="+(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)?"true":"false"));
   WriteLine(reportHandle,"account_trade_expert="+(AccountInfoInteger(ACCOUNT_TRADE_EXPERT)?"true":"false"));
   WriteLine(reportHandle,"terminal_trade_allowed="+(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"true":"false"));
   WriteLine(reportHandle,"chart_trade_allowed="+(MQLInfoInteger(MQL_TRADE_ALLOWED)?"true":"false"));
   WriteLine(reportHandle,"symbol="+symbol);
   WriteLine(reportHandle,"min_volume="+DoubleToString(minVolume,8));
   WriteLine(reportHandle,"positions_before="+IntegerToString(positionsBefore));
   WriteLine(reportHandle,"orders_before="+IntegerToString(ordersBefore));
   WriteLine(reportHandle,"symbol_positions_before="+IntegerToString(symbolPositionsBefore));
   WriteLine(reportHandle,"symbol_orders_before="+IntegerToString(symbolOrdersBefore));
   WriteLine(reportHandle,"basket_id="+InpBasketId);
   WriteLine(reportHandle,"execution_request_id="+InpExecutionRequestId);

   if(tradeMode!=ACCOUNT_TRADE_MODE_DEMO)
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Account is not DEMO");
      FileClose(reportHandle);
      return;
     }
   if(serverClassification!="DEMO")
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Server classification is not DEMO");
      FileClose(reportHandle);
      return;
     }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Terminal Algo Trading disabled");
      FileClose(reportHandle);
      return;
     }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Chart EA trading permission disabled");
      FileClose(reportHandle);
      return;
     }
   if(symbolPositionsBefore>0 || symbolOrdersBefore>0)
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Existing positions or orders on test symbol");
      FileClose(reportHandle);
      return;
     }

   CMt5Clock *clock=new CMt5Clock();
   CMt5UniqueIdGenerator *idGenerator=new CMt5UniqueIdGenerator();
   CFileBasketRepository *repository=new CFileBasketRepository(BRE_PERSISTENCE_BASKET_SUBDIR);
   CExecutionDryRunTestBasketSeedService *seedService=new CExecutionDryRunTestBasketSeedService();
   if(!seedService.Initialize(repository,clock,idGenerator,"default"))
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Seed service init failed");
      FileClose(reportHandle);
      delete seedService; delete repository; delete idGenerator; delete clock;
      return;
     }

   string strategyJson=CStrategyProfileTestFixture::MinimalValidJson();
   CResult<CBasketAggregate> seedResult=seedService.SeedActiveBasket(CBasketId(InpBasketId),symbol,
                                                                    BRE_DIRECTION_BUY,strategyJson);
   if(seedResult.IsFail())
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason="+seedResult.ErrorMessage());
      FileClose(reportHandle);
      delete seedService; delete repository; delete idGenerator; delete clock;
      return;
     }

   CBasketAggregate basket;
   seedResult.TryGetValue(basket);
   WriteLine(reportHandle,"basket_lifecycle=ACTIVE");
   WriteLine(reportHandle,"strategy_profile_hash="+basket.StrategyProfileHash());
   WriteLine(reportHandle,"basket_version="+IntegerToString((int)basket.Version()));

   long magicNumber=202606001;
   CPendingExecutionRegistry *registry=new CPendingExecutionRegistry();
   CFilePendingExecutionStore *store=new CFilePendingExecutionStore("BasketRecovery/pending_executions.dat");
   store.Clear();
   CMt5MarketDataProvider *marketData=new CMt5MarketDataProvider(clock);
   CMarketSafetyConfig marketSafety=CMarketSafetyConfig::Create(5000,500000,30000);
   CSubmissionPreparationValidator *validator=new CSubmissionPreparationValidator(marketData,marketSafety);
   CSubmissionPreparationPolicy prepPolicy=CSubmissionPreparationPolicy(31,5000,InpEnvelopeValiditySeconds);
   CExecutionSubmissionPreparer *preparer=new CExecutionSubmissionPreparer(prepPolicy,
                                                                           *validator,registry,store,clock);

   string idempotencyKey="seed:prep:"+InpExecutionRequestId;
   CTradeExecutionRequest request=CTradeExecutionRequest::Create(InpExecutionRequestId,idempotencyKey,
                                                                   "corr-"+InpExecutionRequestId,
                                                                   CBasketId(InpBasketId),
                                                                   (long)basket.Version(),
                                                                   basket.StrategyProfileHash(),
                                                                   symbol,
                                                                   BRE_EXEC_INTENT_OPEN_POSITION,
                                                                   BRE_DIRECTION_BUY,0,minVolume,0.0,0.0,0.0,
                                                                   clock.Now(),
                                                                   CCommandId("cmd-seed-prep"),"seed");

   CSubmissionPreparationResult prep=preparer.PrepareForValidationSeed(request,basket,magicNumber);
   if(!prep.IsSuccess())
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason="+prep.FailureMessage());
      FileClose(reportHandle);
      delete preparer; delete validator; delete marketData; delete store; delete registry;
      delete seedService; delete repository; delete idGenerator; delete clock;
      return;
     }

   CPendingExecutionEntry entry;
   registry.TryGetByExecutionRequestId(InpExecutionRequestId,entry);
   WriteLine(reportHandle,"pending_status=QUEUED");
   WriteLine(reportHandle,"preparation_mode=validation_seed_bypass_account_precheck");
   WriteLine(reportHandle,"envelope_validity_seconds="+IntegerToString(InpEnvelopeValiditySeconds));
   WriteLine(reportHandle,"prepared="+(entry.IsPreparedQueued()?"true":"false"));
   WriteLine(reportHandle,"broker_comment="+prep.Envelope().BrokerComment());
   WriteLine(reportHandle,"correlation_token="+prep.Envelope().CorrelationToken());

   datetime expiry=clock.Now()+InpAuthorizationTokenExpirySeconds;
   string fingerprint=CExecutionAuthorizationToken::ComputeBindingFingerprint(entry.ExecutionRequestId(),
                                                                              entry.BasketId(),
                                                                              entry.Symbol(),
                                                                              entry.IntentType(),
                                                                              entry.RequestedVolume(),
                                                                              entry.ExpectedBasketVersion(),
                                                                              entry.StrategyProfileHash());
   string authToken=CExecutionAuthorizationToken::IssuePlaintextToken(fingerprint,expiry);
   WriteLine(reportHandle,"authorization_token="+authToken);
   WriteLine(reportHandle,"authorization_token_expiry="+IntegerToString((long)expiry));
   WriteLine(reportHandle,"seed_verification=OK");

   FileClose(reportHandle);
   delete preparer; delete validator; delete marketData; delete store; delete registry;
   delete seedService; delete repository; delete idGenerator; delete clock;
  }
