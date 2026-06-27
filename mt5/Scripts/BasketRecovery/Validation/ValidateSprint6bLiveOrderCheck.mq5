#property script_show_inputs
#property description "Sprint 6B live terminal validation: real OrderCheck via manual dry-run route."

#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Market/Mt5MarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5OrderCheckGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5ExecutionDiagnostics.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5TradeExecutor.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionRequestRepository.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionJournal.mqh>
#include <BasketRecovery/Infrastructure/Events/InMemoryEventBus.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5Clock.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5UniqueIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Logging/FileLogger.mqh>
#include <BasketRecovery/Application/Execution/ExecuteTradeIntentUseCase.mqh>
#include <BasketRecovery/Application/Services/ExecutionDryRunManualCommandService.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>

input string InpPreferredSymbol        = "BTCUSD";
input string InpBasketId               = "sprint6b-demo-btc-001";
input string InpManualTriggerToken     = "";
input double InpManualLotSize          = 0.01;

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
      if(candidates[i]=="")
         continue;
      if(SymbolSelect(candidates[i],true) && SymbolInfoDouble(candidates[i],SYMBOL_BID)>0.0)
         return candidates[i];
     }
   return preferred;
  }

CBasketAggregate BuildActiveBasketForSymbol(const string basketIdValue,const string symbol)
  {
   CUtcTime boundAt(1000);
   CExecutionProfileConfig execution;
   execution.SetMagicNumberBase(202606001);
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                  CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                  execution,boundAt);
   CResult<CBasketAggregate> created=CBasketFactory::Create(CBasketId(basketIdValue),legacy,
                                                            "corr-"+basketIdValue,BRE_DIRECTION_BUY,symbol,
                                                            CSignalId("sig-"+basketIdValue),boundAt,
                                                            CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   return basket;
  }

void WriteValidationLine(const int handle,const string line)
  {
   if(handle!=INVALID_HANDLE)
      FileWriteString(handle,line+"\r\n");
   Print(line);
  }

string TradeExecutionStatusLabelLocal(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
  {
   switch(status)
     {
      case BRE_TRADE_EXEC_STATUS_ACCEPTED: return "ACCEPTED";
      case BRE_TRADE_EXEC_STATUS_REJECTED: return "REJECTED";
      case BRE_TRADE_EXEC_STATUS_FAILED: return "FAILED";
      case BRE_TRADE_EXEC_STATUS_TIMED_OUT: return "TIMED_OUT";
      case BRE_TRADE_EXEC_STATUS_UNKNOWN: return "UNKNOWN";
      default: return "OTHER";
     }
  }

void OnStart()
  {
   string symbol=ResolveTradingSymbol(InpPreferredSymbol);
   string triggerToken=InpManualTriggerToken;
   if(triggerToken=="")
      triggerToken="sprint6b-live-"+IntegerToString((int)GetTickCount());

   int positionsBefore=PositionsTotal();
   int ordersBefore=OrdersTotal();
   long accountLogin=AccountInfoInteger(ACCOUNT_LOGIN);

   FolderCreate("BasketRecovery\\validation",FILE_COMMON);
   string reportRel="BasketRecovery\\validation\\sprint-6b-live-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI);

   WriteValidationLine(reportHandle,"=== Sprint 6B Live OrderCheck Validation ===");
   WriteValidationLine(reportHandle,"timestamp="+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
   WriteValidationLine(reportHandle,"account_login="+IntegerToString((int)accountLogin));
   WriteValidationLine(reportHandle,"execution_mode=MT5_DRY_RUN enable_dry_run=true diagnostics=true");
   WriteValidationLine(reportHandle,"symbol="+symbol+" basket_id="+InpBasketId+" trigger_token="+triggerToken);
   WriteValidationLine(reportHandle,"trade_tab_before positions="+IntegerToString(positionsBefore)+
                                 " orders="+IntegerToString(ordersBefore));

   CFileLogger *logger=new CFileLogger();
   logger.Initialize("BasketRecovery/logs/basket_recovery.log",2);
   CMt5Clock *clock=new CMt5Clock();
   CMt5UniqueIdGenerator *idGenerator=new CMt5UniqueIdGenerator();
   CInMemoryEventBus *eventBus=new CInMemoryEventBus();
   CInMemoryBasketRepository *basketRepository=new CInMemoryBasketRepository();
   CMt5MarketDataProvider *marketDataProvider=new CMt5MarketDataProvider(clock);
   CMt5OrderCheckGateway *orderCheckGateway=new CMt5OrderCheckGateway();
   CMt5ExecutionDiagnostics *executionDiagnostics=new CMt5ExecutionDiagnostics(logger,true);
   CInMemoryExecutionRequestRepository *executionRequestRepository=new CInMemoryExecutionRequestRepository();
   CInMemoryExecutionJournal *executionJournal=new CInMemoryExecutionJournal(executionRequestRepository);
   CMt5TradeExecutor *mt5TradeExecutor=new CMt5TradeExecutor();
   CMarketSafetyConfig safetyConfig=CMarketSafetyConfig::Create(5000,500000,30000);

   mt5TradeExecutor.Configure(BRE_EXEC_RUNTIME_MT5_DRY_RUN,
                              basketRepository,
                              marketDataProvider,
                              orderCheckGateway,
                              executionDiagnostics,
                              safetyConfig,
                              true);

   CExecuteTradeIntentUseCase *executeUseCase=
      new CExecuteTradeIntentUseCase(basketRepository,mt5TradeExecutor,executionJournal,executionRequestRepository,clock);
   CExecutionDryRunManualCommandService *manualService=new CExecutionDryRunManualCommandService();
   manualService.Configure(BRE_EXEC_RUNTIME_MT5_DRY_RUN,true,false,BRE_PERSISTENCE_BASKET_SUBDIR,
                           executeUseCase,basketRepository,eventBus,idGenerator,logger);

   CBasketAggregate basket=BuildActiveBasketForSymbol(InpBasketId,symbol);
   CVoidResult seedResult=basketRepository.Save(basket);
   if(seedResult.IsFail())
     {
      WriteValidationLine(reportHandle,"basket_seed=FAILED message="+seedResult.ErrorMessage());
     }
   else
     {
      WriteValidationLine(reportHandle,"basket_seed=OK version="+IntegerToString((int)basket.Version())+
                                    " hash="+basket.StrategyProfileHash()+" direction=BUY lot="+DoubleToString(InpManualLotSize,4));
     }

   WriteValidationLine(reportHandle,"intent=OPEN_POSITION side=BUY sl=0 tp=0 price=market");

   CVoidResult dryRunResult=manualService.TryProcessManualDryRunOpen(InpBasketId,triggerToken,InpManualLotSize);
   WriteValidationLine(reportHandle,"manual_route="+(dryRunResult.IsOk()?"OK":"REJECTED")+
                                 " error_code="+IntegerToString(dryRunResult.ErrorCode())+
                                 " message="+dryRunResult.ErrorMessage());

   CTradeExecutionReceipt lastReceipt;
   bool hasReceipt=false;
   CResult<CTradeExecutionReceipt> receiptResult=executionRequestRepository.FindByIdempotencyKey("manual:dryrun:"+triggerToken);
   if(receiptResult.IsOk())
     {
      hasReceipt=receiptResult.TryGetValue(lastReceipt);
     }

   if(hasReceipt)
     {
      CTradeExecutionResult result=lastReceipt.Result();
      CTradeExecutionRequest request=lastReceipt.Request();
      WriteValidationLine(reportHandle,"mapped_status="+TradeExecutionStatusLabelLocal(result.Status()));
      WriteValidationLine(reportHandle,"is_dry_run="+(result.IsDryRun()?"true":"false"));
      WriteValidationLine(reportHandle,"order_check_invoked="+(result.OrderCheckInvoked()?"true":"false"));
      WriteValidationLine(reportHandle,"ordercheck_retcode="+IntegerToString((int)result.Mt5Retcode()));
      WriteValidationLine(reportHandle,"ordercheck_text="+result.Message());
      WriteValidationLine(reportHandle,"request_summary="+result.RequestSummary());
      WriteValidationLine(reportHandle,"translated_intent="+TradeExecutionIntentLabel(request.IntentType()));
      WriteValidationLine(reportHandle,"translated_volume="+DoubleToString(result.RequestedVolume(),4));
      WriteValidationLine(reportHandle,"translated_price="+DoubleToString(result.FillPrice(),(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS)));
      WriteValidationLine(reportHandle,"translated_sl="+DoubleToString(result.CheckedStopLoss(),(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS)));
      WriteValidationLine(reportHandle,"translated_tp="+DoubleToString(result.CheckedTakeProfit(),(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS)));
      WriteValidationLine(reportHandle,"ordersend_path=NOT_USED");
     }
   else if(dryRunResult.IsOk())
     {
      WriteValidationLine(reportHandle,"mapped_status=UNKNOWN (receipt missing)");
     }

   int logHandle=FileOpen("BasketRecovery\\logs\\basket_recovery.log",FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(logHandle==INVALID_HANDLE)
      logHandle=FileOpen("BasketRecovery\\logs\\basket_recovery.log",FILE_READ|FILE_TXT|FILE_ANSI);
   if(logHandle!=INVALID_HANDLE)
     {
      FileSeek(logHandle,0,SEEK_END);
      long logSize=FileTell(logHandle);
      long tailStart=logSize-8192;
      if(tailStart<0)
         tailStart=0;
      FileSeek(logHandle,(int)tailStart,SEEK_SET);
      WriteValidationLine(reportHandle,"--- execution_log_tail ---");
      while(!FileIsEnding(logHandle))
        {
         string logLine=FileReadString(logHandle);
         if(StringFind(logLine,"EXECUTION")>=0 || StringFind(logLine,"ManualDryRun")>=0 || StringFind(logLine,"Mt5DryRun")>=0)
            WriteValidationLine(reportHandle,logLine);
        }
      FileClose(logHandle);
     }

   int positionsAfter=PositionsTotal();
   int ordersAfter=OrdersTotal();
   WriteValidationLine(reportHandle,"trade_tab_after positions="+IntegerToString(positionsAfter)+
                                 " orders="+IntegerToString(ordersAfter));
   WriteValidationLine(reportHandle,"broker_mutation="+((positionsBefore==positionsAfter && ordersBefore==ordersAfter)?"NONE":"DETECTED"));

   delete manualService;
   delete executeUseCase;
   delete executionJournal;
   delete executionRequestRepository;
   delete mt5TradeExecutor;
   delete executionDiagnostics;
   delete orderCheckGateway;
   delete marketDataProvider;
   delete basketRepository;
   delete eventBus;
   delete idGenerator;
   delete clock;
   delete logger;

   if(reportHandle!=INVALID_HANDLE)
      FileClose(reportHandle);

   Print("Sprint 6B live validation complete | report=",reportRel);
  }
