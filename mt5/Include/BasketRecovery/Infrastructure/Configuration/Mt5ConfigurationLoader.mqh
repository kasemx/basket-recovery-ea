#ifndef BASKET_RECOVERY_INFRASTRUCTURE_MT5_CONFIGURATION_LOADER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_MT5_CONFIGURATION_LOADER_MQH

#include <BasketRecovery/Application/Configuration/EAConfiguration.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class CMt5ConfigurationLoader
  {
public:
   static CResult<CEAConfiguration> LoadFromInputs(const string profileName,
                                                 const string logFilePath,
                                                 const int logLevel,
                                                 const string accountLabel,
                                                 const string apiBaseUrl,
                                                 const string apiKey,
                                                 const int restPollIntervalMs,
                                                 const int applicationTimerIntervalMs,
                                                 const int maxBasketsPerTick,
                                                 const int reconciliationIntervalMs,
                                                 const int quoteStaleThresholdMs,
                                                 const int maxSpreadPoints,
                                                 const int maxEvaluationAgeMs,
                                                 const int minEvaluationIntervalMs,
                                                 const int materialQuoteChangePoints,
                                                 const int tickSilenceFallbackMs,
                                                 const bool enableFastPathDiagnostics,
                                                 const int fastPathDiagnosticIntervalMs,
                                                 const bool enableFastPathNoBasketHeartbeat,
                                                 const int executionRuntimeMode,
                                                 const bool enableExecutionDryRun,
                                                 const bool enableExecutionDiagnostics,
                                                 const bool enableLiveDemoExecution,
                                                 const bool requireManualDemoAuthorization,
                                                 const bool globalExecutionKillSwitch,
                                                 const bool basketExecutionKillSwitch,
                                                 const string basketExecutionKillSwitchBasketId,
                                                 const int maxAuthorizedRequestsPerSession,
                                                 const int authorizationTokenExpirySeconds,
                                                 const double maxManualDemoOpenVolume)
     {
      CEAConfiguration configuration;
      configuration.SetProfileName(profileName);
      configuration.SetLogFilePath(logFilePath);
      configuration.SetLogLevel(logLevel);
      configuration.SetAccountLabel(accountLabel);
      configuration.SetAccountLogin(AccountInfoInteger(ACCOUNT_LOGIN));
      configuration.SetApiBaseUrl(apiBaseUrl);
      configuration.SetApiKey(apiKey);
      configuration.SetRestPollIntervalMs(restPollIntervalMs);
      configuration.SetApplicationTimerIntervalMs(applicationTimerIntervalMs);
      configuration.SetMaxBasketsPerTick(maxBasketsPerTick);
      configuration.SetReconciliationIntervalMs(reconciliationIntervalMs);
      configuration.SetMaxEvaluationAgeMs(maxEvaluationAgeMs);
      configuration.SetMinEvaluationIntervalMs(minEvaluationIntervalMs);
      configuration.SetMaterialQuoteChangePoints(materialQuoteChangePoints);
      configuration.SetTickSilenceFallbackMs(tickSilenceFallbackMs);
      configuration.SetEnableFastPathDiagnostics(enableFastPathDiagnostics);
      configuration.SetFastPathDiagnosticIntervalMs(fastPathDiagnosticIntervalMs);
      configuration.SetEnableFastPathNoBasketHeartbeat(enableFastPathNoBasketHeartbeat);
      configuration.SetExecutionRuntimeMode((ENUM_BRE_EXECUTION_RUNTIME_MODE)executionRuntimeMode);
      configuration.SetEnableExecutionDryRun(enableExecutionDryRun);
      configuration.SetEnableExecutionDiagnostics(enableExecutionDiagnostics);
      configuration.SetMarketSafetyConfig(CMarketSafetyConfig::Create(quoteStaleThresholdMs,
                                                                      maxSpreadPoints,
                                                                      30000));

      CDemoExecutionAuthorizationConfig demoConfig;
      demoConfig.SetExecutionRuntimeMode((ENUM_BRE_EXECUTION_RUNTIME_MODE)executionRuntimeMode);
      demoConfig.SetEnableLiveDemoExecution(enableLiveDemoExecution);
      demoConfig.SetRequireManualDemoAuthorization(requireManualDemoAuthorization);
      demoConfig.SetGlobalExecutionKillSwitch(globalExecutionKillSwitch);
      demoConfig.SetBasketExecutionKillSwitch(basketExecutionKillSwitch);
      demoConfig.SetBasketExecutionKillSwitchBasketId(basketExecutionKillSwitchBasketId);
      demoConfig.SetMaxAuthorizedRequestsPerSession(maxAuthorizedRequestsPerSession);
      demoConfig.SetAuthorizationTokenExpirySeconds(authorizationTokenExpirySeconds);
      demoConfig.SetMaxManualDemoOpenVolume(maxManualDemoOpenVolume>0.0 ? maxManualDemoOpenVolume : 0.01);
      configuration.SetDemoAuthorizationConfig(demoConfig);

      if(profileName=="")
         return CResult<CEAConfiguration>::Fail(BRE_ERR_CONFIG_INVALID,"Profile name input is empty");

      if(logFilePath=="")
         return CResult<CEAConfiguration>::Fail(BRE_ERR_CONFIG_INVALID,"Log file path input is empty");

      if(logLevel<0 || logLevel>5)
         return CResult<CEAConfiguration>::Fail(BRE_ERR_CONFIG_INVALID,"Log level must be between 0 and 5");

      if(executionRuntimeMode<BRE_EXEC_RUNTIME_DISABLED || executionRuntimeMode>BRE_EXEC_RUNTIME_DEMO_MANUAL_SUBMISSION)
         return CResult<CEAConfiguration>::Fail(BRE_ERR_CONFIG_INVALID,"Execution runtime mode is invalid");

      configuration.SetIsValid(true);
      return CResult<CEAConfiguration>::Ok(configuration);
     }
  };

#endif
