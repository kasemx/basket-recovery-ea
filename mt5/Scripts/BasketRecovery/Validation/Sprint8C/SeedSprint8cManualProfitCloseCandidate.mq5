#property script_show_inputs
#property description "Sprint 8C: seed ACTIVE basket with linked hedging position for manual profit-close validation."

#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Application/Services/ExecutionDryRunTestBasketSeedService.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5Clock.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5UniqueIdGenerator.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Shared/Types/Price.mqh>

input string InpPreferredSymbol = "BTCUSD";
input string InpBasketId         = "sprint8c-demo-btc-001";
input int    InpManualProfitCloseCandidateExpirySeconds = 60;
input bool   InpAllowExistingSymbolPositions = false;

const long SEED_MAGIC=202606001;

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

string MarginModeLabel(const long marginMode)
  {
   if(marginMode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return "RETAIL_HEDGING";
   if(marginMode==ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
      return "RETAIL_NETTING";
   if(marginMode==ACCOUNT_MARGIN_MODE_EXCHANGE)
      return "EXCHANGE";
   return "UNKNOWN";
  }

string LoadProfitCloseValidationStrategyJson(void)
  {
   return "{"
          "\"schema_version\":2,"
          "\"strategy_id\":\"sprint8c-profit-close\","
          "\"metadata\":{\"strategy_name\":\"Sprint 8C Profit Close Validation\"},"
          "\"execution_zone\":{\"source\":\"SIGNAL_RANGE\",\"expansion_mode\":\"SYMMETRIC\",\"above_entry_pips\":3,\"below_entry_pips\":3,\"expansion_disabled\":false},"
          "\"recovery_plan\":{\"algorithm\":\"CONSTANT\",\"constant_distance_pips\":0.2,\"constant_lot\":0.01,\"max_steps\":50,\"allow_during_profit_taking\":true,\"disable_after_break_even\":true,\"initial_position_count\":3,\"initial_lot_size\":0.01},"
          "\"risk_plan\":{\"target_risk_pct\":1.0,\"max_risk_pct\":1.2,\"risk_reduction_threshold_pct\":0.95,\"risk_reduction_mode\":\"WORST_ENTRY\",\"wait_details_timeout_minutes\":30,\"risk_eval_debounce_ms\":100},"
          "\"profit_distribution_plan\":{\"require_floating_profit_positive\":true,\"default_close_mode\":\"WORST_ENTRY_FIRST\",\"levels\":[{\"level_id\":\"M1\",\"level_index\":1,\"source\":\"FLOATING_PROFIT_MONEY\",\"trigger_type\":\"FLOATING_PROFIT_MONEY\",\"trigger_value\":0.01,\"close_percent\":50,\"close_mode\":\"WORST_ENTRY_FIRST\",\"partial_close\":true,\"enabled\":true}]},"
          "\"break_even_plan\":{\"rules\":[{\"rule_id\":\"BE1\",\"enabled\":true,\"priority\":1,\"run_once\":true,\"trigger\":{\"type\":\"REALIZED_PROFIT\",\"realized_profit_usd\":10},\"actions\":[{\"type\":\"MOVE_SL_TO_AVERAGE\",\"buffer_pips\":0.5}]}]},"
          "\"execution_policy\":{\"slippage_points\":10,\"max_trade_retries\":3,\"magic_number_base\":202606000,\"command_batch_size\":10,\"trade_request_batch_size\":5,\"rest_poll_interval_ms\":3000}"
          "}";
  }

double NormalizeVolume(const string symbol,const double volume)
  {
   double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(minVolume<=0.0) minVolume=0.01;
   if(step<=0.0) step=minVolume;
   double normalized=MathMax(volume,minVolume);
   normalized=MathFloor(normalized/step+0.0000001)*step;
   return normalized;
  }

bool FindLinkedPositionTicket(const string basketId,const string symbol,ulong &outTicket,double &outVolume)
  {
   string marker="BR:"+basketId+":";
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=symbol)
         continue;
      string comment=PositionGetString(POSITION_COMMENT);
      if(StringFind(comment,marker)!=0)
         continue;
      outTicket=ticket;
      outVolume=PositionGetDouble(POSITION_VOLUME);
      return true;
     }
   return false;
  }

bool OpenLinkedPosition(const string basketId,const string symbol,const double volume,ulong &outTicket)
  {
   string comment="BR:"+basketId+":INITIAL";
   MqlTradeRequest request={};
   MqlTradeResult result={};
   request.action=TRADE_ACTION_DEAL;
   request.symbol=symbol;
   request.volume=volume;
   request.type=ORDER_TYPE_BUY;
   request.magic=SEED_MAGIC;
   request.deviation=50;
   request.comment=comment;
   if(!OrderSend(request,result))
      return false;
   Sleep(1000);
   double foundVolume=0.0;
   if(!FindLinkedPositionTicket(basketId,symbol,outTicket,foundVolume))
     {
      if(result.deal>0 && HistoryDealSelect(result.deal))
         outTicket=(ulong)HistoryDealGetInteger(result.deal,DEAL_POSITION_ID);
      return outTicket>0;
     }
   return true;
  }

void OnStart(void)
  {
   string reportRel="BasketRecovery/validation/sprint-8c-seed-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      return;

   string symbol=ResolveTradingSymbol(InpPreferredSymbol);
   double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double volumeStep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(minVolume<=0.0) minVolume=0.01;
   if(volumeStep<=0.0) volumeStep=minVolume;

   double seedVolume=NormalizeVolume(symbol,minVolume*2.0);
   double partialCloseVolume=NormalizeVolume(symbol,seedVolume*0.5);
   bool partialClosePossible=(partialCloseVolume>0.0 && partialCloseVolume<seedVolume);

   ENUM_ACCOUNT_TRADE_MODE tradeMode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   long marginMode=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   string marginModeLabel=MarginModeLabel(marginMode);

   WriteLine(reportHandle,"account_trade_mode="+(tradeMode==ACCOUNT_TRADE_MODE_DEMO ? "DEMO" : "REAL"));
   WriteLine(reportHandle,"account_position_model="+marginModeLabel);
   WriteLine(reportHandle,"terminal_trade_allowed="+(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"true":"false"));
   WriteLine(reportHandle,"chart_trade_allowed="+(MQLInfoInteger(MQL_TRADE_ALLOWED)?"true":"false"));
   WriteLine(reportHandle,"symbol="+symbol);
   WriteLine(reportHandle,"min_volume="+DoubleToString(minVolume,8));
   WriteLine(reportHandle,"volume_step="+DoubleToString(volumeStep,8));
   WriteLine(reportHandle,"seed_volume="+DoubleToString(seedVolume,8));
   WriteLine(reportHandle,"partial_close_volume="+DoubleToString(partialCloseVolume,8));
   WriteLine(reportHandle,"partial_close_possible="+(partialClosePossible?"true":"false"));
   WriteLine(reportHandle,"positions_before="+IntegerToString(PositionsTotal()));
   WriteLine(reportHandle,"symbol_positions_before="+IntegerToString(CountSymbolPositions(symbol)));
   WriteLine(reportHandle,"basket_id="+InpBasketId);

   if(tradeMode!=ACCOUNT_TRADE_MODE_DEMO)
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Demo account required");
      FileClose(reportHandle);
      return;
     }
   if(marginMode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Retail hedging account required");
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
   if(!InpAllowExistingSymbolPositions && CountSymbolPositions(symbol)>0)
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Existing symbol positions");
      FileClose(reportHandle);
      return;
     }
   if(!partialClosePossible)
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Broker volume rules allow only full close");
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

   string strategyJson=LoadProfitCloseValidationStrategyJson();
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

   CSignalDetails details;
   details.SetHasDetails(true);
   double bid=SymbolInfoDouble(symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
   if(bid<=0.0) bid=100000.0;
   if(ask<=bid) ask=bid+SymbolInfoDouble(symbol,SYMBOL_POINT);
   details.SetRangeLow(CPrice(bid-SymbolInfoDouble(symbol,SYMBOL_POINT)*100.0));
   details.SetRangeHigh(CPrice(ask+SymbolInfoDouble(symbol,SYMBOL_POINT)*100.0));
   details.SetStopLoss(CPrice(bid-SymbolInfoDouble(symbol,SYMBOL_POINT)*200.0));
   details.SetTp1(CPrice(ask+SymbolInfoDouble(symbol,SYMBOL_POINT)*100.0));
   basket.ApplySignalDetails(details,CCommandId("cmd-seed-signal"),CEventId("evt-seed-signal"),CUtcTime(clock.Now()));
   repository.Save(basket);

   CFilePendingExecutionStore *pendingStore=new CFilePendingExecutionStore("BasketRecovery/pending_executions.dat");
   pendingStore.Clear();
   FileDelete("BasketRecovery/validation/sprint-8c-live-candidate.txt",FILE_COMMON);

   ulong positionTicket=0;
   if(!OpenLinkedPosition(InpBasketId,symbol,seedVolume,positionTicket))
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Could not open linked broker position");
      FileClose(reportHandle);
      delete pendingStore; delete seedService; delete repository; delete idGenerator; delete clock;
      return;
     }

   double linkedVolume=0.0;
   FindLinkedPositionTicket(InpBasketId,symbol,positionTicket,linkedVolume);

   WriteLine(reportHandle,"basket_lifecycle=ACTIVE");
   WriteLine(reportHandle,"strategy_profile_hash="+basket.StrategyProfileHash());
   WriteLine(reportHandle,"basket_version="+IntegerToString((int)basket.Version()));
   WriteLine(reportHandle,"profit_level_id=M1");
   WriteLine(reportHandle,"position_ticket="+IntegerToString((long)positionTicket));
   WriteLine(reportHandle,"original_position_volume="+DoubleToString(linkedVolume,8));
   WriteLine(reportHandle,"requested_close_volume="+DoubleToString(partialCloseVolume,8));
   WriteLine(reportHandle,"pending_execution_store=cleared");
   WriteLine(reportHandle,"positions_after="+IntegerToString(PositionsTotal()));
   WriteLine(reportHandle,"seed_verification=OK");
   FileClose(reportHandle);

   delete pendingStore;
   delete seedService; delete repository; delete idGenerator; delete clock;
  }
