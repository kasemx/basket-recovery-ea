#ifndef BASKET_RECOVERY_INFRASTRUCTURE_REST_CLIENT_CONFIG_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_REST_CLIENT_CONFIG_MQH

class CRestClientConfig
  {
private:
   string m_baseUrl;
   string m_apiKey;
   long   m_accountId;
   string m_mt5InstanceId;
   int    m_timeoutMs;

public:
                     CRestClientConfig(void)
     {
      m_baseUrl="";
      m_apiKey="";
      m_accountId=0;
      m_mt5InstanceId="";
      m_timeoutMs=5000;
     }

   string            BaseUrl(void) const { return m_baseUrl; }
   string            ApiKey(void) const { return m_apiKey; }
   long              AccountId(void) const { return m_accountId; }
   string            Mt5InstanceId(void) const { return m_mt5InstanceId; }
   int               TimeoutMs(void) const { return m_timeoutMs; }
   bool              IsEnabled(void) const { return m_baseUrl!=""; }

   void              SetBaseUrl(const string value) { m_baseUrl=value; }
   void              SetApiKey(const string value) { m_apiKey=value; }
   void              SetAccountId(const long value) { m_accountId=value; }
   void              SetMt5InstanceId(const string value) { m_mt5InstanceId=value; }
   void              SetTimeoutMs(const int value) { m_timeoutMs=value; }
  };

#endif
