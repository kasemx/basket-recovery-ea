#ifndef BRE_APP_SYSTEM_HEALTH_CHECK_SERVICE_MQH
#define BRE_APP_SYSTEM_HEALTH_CHECK_SERVICE_MQH

#include <BasketRecovery/Application/FastPath/InMemoryHotPathDiagnostics.mqh>

class CSystemHealthCheckService
  {
private:
   CInMemoryHotPathDiagnostics *m_diagnostics;
   int                          m_intervalMs;
   ulong                        m_lastRunTickMs;
   bool                         m_lastHealthy;

public:
                     CSystemHealthCheckService(CInMemoryHotPathDiagnostics *diagnostics,
                                               const int intervalMs=60000)
     {
      m_diagnostics=diagnostics;
      m_intervalMs=intervalMs;
      m_lastRunTickMs=0;
      m_lastHealthy=true;
     }

   bool              LastHealthy(void) const { return m_lastHealthy; }

   bool              RunIfDue(void)
     {
      if(m_intervalMs<=0)
         return m_lastHealthy;

      ulong now=GetTickCount64();
      if((now-m_lastRunTickMs)<(ulong)m_intervalMs)
         return m_lastHealthy;

      m_lastRunTickMs=now;
      m_lastHealthy=true;
      if(m_diagnostics!=NULL && m_diagnostics.LastDurationMs()>500)
         m_lastHealthy=false;

      return m_lastHealthy;
     }
  };

#endif
