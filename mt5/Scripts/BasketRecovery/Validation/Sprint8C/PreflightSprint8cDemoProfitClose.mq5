#property script_show_inputs
#property description "Sprint 8C: DEMO hedging preflight for manual profit-close validation (no seed, no submit, read-only pending diagnostics)."

#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionQuery.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Application/Execution/ExecutionReconciliationResolver.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/Mt5BrokerPositionReader.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionReconciliationHydrator.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/Mt5BrokerExecutionHistoryReader.mqh>

input string InpPreferredSymbol = "BTCUSD";

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

string ServerClassification(const string server,const ENUM_ACCOUNT_TRADE_MODE tradeMode)
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

string CorrelationEvidenceCategory(const CPendingExecutionEntry &entry)
  {
   CBrokerRequestCorrelation correlation=entry.BrokerCorrelation();
   if(correlation.HasBrokerDealId())
      return "deal_id";
   if(correlation.HasBrokerOrderId())
      return "order_id";
   if(correlation.HasPositionTicket())
      return "position_ticket";
   if(entry.CorrelationToken()!="")
      return "correlation_token";
   if(entry.BrokerComment()!="")
      return "broker_comment";
   return "symbol_only";
  }

bool ProposedStateRemainsUnresolved(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
  {
   return CPendingExecutionQuery::IsUnresolvedStatus(status);
  }

void AnalyzePendingExecutions(const int reportHandle,
                              CMt5BrokerPositionReader *positionReader,
                              CMt5BrokerExecutionHistoryReader *historyReader,
                              int &unresolvedBeforeOut,
                              int &unresolvedAfterOut,
                              string &blockingIdsOut)
  {
   unresolvedBeforeOut=0;
   unresolvedAfterOut=0;
   blockingIdsOut="";

   CFilePendingExecutionStore *store=new CFilePendingExecutionStore("BasketRecovery/pending_executions.dat");
   store.RestoreFromDisk();
   CPendingExecutionEntry entries[];
   int total=store.RestoreEntries(entries);
   datetime nowUtc=TimeCurrent();

   for(int i=0;i<total;i++)
     {
      CPendingExecutionEntry entry=entries[i];
      CPendingExecutionReconciliationHydrator::TryHydrate(entry,store);
      if(!CPendingExecutionQuery::IsUnresolvedStatus(entry.Status()))
         continue;

      unresolvedBeforeOut++;

      if(entry.Status()==BRE_TRADE_EXEC_STATUS_QUEUED || entry.Status()==BRE_TRADE_EXEC_STATUS_CREATED)
        {
         WriteLine(reportHandle,"pending_execution["+IntegerToString(unresolvedBeforeOut)+"]="
                               +"execution_request_id="+entry.ExecutionRequestId()
                               +" | persisted_status="+TradeExecutionStatusLabel(entry.Status())
                               +" | correlation_evidence="+CorrelationEvidenceCategory(entry)
                               +" | current_open_state=startup_no_auto_reconcile"
                               +" | history_correlation_state=not_queried"
                               +" | final_reconciliation_state=QUEUED"
                               +" | confidence=none"
                               +" | startup_mutation_permitted=false"
                               +" | remains_unresolved=true");
         unresolvedAfterOut++;
         if(blockingIdsOut!="")
            blockingIdsOut+=",";
         blockingIdsOut+=entry.ExecutionRequestId();
         continue;
        }

      double matchedVolume=0.0;
      CExecutionReconciliationReport report;
      ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
         CExecutionReconciliationResolver::ResolveWithReport(entry,positionReader,matchedVolume,historyReader,nowUtc,report);
      bool stillUnresolved=ProposedStateRemainsUnresolved(resolved);

      WriteLine(reportHandle,"pending_execution["+IntegerToString(unresolvedBeforeOut)+"]="
                            +"execution_request_id="+entry.ExecutionRequestId()
                            +" | basket_id="+entry.BasketId().Value()
                            +" | persisted_status="+TradeExecutionStatusLabel(entry.Status())
                            +" | correlation_evidence="+CorrelationEvidenceCategory(entry)
                            +" | current_open_state="+report.CurrentOpenState()
                            +" | history_correlation_state="+report.HistoryCorrelationState()
                            +" | final_reconciliation_state="+TradeExecutionStatusLabel(resolved)
                            +" | confidence="+report.Confidence()
                            +" | startup_mutation_permitted="+(report.MutationPermitted()?"true":"false")
                            +" | remains_unresolved="+(stillUnresolved?"true":"false"));

      if(stillUnresolved)
        {
         unresolvedAfterOut++;
         if(blockingIdsOut!="")
            blockingIdsOut+=",";
         blockingIdsOut+=entry.ExecutionRequestId();
        }
     }

   delete store;
  }

void WriteLine(const int handle,const string line)
  {
   if(handle!=INVALID_HANDLE)
      FileWriteString(handle,line+"\r\n");
   Print(line);
  }

void OnStart(void)
  {
   string reportRel="BasketRecovery/validation/sprint-8c-preflight-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      return;

   string symbol=ResolveTradingSymbol(InpPreferredSymbol);
   ENUM_ACCOUNT_TRADE_MODE tradeMode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   long marginMode=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   string accountModeLabel=(tradeMode==ACCOUNT_TRADE_MODE_DEMO ? "DEMO" : "REAL");
   string marginModeLabel=MarginModeLabel(marginMode);
   string server=AccountInfoString(ACCOUNT_SERVER);
   string terminalClass=ServerClassification(server,tradeMode);
   double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double volumeStep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(minVolume<=0.0) minVolume=0.01;
   if(volumeStep<=0.0) volumeStep=minVolume;
   int symbolPositions=CountSymbolPositions(symbol);
   bool terminalTradeAllowed=(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)!=0);
   bool chartTradeAllowed=(MQLInfoInteger(MQL_TRADE_ALLOWED)!=0);

   CMt5BrokerPositionReader *positionReader=new CMt5BrokerPositionReader();
   CMt5BrokerExecutionHistoryReader *historyReader=new CMt5BrokerExecutionHistoryReader();
   int unresolvedBefore=0;
   int unresolvedAfter=0;
   string blockingExecutionIds="";
   AnalyzePendingExecutions(reportHandle,positionReader,historyReader,unresolvedBefore,unresolvedAfter,blockingExecutionIds);
   delete historyReader;
   delete positionReader;

   WriteLine(reportHandle,"account_trade_mode="+accountModeLabel);
   WriteLine(reportHandle,"account_margin_mode="+marginModeLabel);
   WriteLine(reportHandle,"account_position_model="+marginModeLabel);
   WriteLine(reportHandle,"terminal_classification="+terminalClass);
   WriteLine(reportHandle,"symbol="+symbol);
   WriteLine(reportHandle,"symbol_min_volume="+DoubleToString(minVolume,8));
   WriteLine(reportHandle,"symbol_volume_step="+DoubleToString(volumeStep,8));
   WriteLine(reportHandle,"terminal_trade_allowed="+(terminalTradeAllowed?"true":"false"));
   WriteLine(reportHandle,"chart_trade_allowed="+(chartTradeAllowed?"true":"false"));
   WriteLine(reportHandle,"symbol_positions_count="+IntegerToString(symbolPositions));
   WriteLine(reportHandle,"unresolved_before_reconcile="+IntegerToString(unresolvedBefore));
   WriteLine(reportHandle,"unresolved_after_reconcile="+IntegerToString(unresolvedAfter));
   WriteLine(reportHandle,"blocking_execution_ids="+blockingExecutionIds);
   WriteLine(reportHandle,"unresolved_pending_execution_count="+IntegerToString(unresolvedAfter));

   bool hedgingDemoReady=(tradeMode==ACCOUNT_TRADE_MODE_DEMO &&
                          marginMode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING &&
                          terminalClass=="DEMO" &&
                          terminalTradeAllowed &&
                          chartTradeAllowed &&
                          unresolvedAfter==0);
   WriteLine(reportHandle,"hedging_demo_ready="+(hedgingDemoReady?"true":"false"));

   bool abortBeforeSeed=(tradeMode!=ACCOUNT_TRADE_MODE_DEMO ||
                         marginMode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING ||
                         terminalClass!="DEMO" ||
                         !terminalTradeAllowed ||
                         !chartTradeAllowed ||
                         unresolvedAfter>0);
   WriteLine(reportHandle,"abort_before_seed="+(abortBeforeSeed?"true":"false"));

   if(marginMode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      WriteLine(reportHandle,"abort_reason=Account position model is not RETAIL_HEDGING");
   else if(tradeMode!=ACCOUNT_TRADE_MODE_DEMO)
      WriteLine(reportHandle,"abort_reason=Account is not DEMO");
   else if(terminalClass!="DEMO")
      WriteLine(reportHandle,"abort_reason=Terminal classification is not DEMO");
   else if(!terminalTradeAllowed || !chartTradeAllowed)
      WriteLine(reportHandle,"abort_reason=Algo/chart trading disabled");
   else if(unresolvedAfter>0)
      WriteLine(reportHandle,"abort_reason=Unresolved pending executions remain after read-only reconciliation");
   else
      WriteLine(reportHandle,"abort_reason=");

   WriteLine(reportHandle,"preflight_verification="+(abortBeforeSeed?"BLOCKED":"OK"));
   FileClose(reportHandle);
  }
