#property copyright "Basket Recovery EA"
#property link      "https://github.com/basket-recovery-ea"
#property version   "0.0.3"

#include <BasketRecovery/Interfaces/Bootstrapper.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5TradeTransactionNormalizer.mqh>

input string InpProfileName               = "default";
input string InpLogFilePath               = "BasketRecovery/logs/basket_recovery.log";
input int    InpLogLevel                  = 2;
input string InpAccountLabel              = "primary";
input string InpApiBaseUrl                = "";
input string InpApiKey                    = "";
input int    InpRestPollIntervalMs        = 0;
input int    InpApplicationTimerIntervalMs = 250;
input int    InpMaxBasketsPerTick         = 3;
input int    InpReconciliationIntervalMs  = 30000;
input int    InpQuoteStaleThresholdMs     = 5000;
input int    InpMaxSpreadPoints           = 500;
input int    InpMaxEvaluationAgeMs        = 2000;
input int    InpMinEvaluationIntervalMs   = 250;
input int    InpMaterialQuoteChangePoints = 5;
input int    InpTickSilenceFallbackMs     = 10000;
input bool   InpEnableFastPathDiagnostics = false;
input int    InpFastPathDiagnosticIntervalMs = 1000;
input bool   InpEnableFastPathNoBasketHeartbeat = false;
input int    InpExecutionMode = 0;
input bool   InpEnableExecutionDryRun = false;
input bool   InpEnableExecutionDiagnostics = false;
input string InpManualExecutionDryRunBasketId = "";
input string InpManualExecutionDryRunTriggerToken = "";
input double InpManualExecutionDryRunLotSize = 0.01;

CApplicationContext *g_applicationContext=NULL;
CMt5TradeTransactionNormalizer *g_tradeTransactionNormalizer=NULL;
int g_manualValidationTimerTicks=0;

int OnInit()
  {
   MathSrand((int)GetTickCount());

   g_applicationContext=CBootstrapper::Bootstrap(InpProfileName,
                                                 InpLogFilePath,
                                                 InpLogLevel,
                                                 InpAccountLabel,
                                                 InpApiBaseUrl,
                                                 InpApiKey,
                                                 InpRestPollIntervalMs,
                                                 InpApplicationTimerIntervalMs,
                                                 InpMaxBasketsPerTick,
                                                 InpReconciliationIntervalMs,
                                                 InpQuoteStaleThresholdMs,
                                                 InpMaxSpreadPoints,
                                                 InpMaxEvaluationAgeMs,
                                                 InpMinEvaluationIntervalMs,
                                                 InpMaterialQuoteChangePoints,
                                                 InpTickSilenceFallbackMs,
                                                 InpEnableFastPathDiagnostics,
                                                 InpFastPathDiagnosticIntervalMs,
                                                 InpEnableFastPathNoBasketHeartbeat,
                                                 InpExecutionMode,
                                                 InpEnableExecutionDryRun,
                                                 InpEnableExecutionDiagnostics);
   if(g_applicationContext==NULL)
     {
      Print("BasketRecoveryEA initialization failed");
      return INIT_FAILED;
     }

   g_tradeTransactionNormalizer=new CMt5TradeTransactionNormalizer(NULL);

   int timerIntervalMs=g_applicationContext.ApplicationTimerIntervalMs();
   if(!EventSetMillisecondTimer(timerIntervalMs))
     {
      Print("BasketRecoveryEA failed to start application timer | interval_ms=",timerIntervalMs);
      return INIT_FAILED;
     }

   Print("BasketRecoveryEA v0.0.3 started | profile=",InpProfileName,
         " | account=",AccountInfoInteger(ACCOUNT_LOGIN),
         " | app_timer_ms=",timerIntervalMs,
         " | fast_tick_budget=",InpMaxBasketsPerTick);

   if(InpEnableExecutionDiagnostics && InpManualExecutionDryRunBasketId!="")
     {
      Print("BRE chart-validation | terminal_trade_allowed=",
            (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"true":"false"),
            " | account_trade_expert=",
            (AccountInfoInteger(ACCOUNT_TRADE_EXPERT)?"true":"false"),
            " | broker_state_before | positions=",PositionsTotal(),
            " | orders=",OrdersTotal(),
            " | common_persistence=",
            TerminalInfoString(TERMINAL_COMMONDATA_PATH),"\\Files\\BasketRecovery\\persistence\\baskets\\",
            InpManualExecutionDryRunBasketId,".json");
     }

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();

   if(g_tradeTransactionNormalizer!=NULL)
     {
      delete g_tradeTransactionNormalizer;
      g_tradeTransactionNormalizer=NULL;
     }

   if(g_applicationContext!=NULL)
     {
      g_applicationContext.LogFastPathDeinitSummary();
      g_applicationContext.LogShutdown(reason);
      delete g_applicationContext;
      g_applicationContext=NULL;
     }
  }

void OnTick()
  {
   if(g_applicationContext==NULL)
      return;

   g_applicationContext.OnTick(_Symbol);
  }

void OnTimer()
  {
   if(g_applicationContext==NULL)
      return;

   int commandsProcessed=0;
   int eventsProcessed=0;
   int evaluationsScheduled=0;
   g_applicationContext.OnApplicationTimer(commandsProcessed,eventsProcessed,evaluationsScheduled);

   if(InpManualExecutionDryRunBasketId!="")
     {
      if(InpEnableExecutionDiagnostics || (InpManualExecutionDryRunTriggerToken!="" && InpManualExecutionDryRunTriggerToken!="0"))
        {
         CVoidResult dryRunResult=g_applicationContext.TryProcessManualExecutionDryRun(
            InpManualExecutionDryRunBasketId,
            InpManualExecutionDryRunTriggerToken,
            InpManualExecutionDryRunLotSize);
         if(dryRunResult.IsFail())
            Print("Manual execution dry-run rejected | code=",dryRunResult.ErrorCode(),
                  " | message=",dryRunResult.ErrorMessage());

         g_manualValidationTimerTicks++;
         bool crcOnly=(InpManualExecutionDryRunTriggerToken=="" || InpManualExecutionDryRunTriggerToken=="0");
         int ticksBeforeShutdown=(crcOnly ? 1 : 1);
         if(g_manualValidationTimerTicks>=ticksBeforeShutdown)
           {
            ExpertRemove();
            TerminalClose(0);
           }
        }
     }
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(g_applicationContext==NULL || g_tradeTransactionNormalizer==NULL)
      return;

   CNormalizedTradeTransaction normalized=
      g_tradeTransactionNormalizer.Normalize(trans,request,result);

   g_applicationContext.ApplyNormalizedTransaction(normalized);
  }
