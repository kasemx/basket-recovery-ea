#ifndef BASKET_RECOVERY_INFRASTRUCTURE_MT5_CONFIGURATION_LOADER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_MT5_CONFIGURATION_LOADER_MQH

#include <BasketRecovery/Application/Configuration/EAConfiguration.mqh>
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
                                                 const int tickSilenceFallbackMs)
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
      configuration.SetMarketSafetyConfig(CMarketSafetyConfig::Create(quoteStaleThresholdMs,
                                                                      maxSpreadPoints,
                                                                      30000));

      if(profileName=="")
         return CResult<CEAConfiguration>::Fail(BRE_ERR_CONFIG_INVALID,"Profile name input is empty");

      if(logFilePath=="")
         return CResult<CEAConfiguration>::Fail(BRE_ERR_CONFIG_INVALID,"Log file path input is empty");

      if(logLevel<0 || logLevel>5)
         return CResult<CEAConfiguration>::Fail(BRE_ERR_CONFIG_INVALID,"Log level must be between 0 and 5");

      configuration.SetIsValid(true);
      return CResult<CEAConfiguration>::Ok(configuration);
     }
  };

#endif
