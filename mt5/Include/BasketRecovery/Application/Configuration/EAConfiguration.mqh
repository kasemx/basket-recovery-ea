#ifndef BASKET_RECOVERY_APPLICATION_EA_CONFIGURATION_MQH
#define BASKET_RECOVERY_APPLICATION_EA_CONFIGURATION_MQH

#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>

class CEAConfiguration
  {
private:
   string m_profileName;
   string m_logFilePath;
   int    m_logLevel;
   string m_accountLabel;
   long   m_accountLogin;
   string m_apiBaseUrl;
   string m_apiKey;
   int    m_restPollIntervalMs;
   int    m_applicationTimerIntervalMs;
   int    m_strategyEvalIntervalMs;
   int    m_maxBasketsPerEvalCycle;
   int    m_marketRefreshIntervalMs;
   int    m_reconciliationIntervalMs;
   int    m_maxBasketsPerReconcileCycle;
   int    m_maxBasketsPerTick;
   int    m_maxEvaluationAgeMs;
   int    m_minEvaluationIntervalMs;
   int    m_materialQuoteChangePoints;
   int    m_tickSilenceFallbackMs;
   bool   m_enableFastPathDiagnostics;
   int    m_fastPathDiagnosticIntervalMs;
   bool   m_enableFastPathNoBasketHeartbeat;
   CMarketSafetyConfig m_marketSafetyConfig;
   bool   m_isValid;

public:
                     CEAConfiguration(void)
     {
      m_profileName="default";
      m_logFilePath="BasketRecovery/logs/basket_recovery.log";
      m_logLevel=2;
      m_accountLabel="";
      m_accountLogin=0;
      m_apiBaseUrl="";
      m_apiKey="";
      m_restPollIntervalMs=3000;
      m_applicationTimerIntervalMs=250;
      m_strategyEvalIntervalMs=5000;
      m_maxBasketsPerEvalCycle=5;
      m_marketRefreshIntervalMs=1000;
      m_reconciliationIntervalMs=30000;
      m_maxBasketsPerReconcileCycle=3;
      m_maxBasketsPerTick=3;
      m_maxEvaluationAgeMs=2000;
      m_minEvaluationIntervalMs=250;
      m_materialQuoteChangePoints=5;
      m_tickSilenceFallbackMs=10000;
      m_enableFastPathDiagnostics=false;
      m_fastPathDiagnosticIntervalMs=1000;
      m_enableFastPathNoBasketHeartbeat=false;
      m_marketSafetyConfig=CMarketSafetyConfig();
      m_isValid=false;
     }

   string            ProfileName(void) const { return m_profileName; }
   string            LogFilePath(void) const { return m_logFilePath; }
   int               LogLevel(void) const { return m_logLevel; }
   string            AccountLabel(void) const { return m_accountLabel; }
   long              AccountLogin(void) const { return m_accountLogin; }
   string            ApiBaseUrl(void) const { return m_apiBaseUrl; }
   string            ApiKey(void) const { return m_apiKey; }
   int               RestPollIntervalMs(void) const { return m_restPollIntervalMs; }
   int               ApplicationTimerIntervalMs(void) const { return m_applicationTimerIntervalMs; }
   int               StrategyEvalIntervalMs(void) const { return m_strategyEvalIntervalMs; }
   int               MaxBasketsPerEvalCycle(void) const { return m_maxBasketsPerEvalCycle; }
   int               MarketRefreshIntervalMs(void) const { return m_marketRefreshIntervalMs; }
   int               ReconciliationIntervalMs(void) const { return m_reconciliationIntervalMs; }
   int               MaxBasketsPerReconcileCycle(void) const { return m_maxBasketsPerReconcileCycle; }
   int               MaxBasketsPerTick(void) const { return m_maxBasketsPerTick; }
   int               MaxEvaluationAgeMs(void) const { return m_maxEvaluationAgeMs; }
   int               MinEvaluationIntervalMs(void) const { return m_minEvaluationIntervalMs; }
   int               MaterialQuoteChangePoints(void) const { return m_materialQuoteChangePoints; }
   int               TickSilenceFallbackMs(void) const { return m_tickSilenceFallbackMs; }
   bool              EnableFastPathDiagnostics(void) const { return m_enableFastPathDiagnostics; }
   int               FastPathDiagnosticIntervalMs(void) const { return m_fastPathDiagnosticIntervalMs; }
   bool              EnableFastPathNoBasketHeartbeat(void) const { return m_enableFastPathNoBasketHeartbeat; }
   CMarketSafetyConfig MarketSafetyConfig(void) const { return m_marketSafetyConfig; }
   bool              IsValid(void) const { return m_isValid; }

   void              SetProfileName(const string value) { m_profileName=value; }
   void              SetLogFilePath(const string value) { m_logFilePath=value; }
   void              SetLogLevel(const int value) { m_logLevel=value; }
   void              SetAccountLabel(const string value) { m_accountLabel=value; }
   void              SetAccountLogin(const long value) { m_accountLogin=value; }
   void              SetApiBaseUrl(const string value) { m_apiBaseUrl=value; }
   void              SetApiKey(const string value) { m_apiKey=value; }
   void              SetRestPollIntervalMs(const int value) { m_restPollIntervalMs=value; }
   void              SetApplicationTimerIntervalMs(const int value) { m_applicationTimerIntervalMs=value; }
   void              SetStrategyEvalIntervalMs(const int value) { m_strategyEvalIntervalMs=value; }
   void              SetMaxBasketsPerEvalCycle(const int value) { m_maxBasketsPerEvalCycle=value; }
   void              SetMarketRefreshIntervalMs(const int value) { m_marketRefreshIntervalMs=value; }
   void              SetReconciliationIntervalMs(const int value) { m_reconciliationIntervalMs=value; }
   void              SetMaxBasketsPerReconcileCycle(const int value) { m_maxBasketsPerReconcileCycle=value; }
   void              SetMaxBasketsPerTick(const int value) { m_maxBasketsPerTick=value; }
   void              SetMaxEvaluationAgeMs(const int value) { m_maxEvaluationAgeMs=value; }
   void              SetMinEvaluationIntervalMs(const int value) { m_minEvaluationIntervalMs=value; }
   void              SetMaterialQuoteChangePoints(const int value) { m_materialQuoteChangePoints=value; }
   void              SetTickSilenceFallbackMs(const int value) { m_tickSilenceFallbackMs=value; }
   void              SetEnableFastPathDiagnostics(const bool value) { m_enableFastPathDiagnostics=value; }
   void              SetFastPathDiagnosticIntervalMs(const int value) { m_fastPathDiagnosticIntervalMs=value; }
   void              SetEnableFastPathNoBasketHeartbeat(const bool value) { m_enableFastPathNoBasketHeartbeat=value; }
   void              SetMarketSafetyConfig(const CMarketSafetyConfig &value) { m_marketSafetyConfig=value; }
   void              SetIsValid(const bool value) { m_isValid=value; }
  };

#endif
