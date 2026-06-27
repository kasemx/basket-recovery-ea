#ifndef BASKET_RECOVERY_DOMAIN_BASKET_VERSION_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_VERSION_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

class CBasketVersion
  {
private:
   long        m_version;
   CCommandId  m_lastCommandId;
   CEventId    m_lastEventId;
   CUtcTime    m_lastModifiedUtc;

public:
                     CBasketVersion(void)
     {
      m_version=0;
     }

   long              Version(void) const { return m_version; }
   CCommandId        LastCommandId(void) const { return m_lastCommandId; }
   CEventId          LastEventId(void) const { return m_lastEventId; }
   CUtcTime          LastModifiedUtc(void) const { return m_lastModifiedUtc; }

   void              SetVersion(const long value) { m_version=value; }
   void              SetLastCommandId(const CCommandId &value) { m_lastCommandId=value; }
   void              SetLastEventId(const CEventId &value) { m_lastEventId=value; }
   void              SetLastModifiedUtc(const CUtcTime value) { m_lastModifiedUtc=value; }
  };

#endif
