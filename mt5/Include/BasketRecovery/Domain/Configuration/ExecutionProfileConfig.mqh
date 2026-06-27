#ifndef BASKET_RECOVERY_DOMAIN_EXECUTION_PROFILE_CONFIG_MQH
#define BASKET_RECOVERY_DOMAIN_EXECUTION_PROFILE_CONFIG_MQH

class CExecutionProfileConfig
  {
private:
   string m_profileName;
   int    m_slippagePoints;
   int    m_maxTradeRetries;
   int    m_magicNumberBase;
   int    m_commandBatchSize;
   int    m_tradeRequestBatchSize;
   int    m_restPollIntervalMs;

public:
                     CExecutionProfileConfig(void)
     {
      m_profileName="default";
      m_slippagePoints=10;
      m_maxTradeRetries=3;
      m_magicNumberBase=202606000;
      m_commandBatchSize=10;
      m_tradeRequestBatchSize=5;
      m_restPollIntervalMs=3000;
     }

   string            ProfileName(void) const { return m_profileName; }
   int               SlippagePoints(void) const { return m_slippagePoints; }
   int               MaxTradeRetries(void) const { return m_maxTradeRetries; }
   int               MagicNumberBase(void) const { return m_magicNumberBase; }
   int               CommandBatchSize(void) const { return m_commandBatchSize; }
   int               TradeRequestBatchSize(void) const { return m_tradeRequestBatchSize; }
   int               RestPollIntervalMs(void) const { return m_restPollIntervalMs; }

   void              SetProfileName(const string value) { m_profileName=value; }
   void              SetSlippagePoints(const int value) { m_slippagePoints=value; }
   void              SetMaxTradeRetries(const int value) { m_maxTradeRetries=value; }
   void              SetMagicNumberBase(const int value) { m_magicNumberBase=value; }
   void              SetCommandBatchSize(const int value) { m_commandBatchSize=value; }
   void              SetTradeRequestBatchSize(const int value) { m_tradeRequestBatchSize=value; }
   void              SetRestPollIntervalMs(const int value) { m_restPollIntervalMs=value; }
  };

#endif
