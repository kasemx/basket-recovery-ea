#ifndef BRE_DOMAIN_BREAK_EVEN_MODIFICATION_DOMAIN_EVENT_MQH
#define BRE_DOMAIN_BREAK_EVEN_MODIFICATION_DOMAIN_EVENT_MQH

#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenModificationAudit.mqh>

class CBreakEvenModificationDomainEvent : public CDomainEvent
  {
private:
   CBreakEvenModificationAudit m_audit;
   ulong                       m_quoteSequence;

public:
                     CBreakEvenModificationDomainEvent(void)
     {
      m_quoteSequence=0;
     }

   CBreakEvenModificationAudit Audit(void) const { return m_audit; }
   ulong                       QuoteSequence(void) const { return m_quoteSequence; }

   static CBreakEvenModificationDomainEvent Create(const ENUM_BRE_EVENT_TYPE eventType,
                                                   const CBasketId &basketId,
                                                   const string correlationId,
                                                   const datetime occurredAt,
                                                   const CBreakEvenModificationAudit &audit,
                                                   const ulong quoteSequence)
     {
      CBreakEvenModificationDomainEvent event;
      event.SetEventType(eventType);
      event.SetBasketId(basketId);
      event.SetCorrelationId(correlationId);
      event.SetOccurredAt(occurredAt);
      event.m_audit=audit;
      event.m_quoteSequence=quoteSequence;
      return event;
     }
  };

#endif
