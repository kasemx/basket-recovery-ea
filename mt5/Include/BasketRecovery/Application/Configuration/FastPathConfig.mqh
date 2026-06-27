#ifndef BRE_APP_FAST_PATH_CONFIG_MQH
#define BRE_APP_FAST_PATH_CONFIG_MQH

class CFastPathConfig
  {
private:
   int  m_maxBasketsPerTick;
   int  m_maxEvaluationAgeMs;
   int  m_minEvaluationIntervalMs;
   int  m_materialQuoteChangePoints;
   int  m_tickSilenceFallbackMs;
   bool m_enableFastPathDiagnostics;
   int  m_fastPathDiagnosticIntervalMs;
   bool m_enableFastPathNoBasketHeartbeat;

public:
                     CFastPathConfig(void)
     {
      m_maxBasketsPerTick=3;
      m_maxEvaluationAgeMs=2000;
      m_minEvaluationIntervalMs=250;
      m_materialQuoteChangePoints=5;
      m_tickSilenceFallbackMs=10000;
      m_enableFastPathDiagnostics=false;
      m_fastPathDiagnosticIntervalMs=1000;
      m_enableFastPathNoBasketHeartbeat=false;
     }

   int               MaxBasketsPerTick(void) const { return m_maxBasketsPerTick; }
   int               MaxEvaluationAgeMs(void) const { return m_maxEvaluationAgeMs; }
   int               MinEvaluationIntervalMs(void) const { return m_minEvaluationIntervalMs; }
   int               MaterialQuoteChangePoints(void) const { return m_materialQuoteChangePoints; }
   int               TickSilenceFallbackMs(void) const { return m_tickSilenceFallbackMs; }
   bool              EnableFastPathDiagnostics(void) const { return m_enableFastPathDiagnostics; }
   int               FastPathDiagnosticIntervalMs(void) const { return m_fastPathDiagnosticIntervalMs; }
   bool              EnableFastPathNoBasketHeartbeat(void) const { return m_enableFastPathNoBasketHeartbeat; }

   static CFastPathConfig Create(const int maxBasketsPerTick,
                                 const int maxEvaluationAgeMs,
                                 const int minEvaluationIntervalMs,
                                 const int materialQuoteChangePoints,
                                 const int tickSilenceFallbackMs,
                                 const bool enableFastPathDiagnostics=false,
                                 const int fastPathDiagnosticIntervalMs=1000,
                                 const bool enableFastPathNoBasketHeartbeat=false)
     {
      CFastPathConfig config;
      config.m_maxBasketsPerTick=maxBasketsPerTick;
      config.m_maxEvaluationAgeMs=maxEvaluationAgeMs;
      config.m_minEvaluationIntervalMs=minEvaluationIntervalMs;
      config.m_materialQuoteChangePoints=materialQuoteChangePoints;
      config.m_tickSilenceFallbackMs=tickSilenceFallbackMs;
      config.m_enableFastPathDiagnostics=enableFastPathDiagnostics;
      config.m_fastPathDiagnosticIntervalMs=fastPathDiagnosticIntervalMs;
      config.m_enableFastPathNoBasketHeartbeat=enableFastPathNoBasketHeartbeat;
      return config;
     }
  };

#endif
