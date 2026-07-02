#property script_show_inputs
#property description "Sprint 8C: seed ACTIVE basket with linked hedging position for manual profit-close validation."

#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Application/Services/ExecutionDryRunTestBasketSeedService.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionReconciliationHydrator.mqh>
#include <BasketRecovery/Validation/Sprint8C/Sprint8cPendingExecutionPersistenceDiagnostics.mqh>
#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5Clock.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5UniqueIdGenerator.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Shared/Types/Price.mqh>
#include <BasketRecovery/Validation/Sprint8C/Sprint8cValidationSymbol.mqh>
#include <BasketRecovery/Validation/Sprint8C/Sprint8cValidationProfile.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/BrokerMarketDealFillingModeResolver.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

input string InpPreferredSymbol = "XAUUSD";
input string InpBasketId         = "sprint8c-demo-xauusd-002";
input string InpSeedDirection    = "BUY";
input int    InpManualProfitCloseCandidateExpirySeconds = 60;
input bool   InpAllowExistingSymbolPositions = false;
input bool   InpAllowChartSymbolFallback = false;

const long SEED_MAGIC=202606001;
const int  SEED_POSITION_LOOKUP_TIMEOUT_MS=1000;
const string SEED_SCRIPT_BUILD_MARKER="S8C_FILLING_IOC_V1";

struct SSeedLinkedPositionOpenTrace
  {
   MqlTradeRequest request;
   MqlTradeResult  trade_result;
   int             last_error_after_order_send;
   bool            order_send_returned_true;
   bool            find_linked_position_ok;
   ulong           deal_position_id_fallback;
   int             position_lookup_attempt_count;
   int             position_lookup_timeout_ms;
   string          position_lookup_result;
   string          open_failure_branch;
   string          filling_mode_resolution;
   string          filling_mode_failure_reason;
   ENUM_ORDER_TYPE_FILLING resolved_type_filling;
  };

string Sprint8cMarketSessionStatusLabel(const string symbol)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   datetime from=0;
   datetime to=0;
   if(!SymbolInfoSessionTrade(symbol,(ENUM_DAY_OF_WEEK)dt.day_of_week,0,from,to))
      return "SESSION_TRADE_LOOKUP_FAILED";
   datetime now=TimeCurrent();
   if(now<from || now>to)
      return "OUTSIDE_SESSION_HOURS";
   return "INSIDE_SESSION_HOURS";
  }

string Sprint8cSymbolFillingModeLabel(const string symbol)
  {
   return CBrokerMarketDealFillingModeResolver::FormatSymbolFillingModeMask(
      SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE));
  }

void WriteSeedOpenFailureDiagnostics(const int reportHandle,
                                     const string requestedSymbol,
                                     const string resolvedSymbol,
                                     const double requestedVolume,
                                     const double normalizedVolume,
                                     const SSeedLinkedPositionOpenTrace &trace)
  {
   WriteLine(reportHandle,"requested_symbol="+requestedSymbol);
   WriteLine(reportHandle,"resolved_symbol="+resolvedSymbol);
   WriteLine(reportHandle,"requested_volume="+DoubleToString(requestedVolume,8));
   WriteLine(reportHandle,"normalized_volume="+DoubleToString(normalizedVolume,8));
   WriteLine(reportHandle,"terminal_trade_allowed="+(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"true":"false"));
   WriteLine(reportHandle,"mql_trade_allowed="+(MQLInfoInteger(MQL_TRADE_ALLOWED)?"true":"false"));
   WriteLine(reportHandle,"script_trade_allowed_if_available="+(MQLInfoInteger(MQL_TRADE_ALLOWED)?"true":"false"));
   WriteLine(reportHandle,"symbol_trade_mode="+Sprint8cValidationSymbolTradeModeLabel(SymbolInfoInteger(resolvedSymbol,SYMBOL_TRADE_MODE)));
   WriteLine(reportHandle,"market_session_status="+Sprint8cMarketSessionStatusLabel(resolvedSymbol));
   WriteLine(reportHandle,"symbol_filling_mode="+Sprint8cSymbolFillingModeLabel(resolvedSymbol));
   WriteLine(reportHandle,"filling_mode_resolution="+trace.filling_mode_resolution);
   WriteLine(reportHandle,"resolved_type_filling="+CBrokerMarketDealFillingModeResolver::FormatOrderTypeFilling(
      trace.resolved_type_filling));
   WriteLine(reportHandle,"request_type_filling="+IntegerToString((int)trace.request.type_filling));
   WriteLine(reportHandle,"broker_retcode="+IntegerToString((int)trace.trade_result.retcode));
   WriteLine(reportHandle,"broker_result_text="+trace.trade_result.comment);
   WriteLine(reportHandle,"GetLastError="+IntegerToString(trace.last_error_after_order_send));
   WriteLine(reportHandle,"submitted_order_ticket="+IntegerToString((long)trace.trade_result.order));
   WriteLine(reportHandle,"submitted_deal_ticket="+IntegerToString((long)trace.trade_result.deal));
   WriteLine(reportHandle,"position_lookup_attempt_count="+IntegerToString(trace.position_lookup_attempt_count));
   WriteLine(reportHandle,"position_lookup_timeout_ms="+IntegerToString(trace.position_lookup_timeout_ms));
   WriteLine(reportHandle,"position_lookup_result="+trace.position_lookup_result);
   WriteLine(reportHandle,"open_failure_branch="+trace.open_failure_branch);
   WriteLine(reportHandle,"deal_position_id_fallback="+IntegerToString((long)trace.deal_position_id_fallback));
   WriteLine(reportHandle,"order_send_returned_true="+(trace.order_send_returned_true?"true":"false"));
   WriteLine(reportHandle,"find_linked_position_ok="+(trace.find_linked_position_ok?"true":"false"));
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
   return CSprint8cValidationProfile::BuildStrategyJson();
  }

void WriteValidationProfileMarkers(const int reportHandle)
  {
   CSprint8cValidationProfile::LogProfileMarkers();
   WriteLine(reportHandle,"validation_profile_version="+CSprint8cValidationProfile::ProfileVersionLabel());
   WriteLine(reportHandle,"validation_profile_id="+CSprint8cValidationProfile::ProfileId());
   WriteLine(reportHandle,"validation_profit_trigger_type="+CSprint8cValidationProfile::FloatingProfitTriggerTypeLabel());
   WriteLine(reportHandle,"validation_profit_trigger_value_usd="+DoubleToString(CSprint8cValidationProfile::FloatingProfitTriggerUsd(),2));
   WriteLine(reportHandle,"validation_require_floating_profit_positive=true");
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

bool OpenLinkedPosition(const string basketId,const string symbol,const double volume,
                        const ENUM_BRE_TRADE_DIRECTION seedDirection,
                        ulong &outTicket,SSeedLinkedPositionOpenTrace &trace)
  {
   trace.position_lookup_attempt_count=0;
   trace.position_lookup_timeout_ms=SEED_POSITION_LOOKUP_TIMEOUT_MS;
   trace.position_lookup_result="not_started";
   trace.deal_position_id_fallback=0;
   trace.find_linked_position_ok=false;
   trace.order_send_returned_true=false;
   trace.open_failure_branch="";
   trace.filling_mode_resolution="";
   trace.filling_mode_failure_reason="";
   trace.resolved_type_filling=ORDER_FILLING_RETURN;

   string comment="BR:"+basketId+":INITIAL";
   MqlTradeRequest request={};
   MqlTradeResult result={};
   request.action=TRADE_ACTION_DEAL;
   request.symbol=symbol;
   request.volume=volume;
   if(seedDirection==BRE_DIRECTION_SELL)
      request.type=ORDER_TYPE_SELL;
   else
      request.type=ORDER_TYPE_BUY;
   request.magic=SEED_MAGIC;
   request.deviation=50;
   request.comment=comment;

   ENUM_ORDER_TYPE_FILLING resolvedTypeFilling=ORDER_FILLING_RETURN;
   long symbolFillingMask=0;
   string fillingError="";
   if(!CBrokerMarketDealFillingModeResolver::TryResolveForSymbol(symbol,resolvedTypeFilling,symbolFillingMask,fillingError))
     {
      trace.filling_mode_resolution="FAILED";
      trace.filling_mode_failure_reason=fillingError;
      trace.resolved_type_filling=ORDER_FILLING_RETURN;
      trace.request=request;
      trace.open_failure_branch="filling_mode_resolution_failed";
      trace.position_lookup_result="skipped_filling_mode_unresolved";
      Print("filling_mode_resolution=FAILED failure_reason=",fillingError);
      return false;
     }

   request.type_filling=resolvedTypeFilling;
   trace.filling_mode_resolution="OK";
   trace.resolved_type_filling=resolvedTypeFilling;
   trace.request=request;
   Print("filling_mode_resolution=OK");
   Print("resolved_type_filling=",CBrokerMarketDealFillingModeResolver::FormatOrderTypeFilling(resolvedTypeFilling));
   Print("request_type_filling=",IntegerToString((int)request.type_filling));
   CBrokerMarketDealFillingModeResolver::LogMarketDealSubmissionDiagnostics(symbol,symbolFillingMask,
                                                                            resolvedTypeFilling,request);

   trace.order_send_returned_true=OrderSend(request,result);
   trace.request=request;
   trace.trade_result=result;
   trace.last_error_after_order_send=GetLastError();
   if(!trace.order_send_returned_true)
     {
      trace.open_failure_branch="order_send_returned_false";
      trace.position_lookup_result="skipped_order_send_failed";
      return false;
     }

   Sleep(SEED_POSITION_LOOKUP_TIMEOUT_MS);
   trace.position_lookup_attempt_count=1;
   double foundVolume=0.0;
   trace.find_linked_position_ok=FindLinkedPositionTicket(basketId,symbol,outTicket,foundVolume);
   if(!trace.find_linked_position_ok)
     {
      if(result.deal>0 && HistoryDealSelect(result.deal))
         trace.deal_position_id_fallback=(ulong)HistoryDealGetInteger(result.deal,DEAL_POSITION_ID);
      outTicket=trace.deal_position_id_fallback;
      if(outTicket>0)
         trace.open_failure_branch="deal_position_id_fallback_ok";
      else if(result.deal>0)
        {
         trace.open_failure_branch="deal_position_id_fallback_missing";
         trace.position_lookup_result="find_linked_failed_deal_position_id_zero";
        }
      else
        {
         trace.open_failure_branch="find_linked_failed_no_deal";
         trace.position_lookup_result="find_linked_failed_no_deal";
        }
      return outTicket>0;
     }

   trace.open_failure_branch="find_linked_position_ok";
   trace.position_lookup_result="find_linked_position_ok";
   return true;
  }

void OnStart(void)
  {
   Print("seed_script_build_marker=",SEED_SCRIPT_BUILD_MARKER);

   string reportRel="BasketRecovery/validation/sprint-8c-seed-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      return;

   WriteLine(reportHandle,"seed_script_build_marker="+SEED_SCRIPT_BUILD_MARKER);
   WriteValidationProfileMarkers(reportHandle);

   string requestedSymbol=InpPreferredSymbol;
   string symbol=Sprint8cResolveValidationTradingSymbol(requestedSymbol,InpAllowChartSymbolFallback);
   double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double volumeStep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(minVolume<=0.0) minVolume=0.01;
   if(volumeStep<=0.0) volumeStep=minVolume;

   double seedVolume=0.0;
   double partialCloseVolume=0.0;
   bool partialClosePossible=Sprint8cAssessPartialCloseVolumePlan(symbol,seedVolume,partialCloseVolume);
   bool symbolAvailable=Sprint8cValidationSymbolIsQuotable(symbol);
   double rawRequestedVolume=minVolume*2.0;

   ENUM_ACCOUNT_TRADE_MODE tradeMode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   long marginMode=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   string marginModeLabel=MarginModeLabel(marginMode);

   WriteLine(reportHandle,"account_trade_mode="+(tradeMode==ACCOUNT_TRADE_MODE_DEMO ? "DEMO" : "REAL"));
   WriteLine(reportHandle,"account_position_model="+marginModeLabel);
   WriteLine(reportHandle,"terminal_trade_allowed="+(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"true":"false"));
   WriteLine(reportHandle,"chart_trade_allowed="+(MQLInfoInteger(MQL_TRADE_ALLOWED)?"true":"false"));
   WriteLine(reportHandle,"validation_symbol_requested="+requestedSymbol);
   WriteLine(reportHandle,"symbol="+symbol);
   WriteLine(reportHandle,"symbol_available="+(symbolAvailable?"true":"false"));
   WriteLine(reportHandle,"min_volume="+DoubleToString(minVolume,8));
   WriteLine(reportHandle,"volume_step="+DoubleToString(volumeStep,8));
   WriteLine(reportHandle,"seed_volume="+DoubleToString(seedVolume,8));
   WriteLine(reportHandle,"partial_close_volume="+DoubleToString(partialCloseVolume,8));
   WriteLine(reportHandle,"partial_close_possible="+(partialClosePossible?"true":"false"));
   WriteLine(reportHandle,"positions_before="+IntegerToString(PositionsTotal()));
   WriteLine(reportHandle,"symbol_positions_before="+IntegerToString(CountSymbolPositions(symbol)));
   WriteLine(reportHandle,"basket_id="+InpBasketId);

   ENUM_BRE_TRADE_DIRECTION seedDirection=BRE_DIRECTION_NONE;
   if(!CSprint8cValidationProfile::TryParseSeedDirection(InpSeedDirection,seedDirection))
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=InpSeedDirection must be BUY or SELL");
      FileClose(reportHandle);
      return;
     }
   WriteLine(reportHandle,"seed_direction="+CSprint8cValidationProfile::SeedDirectionLabel(seedDirection));

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
   if(!symbolAvailable)
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Validation symbol is not available or not quotable");
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
                                                                    seedDirection,strategyJson);
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

   CFilePendingExecutionStore *pendingStore=new CFilePendingExecutionStore(CSprint8cPendingExecutionPersistenceDiagnostics::DefaultStoreRelativePath());
   pendingStore.RestoreFromDisk();
   int pendingBeforeClear=pendingStore.RestoreEntries(CPendingExecutionEntry entriesBefore[]);
   int deletedCount=pendingBeforeClear;
   CVoidResult clearResult=pendingStore.Clear();
   CFilePendingExecutionStore *verifyStore=new CFilePendingExecutionStore(CSprint8cPendingExecutionPersistenceDiagnostics::DefaultStoreRelativePath());
   verifyStore.RestoreFromDisk();
   CPendingExecutionEntry verifyEntries[];
   int verifyCount=verifyStore.RestoreEntries(verifyEntries);
   int unresolvedAfterClear=CSprint8cPendingExecutionPersistenceDiagnostics::CountUnresolvedForBasketOnDisk(CBasketId(InpBasketId),*verifyStore);
   WriteLine(reportHandle,"seed_pending_clear_target_path="+CSprint8cPendingExecutionPersistenceDiagnostics::DefaultStoreRelativePath());
   WriteLine(reportHandle,"seed_pending_clear_deleted_count="+IntegerToString(deletedCount));
   WriteLine(reportHandle,"seed_pending_clear_persisted_result="+(clearResult.IsOk()?"OK":"FAIL"));
   WriteLine(reportHandle,"seed_pending_verify_reload_count="+IntegerToString(verifyCount));
   WriteLine(reportHandle,"seed_pending_verify_unresolved_count="+IntegerToString(unresolvedAfterClear));
   if(!clearResult.IsOk() || verifyCount!=0 || unresolvedAfterClear!=0)
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Pending execution store was not cleared on disk");
      FileClose(reportHandle);
      delete verifyStore; delete pendingStore; delete seedService; delete repository; delete idGenerator; delete clock;
      return;
     }
   FileDelete("BasketRecovery/validation/sprint-8c-live-candidate.txt",FILE_COMMON);

   ulong positionTicket=0;
   SSeedLinkedPositionOpenTrace openTrace;
   if(!OpenLinkedPosition(InpBasketId,symbol,seedVolume,seedDirection,positionTicket,openTrace))
     {
      WriteLine(reportHandle,"seed_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Could not open linked broker position");
      WriteSeedOpenFailureDiagnostics(reportHandle,requestedSymbol,symbol,rawRequestedVolume,seedVolume,openTrace);
      FileClose(reportHandle);
      delete verifyStore; delete pendingStore; delete seedService; delete repository; delete idGenerator; delete clock;
      return;
     }

   delete verifyStore;
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
