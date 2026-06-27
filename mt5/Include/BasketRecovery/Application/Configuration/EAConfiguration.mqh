#ifndef BASKET_RECOVERY_APPLICATION_EA_CONFIGURATION_MQH
#define BASKET_RECOVERY_APPLICATION_EA_CONFIGURATION_MQH

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
   void              SetIsValid(const bool value) { m_isValid=value; }
  };

#endif
