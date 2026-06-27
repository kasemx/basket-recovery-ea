#ifndef BRE_DOMAIN_POSITION_MISMATCH_REPORT_MQH
#define BRE_DOMAIN_POSITION_MISMATCH_REPORT_MQH

#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>

class CPositionMismatchReport
  {
private:
   CPositionSnapshotEntry m_localEntry;
   CPositionSnapshotEntry m_brokerEntry;
   string                 m_reason;

public:
                     CPositionMismatchReport(void) {}

   CPositionSnapshotEntry LocalEntry(void) const { return m_localEntry; }
   CPositionSnapshotEntry BrokerEntry(void) const { return m_brokerEntry; }
   string                 Reason(void) const { return m_reason; }

   static CPositionMismatchReport Create(const CPositionSnapshotEntry &localEntry,
                                         const CPositionSnapshotEntry &brokerEntry,
                                         const string reason)
     {
      CPositionMismatchReport report;
      report.m_localEntry=localEntry;
      report.m_brokerEntry=brokerEntry;
      report.m_reason=reason;
      return report;
     }
  };

#endif
