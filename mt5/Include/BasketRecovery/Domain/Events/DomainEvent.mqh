#ifndef BASKET_RECOVERY_DOMAIN_DOMAIN_EVENT_MQH
#define BASKET_RECOVERY_DOMAIN_DOMAIN_EVENT_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/EventType.mqh>

class CDomainEvent
  {
protected:
   ENUM_BRE_EVENT_TYPE m_eventType;
   CBasketId           m_basketId;
   datetime            m_occurredAt;
   string              m_correlationId;

public:
                     CDomainEvent(void)
     {
      m_eventType=BRE_EVENT_NONE;
      m_occurredAt=0;
      m_correlationId="";
     }

   virtual          ~CDomainEvent(void) {}

   ENUM_BRE_EVENT_TYPE EventType(void) const { return m_eventType; }
   CBasketId         BasketId(void) const { return m_basketId; }
   datetime          OccurredAt(void) const { return m_occurredAt; }
   string            CorrelationId(void) const { return m_correlationId; }

   void              SetEventType(const ENUM_BRE_EVENT_TYPE value) { m_eventType=value; }
   void              SetBasketId(const CBasketId &value) { m_basketId=value; }
   void              SetOccurredAt(const datetime value) { m_occurredAt=value; }
   void              SetCorrelationId(const string value) { m_correlationId=value; }
  };

#endif
