#ifndef BASKET_RECOVERY_DOMAIN_AUDIT_RECORD_MQH
#define BASKET_RECOVERY_DOMAIN_AUDIT_RECORD_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

class CAuditRecord
  {
private:
   CCommandId m_commandId;
   CEventId   m_eventId;
   CUtcTime   m_timestampUtc;
   long       m_version;

public:
                     CAuditRecord(void)
     {
      m_version=0;
     }

   CCommandId        CommandId(void) const { return m_commandId; }
   CEventId          EventId(void) const { return m_eventId; }
   CUtcTime          TimestampUtc(void) const { return m_timestampUtc; }
   long              Version(void) const { return m_version; }

   void              SetCommandId(const CCommandId &value) { m_commandId=value; }
   void              SetEventId(const CEventId &value) { m_eventId=value; }
   void              SetTimestampUtc(const CUtcTime &value) { m_timestampUtc=value; }
   void              SetVersion(const long value) { m_version=value; }
  };

#endif
