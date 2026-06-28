#property copyright "Basket Recovery EA"
#property link      "https://github.com/basket-recovery-ea"
#property version   "0.0.3"

#include <BasketRecovery/Interfaces/Bootstrapper.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5TradeTransactionNormalizer.mqh>
#include <BasketRecovery/Domain/Execution/DemoManualSubmissionResult.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/LiveSubmissionSafetyRejectionReason.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationResult.mqh>

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
input bool   InpEnableLiveDemoExecution = false;
input bool   InpRequireManualDemoAuthorization = true;
input bool   InpGlobalExecutionKillSwitch = false;
input bool   InpBasketExecutionKillSwitch = false;
input string InpBasketExecutionKillSwitchBasketId = "";
input int    InpMaxAuthorizedRequestsPerSession = 1;
input int    InpAuthorizationTokenExpirySeconds = 300;
input string InpManualDemoAuthorizationToken = "";
input string InpManualDemoAuthorizationRequestId = "";
input string InpManualDemoAuthorizationBasketId = "";
input string InpManualDemoSubmissionRequestId = "";
input string InpManualDemoSubmissionTriggerToken = "";
input double InpMaxManualDemoOpenVolume = 0.01;
input bool   InpManualDemoValidationAutoShutdown = false;
input string InpManualExecutionDryRunBasketId = "";
input string InpManualExecutionDryRunTriggerToken = "";
input double InpManualExecutionDryRunLotSize = 0.01;
input string InpManualRecoveryCandidateId = "";
input string InpManualRecoverySubmissionTriggerToken = "";
input int    InpManualRecoveryCandidateExpirySeconds = 30;
input string InpManualProfitCloseCandidateId = "";
input string InpManualProfitCloseSubmissionTriggerToken = "";
input int    InpManualProfitCloseCandidateExpirySeconds = 30;

CApplicationContext *g_applicationContext=NULL;
CMt5TradeTransactionNormalizer *g_tradeTransactionNormalizer=NULL;
int g_manualValidationTimerTicks=0;
int g_manualSubmissionTimerTicks=0;
bool g_manualRecoverySubmitAttempted=false;
bool g_manualProfitCloseSubmitAttempted=false;

void ProcessManualProfitCloseSubmissionChartValidation(void)
  {
   if(g_applicationContext==NULL || g_manualProfitCloseSubmitAttempted)
      return;
   if(InpManualProfitCloseCandidateId=="")
      return;
   if(!(InpEnableExecutionDiagnostics ||
        (InpManualDemoAuthorizationToken!="" && InpManualProfitCloseSubmissionTriggerToken!="")))
      return;

   g_manualProfitCloseSubmitAttempted=true;

   if(InpEnableExecutionDiagnostics)
      Print("BRE broker_state_before | positions=",PositionsTotal(),
            " | orders=",OrdersTotal(),
            " | deals_history=",HistoryDealsTotal());

   CDemoManualSubmissionResult profitCloseResult=g_applicationContext.TryProcessManualProfitCloseSubmission(
      InpManualProfitCloseCandidateId,
      InpManualDemoAuthorizationToken,
      InpManualProfitCloseSubmissionTriggerToken,
      InpManualDemoAuthorizationBasketId,
      (long)202606001);

   if(InpEnableExecutionDiagnostics)
      Print("BRE broker_state_after | positions=",PositionsTotal(),
            " | orders=",OrdersTotal(),
            " | deals_history=",HistoryDealsTotal());

   if(profitCloseResult.IsSuccess())
      Print("Manual profit close submission accepted | status=",
            TradeExecutionStatusLabel(profitCloseResult.ResultingStatus()),
            " | order_send_async=",profitCloseResult.OrderSendAsyncAccepted()?"true":"false");
   else
      Print("Manual profit close submission rejected | reason=",
            LiveSubmissionSafetyRejectionReasonLabel(profitCloseResult.RejectionReason()),
            " | detail=",profitCloseResult.Detail());
  }

void ProcessManualRecoverySubmissionChartValidation(void)
  {
   if(g_applicationContext==NULL || g_manualRecoverySubmitAttempted)
      return;
   if(InpManualRecoveryCandidateId=="")
      return;
   if(!(InpEnableExecutionDiagnostics ||
        (InpManualDemoAuthorizationToken!="" && InpManualRecoverySubmissionTriggerToken!="")))
      return;

   g_manualRecoverySubmitAttempted=true;

   if(InpEnableExecutionDiagnostics)
      Print("BRE broker_state_before | positions=",PositionsTotal(),
            " | orders=",OrdersTotal(),
            " | deals_history=",HistoryDealsTotal());

   CDemoManualSubmissionResult recoveryResult=g_applicationContext.TryProcessManualRecoverySubmission(
      InpManualRecoveryCandidateId,
      InpManualDemoAuthorizationToken,
      InpManualRecoverySubmissionTriggerToken,
      InpManualDemoAuthorizationBasketId,
      (long)202606001);

   if(InpEnableExecutionDiagnostics)
      Print("BRE broker_state_after | positions=",PositionsTotal(),
            " | orders=",OrdersTotal(),
            " | deals_history=",HistoryDealsTotal());

   if(recoveryResult.IsSuccess())
      Print("Manual recovery submission accepted | status=",
            TradeExecutionStatusLabel(recoveryResult.ResultingStatus()),
            " | order_send_async=",recoveryResult.OrderSendAsyncAccepted()?"true":"false");
   else
      Print("Manual recovery submission rejected | reason=",
            LiveSubmissionSafetyRejectionReasonLabel(recoveryResult.RejectionReason()),
            " | detail=",recoveryResult.Detail());
  }

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
                                                 InpEnableExecutionDiagnostics,
                                                 InpEnableLiveDemoExecution,
                                                 InpRequireManualDemoAuthorization,
                                                 InpGlobalExecutionKillSwitch,
                                                 InpBasketExecutionKillSwitch,
                                                 InpBasketExecutionKillSwitchBasketId,
                                                 InpMaxAuthorizedRequestsPerSession,
                                                 InpAuthorizationTokenExpirySeconds,
                                                 InpMaxManualDemoOpenVolume,
                                                 InpManualRecoveryCandidateExpirySeconds,
                                                 InpManualProfitCloseCandidateExpirySeconds);
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

   ProcessManualRecoverySubmissionChartValidation();
   ProcessManualProfitCloseSubmissionChartValidation();

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

   if(InpManualProfitCloseCandidateId!="" && InpManualDemoValidationAutoShutdown)
     {
      g_manualSubmissionTimerTicks++;
      if(g_manualSubmissionTimerTicks>=12)
        {
         ExpertRemove();
         TerminalClose(0);
        }
      return;
     }

   if(InpManualProfitCloseCandidateId!="" && !g_manualProfitCloseSubmitAttempted)
      ProcessManualProfitCloseSubmissionChartValidation();

   if(InpManualProfitCloseCandidateId!="")
      return;

   if(InpManualRecoveryCandidateId!="" && InpManualDemoValidationAutoShutdown)
     {
      g_manualSubmissionTimerTicks++;
      if(g_manualSubmissionTimerTicks>=12)
        {
         ExpertRemove();
         TerminalClose(0);
        }
      return;
     }

   if(InpManualRecoveryCandidateId!="" && !g_manualRecoverySubmitAttempted)
      ProcessManualRecoverySubmissionChartValidation();

   if(InpManualRecoveryCandidateId!="")
      return;

   if(InpManualDemoSubmissionRequestId!="")
     {
      if(InpEnableExecutionDiagnostics ||
         (InpManualDemoAuthorizationToken!="" && InpManualDemoSubmissionTriggerToken!=""))
        {
         if(InpEnableExecutionDiagnostics)
            Print("BRE broker_state_before | positions=",PositionsTotal(),
                  " | orders=",OrdersTotal(),
                  " | deals_history=",HistoryDealsTotal());

         CDemoManualSubmissionResult submitResult=g_applicationContext.TryProcessManualDemoSubmission(
            InpManualDemoSubmissionRequestId,
            InpManualDemoAuthorizationToken,
            InpManualDemoSubmissionTriggerToken,
            InpManualDemoAuthorizationBasketId);

         if(InpEnableExecutionDiagnostics)
            Print("BRE broker_state_after | positions=",PositionsTotal(),
                  " | orders=",OrdersTotal(),
                  " | deals_history=",HistoryDealsTotal());

         if(submitResult.IsSuccess())
            Print("Manual demo submission accepted | status=",
                  TradeExecutionStatusLabel(submitResult.ResultingStatus()),
                  " | order_send_async=",submitResult.OrderSendAsyncAccepted()?"true":"false");
         else
            Print("Manual demo submission rejected | reason=",
                  LiveSubmissionSafetyRejectionReasonLabel(submitResult.RejectionReason()),
                  " | detail=",submitResult.Detail());

         if(InpManualDemoValidationAutoShutdown)
           {
            g_manualSubmissionTimerTicks++;
            if(g_manualSubmissionTimerTicks>=12)
              {
               ExpertRemove();
               TerminalClose(0);
              }
           }
        }
     }

   if(InpManualDemoAuthorizationRequestId!="")
     {
      if(InpEnableExecutionDiagnostics || InpManualDemoAuthorizationToken!="")
        {
         CExecutionAuthorizationResult authResult=g_applicationContext.TryProcessManualDemoAuthorizationValidation(
            InpManualDemoAuthorizationRequestId,
            InpManualDemoAuthorizationToken,
            InpManualDemoAuthorizationBasketId);
         if(authResult.IsSuccess())
            Print("Manual demo authorization accepted | status=",
                  ExecutionAuthorizationStatusLabel(authResult.Status()));
         else
            Print("Manual demo authorization rejected | reason=",
                  LiveSubmissionSafetyRejectionReasonLabel(authResult.RejectionReason()),
                  " | detail=",authResult.Detail());
        }
     }

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

   if(InpEnableExecutionDiagnostics)
      Print("BRE OnTradeTransaction | type=",trans.type,
            " | order=",trans.order,
            " | deal=",trans.deal,
            " | symbol=",trans.symbol,
            " | comment=",request.comment);
  }
