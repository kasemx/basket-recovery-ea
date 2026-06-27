#ifndef BRE_DOMAIN_ORPHAN_POSITION_REPORT_MQH
#define BRE_DOMAIN_ORPHAN_POSITION_REPORT_MQH

#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>

class COrphanPositionReport
  {
private:
   CPositionSnapshotEntry m_brokerEntry;

public:
                     COrphanPositionReport(void) {}

   CPositionSnapshotEntry BrokerEntry(void) const { return m_brokerEntry; }

   static COrphanPositionReport Create(const CPositionSnapshotEntry &brokerEntry)
     {
      COrphanPositionReport report;
      report.m_brokerEntry=brokerEntry;
      return report;
     }
  };

#endif
