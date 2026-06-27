#ifndef BRE_DOMAIN_MISSING_POSITION_REPORT_MQH
#define BRE_DOMAIN_MISSING_POSITION_REPORT_MQH

#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>

class CMissingPositionReport
  {
private:
   CPositionSnapshotEntry m_localEntry;

public:
                     CMissingPositionReport(void) {}

   CPositionSnapshotEntry LocalEntry(void) const { return m_localEntry; }

   static CMissingPositionReport Create(const CPositionSnapshotEntry &localEntry)
     {
      CMissingPositionReport report;
      report.m_localEntry=localEntry;
      return report;
     }
  };

#endif
