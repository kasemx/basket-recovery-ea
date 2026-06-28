#property script_show_inputs
#property description "Sprint 7D: seed ACTIVE recovery basket for manual recovery candidate chart validation."

#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Application/Services/ExecutionDryRunTestBasketSeedService.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonLoader.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5Clock.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5UniqueIdGenerator.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Shared/Constants/StrategySchema.mqh>
#include <BasketRecovery/Shared/Types/Price.mqh>

input string InpPreferredSymbol = "BTCUSD";
input string InpBasketId         = "sprint7d-demo-btc-001";
input int    InpManualRecoveryCandidateExpirySeconds = 30;
input bool   InpAllowExistingSymbolPositions = false;

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
   return "UNKNOWN";
  }

string LoadDefaultRecoveryStrategyJson(void)
  {
   string relPath=BRE_STRATEGY_FILES_SUBDIR+BRE_STRATEGY_DEFAULT_ID+".strategy.json";
   int handle=FileOpen(relPath,FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle==INVALID_HANDLE)
      return CStrategyProfileTestFixture::MinimalValidJson();
   string content="";
   while(!FileIsEnding(handle))
     {
      if(content!="")
         content+="\n";
      content+=FileReadString(handle);
     }
   FileClose(handle);
   if(content=="")
      return CStrategyProfileTestFixture::MinimalValidJson();
   return content;
  }

CSignalDetails BuildRecoveryDueSignalDetails(const string symbol,const ENUM_BRE_TRADE_DIRECTION direction)
  {
   double bid=SymbolInfoDouble(symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
   if(bid<=0.0)
      bid=100000.0;
   if(ask<=bid)
      ask=bid+SymbolInfoDouble(symbol,SYMBOL_POINT);

   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   if(point<=0.0)
      point=0.01;

   double pipSize=point;
   double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize>0.0)
      pipSize=tickSize;

   double rangeHigh=ask+pipSize*100.0;
   double rangeLow=ask-point*500.0;
   double stopLoss=rangeLow-point*200.0;
   if(direction==BRE_DIRECTION_SELL)
     {
      rangeLow=bid;
      rangeHigh=bid+point*500.0;
      stopLoss=rangeHigh+point*200.0;
     }

   CSignalDetails details;
   details.SetHasDetails(true);
   details.SetRangeLow(CPrice(rangeLow));
   details.SetRangeHigh(CPrice(rangeHigh));
   details.SetStopLoss(CPrice(stopLoss));
   details.SetTp1(CPrice(ask+point*100.0));
   return details;
  }

void OnStart(void)
  {
   string reportRel="BasketRecovery/validation/sprint-7d-seed-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
     {
      Print("Failed to open seed report");
      return;
     }

   string symbol=ResolveTradingSymbol(InpPreferredSymbol);
   double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   if(minVolume<=0.0)
      minVolume=0.01;

   ENUM_ACCOUNT_TRADE_MODE tradeMode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   string accountModeLabel=(tradeMode==ACCOUNT_TRADE_MODE_DEMO ? "DEMO" : "REAL");
   string accountServer=AccountInfoString(ACCOUNT_SERVER);
   string serverClassification=ClassifyServer(accountServer,tradeMode);

   WriteLine(reportHandle,"seed_terminal_data_path="+TerminalInfoString(TERMINAL_DATA_PATH));
   WriteLine(reportHandle,"account_trade_mode="+accountModeLabel);
   WriteLine(reportHandle,"account_server="+accountServer);
   WriteLine(reportHandle,"server_classification="+serverClassification);
   WriteLine(reportHandle,"terminal_trade_allowed="+(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"true":"false"));
   WriteLine(reportHandle,"chart_trade_allowed="+(MQLInfoInteger(MQL_TRADE_ALLOWED)?"true":"false"));
   WriteLine(reportHandle,"symbol="+symbol);
   WriteLine(reportHandle,"min_volume="+DoubleToString(minVolume,8));
   WriteLine(reportHandle,"positions_before="+IntegerToString(PositionsTotal()));
   WriteLine(reportHandle,"orders_before="+IntegerToString(OrdersTotal()));
   WriteLine(reportHandle,"symbol_positions_before="+IntegerToString(CountSymbolPositions(symbol)));
   WriteLine(reportHandle,"symbol_orders_before="+IntegerToString(CountSymbolOrders(symbol)));
   WriteLine(reportHandle,"basket_id="+InpBasketId);
   WriteLine(reportHandle,"manual_recovery_candidate_expiry_seconds="+IntegerToString(InpManualRecoveryCandidateExpirySeconds));

   if(tradeMode!=ACCOUNT_TRADE_MODE_DEMO || serverClassification!="DEMO")
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Demo terminal/account required");
      FileClose(reportHandle);
      return;
     }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Algo/chart trading disabled");
      FileClose(reportHandle);
      return;
     }
   if(!InpAllowExistingSymbolPositions && (CountSymbolPositions(symbol)>0 || CountSymbolOrders(symbol)>0))
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Existing symbol positions or orders");
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

   string strategyJson=LoadDefaultRecoveryStrategyJson();
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

   CSignalDetails tuned=BuildRecoveryDueSignalDetails(symbol,BRE_DIRECTION_BUY);
   basket.ApplySignalDetails(tuned,CCommandId("cmd-seed-signal"),CEventId("evt-seed-signal"),CUtcTime(clock.Now()));
   basket.SetRecoveryActive(true);
   repository.Save(basket);
   repository.Load(basket.Id()).TryGetValue(basket);

   CFilePendingExecutionStore *pendingStore=new CFilePendingExecutionStore("BasketRecovery/pending_executions.dat");
   pendingStore.Clear();
   FileDelete("BasketRecovery/validation/sprint-7d-live-candidate.txt",FILE_COMMON);

   WriteLine(reportHandle,"basket_lifecycle=ACTIVE");
   WriteLine(reportHandle,"recovery_active=true");
   WriteLine(reportHandle,"strategy_profile_hash="+basket.StrategyProfileHash());
   WriteLine(reportHandle,"basket_version="+IntegerToString((int)basket.Version()));
   WriteLine(reportHandle,"signal_range_low="+DoubleToString(basket.SignalDetails().RangeLow().Value(),8));
   WriteLine(reportHandle,"signal_range_high="+DoubleToString(basket.SignalDetails().RangeHigh().Value(),8));
   WriteLine(reportHandle,"basket_stop_loss="+DoubleToString(basket.SignalDetails().StopLoss().Value(),8));
   WriteLine(reportHandle,"pending_execution_store=cleared");
   WriteLine(reportHandle,"seed_verification=OK");

   FileClose(reportHandle);
   delete pendingStore;
   delete seedService; delete repository; delete idGenerator; delete clock;
  }
