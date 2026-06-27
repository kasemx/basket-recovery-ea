#ifndef BRE_APP_IN_MEMORY_HOT_PATH_DIAGNOSTICS_MQH
#define BRE_APP_IN_MEMORY_HOT_PATH_DIAGNOSTICS_MQH

class CInMemoryHotPathDiagnostics
  {
private:
   ulong  m_lastDurationMs;
   int    m_lastEvaluations;
   int    m_lastDeferred;
   int    m_lastSkipped;
   string m_lastSymbol;

public:
                     CInMemoryHotPathDiagnostics(void)
     {
      m_lastDurationMs=0;
      m_lastEvaluations=0;
      m_lastDeferred=0;
      m_lastSkipped=0;
      m_lastSymbol="";
     }

   void              RecordTickRun(const string symbol,
                                   const ulong startMsc,
                                   const int evaluations,
                                   const int deferred,
                                   const int skipped)
     {
      m_lastSymbol=symbol;
      m_lastEvaluations=evaluations;
      m_lastDeferred=deferred;
      m_lastSkipped=skipped;
      ulong endMsc=GetTickCount64();
      m_lastDurationMs=(endMsc>startMsc) ? (endMsc-startMsc) : 0;
     }

   ulong             LastDurationMs(void) const { return m_lastDurationMs; }
   int               LastEvaluations(void) const { return m_lastEvaluations; }
   int               LastDeferred(void) const { return m_lastDeferred; }
   int               LastSkipped(void) const { return m_lastSkipped; }
   string            LastSymbol(void) const { return m_lastSymbol; }
  };

#endif
