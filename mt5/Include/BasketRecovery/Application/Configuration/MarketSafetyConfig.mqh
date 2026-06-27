#ifndef BRE_APP_MARKET_SAFETY_CONFIG_MQH
#define BRE_APP_MARKET_SAFETY_CONFIG_MQH

class CMarketSafetyConfig
  {
private:
   int m_quoteStaleThresholdMs;
   int m_maxSpreadPoints;
   int m_warningDedupeWindowMs;

public:
                     CMarketSafetyConfig(void)
     {
      m_quoteStaleThresholdMs=5000;
      m_maxSpreadPoints=500;
      m_warningDedupeWindowMs=30000;
     }

   int               QuoteStaleThresholdMs(void) const { return m_quoteStaleThresholdMs; }
   int               MaxSpreadPoints(void) const { return m_maxSpreadPoints; }
   int               WarningDedupeWindowMs(void) const { return m_warningDedupeWindowMs; }

   static CMarketSafetyConfig Create(const int quoteStaleThresholdMs,
                                     const int maxSpreadPoints,
                                     const int warningDedupeWindowMs)
     {
      CMarketSafetyConfig config;
      config.m_quoteStaleThresholdMs=quoteStaleThresholdMs;
      config.m_maxSpreadPoints=maxSpreadPoints;
      config.m_warningDedupeWindowMs=warningDedupeWindowMs;
      return config;
     }
  };

#endif
