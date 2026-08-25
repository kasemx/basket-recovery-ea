#property copyright "Basket Recovery EA"
#property link      "https://github.com/basket-recovery-ea"
#property version   "0.0.3"

#include <BasketRecovery/Interfaces/Bootstrapper.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseSubmitDiagnostics.mqh>
#include <BasketRecovery/Domain/Execution/ProfitCloseAuthorizationBinding.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5TradeTransactionNormalizer.mqh>
#include <BasketRecovery/Domain/Execution/DemoManualSubmissionResult.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/LiveSubmissionSafetyRejectionReason.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationResult.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackManualTestOrchestrator.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackAuditFileSource.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackDemoSubmissionBridge.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackDemoSubmissionEnvironmentResolver.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackAuditSkippedLogThrottle.mqh>

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
input bool   InpObserverOnlyStartupIsolation = false;
input bool   InpFastTrackManualTestEnabled = false;
input string InpFastTrackSeedSignalText = "";
input string InpFastTrackDetailsSignalText = "";
input double InpFastTrackSeedLot = 0.01;
input int    InpFastTrackSeedOrderCount = 1;
input bool   InpFastTrackAllowDemoSeedExecution = false;
input bool   InpFastTrackEnableRecovery = false;
input bool   InpFastTrackEnableRangeAdd = false;
input bool   InpFastTrackEnableDeRisk = false;
input bool   InpFastTrackEnableBreakEven = false;
input bool   InpFastTrackAuditFilePollingEnabled = false;
input string InpFastTrackAuditSeedFileName = "br_d0e_justgold_seed.txt";
input string InpFastTrackAuditDetailsFileName = "br_d0e_justgold_details.txt";
input long   InpFastTrackDemoSubmissionMagicOverride = 91001;
input string InpFastTrackDemoSubmissionRouteLabel = "justgold-dashboard-route";
input string InpFastTrackDemoSubmissionTargetLabel = "d0e-vantage-xauusd-demo";
input int    InpFastTrackAuditFileNotFoundLogThrottleSeconds = 30;

CApplicationContext *g_applicationContext=NULL;
CMt5TradeTransactionNormalizer *g_tradeTransactionNormalizer=NULL;
int g_manualValidationTimerTicks=0;
int g_manualSubmissionTimerTicks=0;
bool g_manualRecoverySubmitAttempted=false;
bool g_manualProfitCloseSubmitAttempted=false;
CFastTrackManualTestOrchestrator g_fastTrackManualTestOrchestrator;
CFastTrackDemoSubmissionCandidateRegistry g_fastTrackDemoSubmissionRegistry;
CFastTrackAuditSkippedLogThrottle g_fastTrackAuditSkippedLogThrottle;
string g_fastTrackLastFingerprint="";

SFastTrackManualTestInputs BuildFastTrackManualTestInputs(void)
  {
   SFastTrackManualTestInputs inputs;
   inputs.enabled=InpFastTrackManualTestEnabled;
   inputs.seed_text=InpFastTrackSeedSignalText;
   inputs.details_text=InpFastTrackDetailsSignalText;
   inputs.seed_lot=InpFastTrackSeedLot;
   inputs.seed_order_count=InpFastTrackSeedOrderCount;
   inputs.allow_demo_seed_execution=InpFastTrackAllowDemoSeedExecution;
   inputs.enable_recovery=InpFastTrackEnableRecovery;
   inputs.enable_range_add=InpFastTrackEnableRangeAdd;
   inputs.enable_de_risk=InpFastTrackEnableDeRisk;
   inputs.enable_break_even=InpFastTrackEnableBreakEven;
   inputs.observer_only_startup_isolation=InpObserverOnlyStartupIsolation;
   inputs.global_execution_kill_switch=InpGlobalExecutionKillSwitch;
   inputs.enable_live_demo_execution=InpEnableLiveDemoExecution;
   inputs.execution_mode=InpExecutionMode;
   return inputs;
  }

SFastTrackDemoSubmissionBridgeInputs BuildFastTrackDemoSubmissionBridgeInputs(void)
  {
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs;
   bridgeInputs.Reset();
   bridgeInputs.enabled=InpFastTrackManualTestEnabled;
   bridgeInputs.require_manual_demo_authorization=InpRequireManualDemoAuthorization;
   bridgeInputs.audit_file_polling_enabled=InpFastTrackAuditFilePollingEnabled;
   bridgeInputs.allow_demo_seed_execution=InpFastTrackAllowDemoSeedExecution;
   bridgeInputs.enable_recovery=InpFastTrackEnableRecovery;
   bridgeInputs.enable_range_add=InpFastTrackEnableRangeAdd;
   bridgeInputs.enable_de_risk=InpFastTrackEnableDeRisk;
   bridgeInputs.enable_break_even=InpFastTrackEnableBreakEven;
   bridgeInputs.enable_re_entry=false;
   bridgeInputs.enable_partial_close=false;
   bridgeInputs.enable_trailing=false;
   bridgeInputs.observer_only_startup_isolation=InpObserverOnlyStartupIsolation;
   bridgeInputs.global_execution_kill_switch=InpGlobalExecutionKillSwitch;
   bridgeInputs.enable_live_demo_execution=InpEnableLiveDemoExecution;
   bridgeInputs.execution_mode=InpExecutionMode;
   bridgeInputs.seed_lot=InpFastTrackSeedLot;
   bridgeInputs.seed_order_count=InpFastTrackSeedOrderCount;
   bridgeInputs.magic_number_override=InpFastTrackDemoSubmissionMagicOverride;
   bridgeInputs.manual_demo_authorization_basket_id=InpManualDemoAuthorizationBasketId;
   bridgeInputs.route_label=InpFastTrackDemoSubmissionRouteLabel;
   bridgeInputs.target_label=InpFastTrackDemoSubmissionTargetLabel;
   bridgeInputs.environment=CFastTrackDemoSubmissionEnvironmentResolver::ResolveRuntime("XAUUSD");
   bridgeInputs.environment.require_manual_demo_authorization=InpRequireManualDemoAuthorization;
   bridgeInputs.environment.audit_file_polling_enabled=InpFastTrackAuditFilePollingEnabled;
   return bridgeInputs;
  }

bool ResolveFastTrackSignalText(string &seedText,string &detailsText)
  {
   seedText=InpFastTrackSeedSignalText;
   detailsText=InpFastTrackDetailsSignalText;

   if(seedText!="")
      return true;

   if(!InpFastTrackAuditFilePollingEnabled || !InpFastTrackManualTestEnabled)
      return false;

   string reason="";
   if(CFastTrackAuditFileSource::TryRead(true,
                                          InpFastTrackAuditSeedFileName,
                                          InpFastTrackAuditDetailsFileName,
                                          seedText,
                                          detailsText,
                                          reason))
     {
      g_fastTrackAuditSkippedLogThrottle.NotifyReadSuccess();
      return true;
     }

   if(reason!="" &&
      g_fastTrackAuditSkippedLogThrottle.ShouldLogSkipped(reason,TimeCurrent(),
                                                          InpFastTrackAuditFileNotFoundLogThrottleSeconds))
      CFastTrackAuditFileSource::PrintSkippedAudit(reason);
   return false;
  }

void ProcessFastTrackManualTest(void)
  {
   if(!InpFastTrackManualTestEnabled)
      return;

   string seedText="";
   string detailsText="";
   if(!ResolveFastTrackSignalText(seedText,detailsText) || seedText=="")
      return;

   string fingerprint=seedText+"|"+detailsText;
   if(fingerprint==g_fastTrackLastFingerprint)
      return;

   SFastTrackManualTestInputs inputs=BuildFastTrackManualTestInputs();
   inputs.seed_text=seedText;
   inputs.details_text=detailsText;
   SFastTrackManualTestOutcome outcome=g_fastTrackManualTestOrchestrator.Process(inputs,TimeCurrent());
   CFastTrackManualTestOrchestrator::PrintAudit(inputs,outcome);
   if(InpFastTrackAuditFilePollingEnabled && InpFastTrackSeedSignalText=="")
      CFastTrackAuditFileSource::PrintReadAudit(InpFastTrackAuditSeedFileName,
                                                InpFastTrackAuditDetailsFileName);

   if(outcome.stage==BRE_FAST_TRACK_MANUAL_STAGE_WAIT_DETAILS)
      return;

   g_fastTrackLastFingerprint=fingerprint;

   if(outcome.order_plan_result==BRE_FAST_TRACK_ORDER_PLAN_ALLOWED)
     {
      SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildFastTrackDemoSubmissionBridgeInputs();
      SFastTrackDemoSubmissionBridgeOutcome bridgeOutcome=CFastTrackDemoSubmissionBridge::TryCreateCandidate(
         inputs,outcome,bridgeInputs,g_fastTrackDemoSubmissionRegistry,TimeCurrent());
      CFastTrackDemoSubmissionBridge::PrintAudit(bridgeOutcome);
     }
  }

void PrintEaInitFailureDiagnostics(const string stageOverride="",
                                   const string reasonOverride="",
                                   const int errorCodeOverride=-1)
  {
   string stage=stageOverride;
   string reason=reasonOverride;
   int errorCode=errorCodeOverride;

   if(stage=="")
     {
      if(CBootstrapper::HasEaInitFailureRecord())
        {
         stage=CBootstrapper::EaInitFailureStage();
         reason=CBootstrapper::EaInitFailureReason();
         errorCode=CBootstrapper::EaInitFailureErrorCode();
        }
      else
        {
         stage=CBootstrapper::EaInitCurrentStage();
         reason="bootstrap_returned_null_without_recorded_reason";
         errorCode=0;
        }
     }

   if(reason=="")
      reason="unknown";

   Print("ea_init_failure_stage=",stage);
   Print("ea_init_failure_reason=",reason);
   Print("ea_init_failure_error_code=",IntegerToString(errorCode));
   Print("ea_init_live_demo_execution=",InpEnableLiveDemoExecution?"true":"false");
   Print("ea_init_global_kill_switch=",InpGlobalExecutionKillSwitch?"true":"false");
   Print("ea_init_basket_kill_switch=",InpBasketExecutionKillSwitch?"true":"false");
   Print("ea_init_dry_run=",InpEnableExecutionDryRun?"true":"false");
  }

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
   Print("ea_build_marker=S8C_BROKER_COMMENT_FACTORY_V1");
   Print("broker_comment_factory_build_marker=",CBrokerExecutionCommentFactory::BuildMarker());
   Print("auth_validate_runtime_build_marker=",BRE_AUTH_VALIDATE_RUNTIME_BUILD_MARKER);
   Print("auth_binding_build_marker=",CProfitCloseAuthorizationBinding::BuildMarker());
   Print("pending_precheck_runtime_build_marker=",BRE_PENDING_PRECHECK_BUILD_MARKER);
   Print("profit_close_transaction_correlation_build_marker=",BRE_PROFIT_CLOSE_TRANSACTION_CORRELATION_BUILD_MARKER);
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
                                                 InpManualProfitCloseCandidateExpirySeconds,
                                                 InpObserverOnlyStartupIsolation);
   if(g_applicationContext==NULL)
     {
      PrintEaInitFailureDiagnostics();
      Print("BasketRecoveryEA initialization failed");
      return INIT_FAILED;
     }

   g_tradeTransactionNormalizer=new CMt5TradeTransactionNormalizer(NULL);

   int timerIntervalMs=g_applicationContext.ApplicationTimerIntervalMs();
   if(!EventSetMillisecondTimer(timerIntervalMs))
     {
      PrintEaInitFailureDiagnostics("timer_setup","application_timer_start_failed",GetLastError());
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
   ProcessFastTrackManualTest();

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

   if(InpManualProfitCloseCandidateId!="")
      return;

   g_applicationContext.OnTick(_Symbol);
  }

void OnTimer()
  {
   if(g_applicationContext==NULL)
      return;

   if(InpManualProfitCloseCandidateId!="" && !g_manualProfitCloseSubmitAttempted)
      ProcessManualProfitCloseSubmissionChartValidation();

   if(InpManualProfitCloseCandidateId!="")
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

   if(InpFastTrackManualTestEnabled)
      ProcessFastTrackManualTest();
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
