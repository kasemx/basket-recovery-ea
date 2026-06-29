#ifndef BRE_DOMAIN_BREAK_EVEN_CANDIDATE_DOMAIN_EVENT_MQH
#define BRE_DOMAIN_BREAK_EVEN_CANDIDATE_DOMAIN_EVENT_MQH

#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenCandidateAudit.mqh>

class CBreakEvenCandidateDomainEvent : public CDomainEvent
  {
private:
   CBreakEvenCandidateAudit m_audit;
   ulong                    m_quoteSequence;

public:
                     CBreakEvenCandidateDomainEvent(void)
     {
      m_quoteSequence=0;
     }

   CBreakEvenCandidateAudit Audit(void) const { return m_audit; }
   ulong                    QuoteSequence(void) const { return m_quoteSequence; }

   static CBreakEvenCandidateDomainEvent Create(const ENUM_BRE_EVENT_TYPE eventType,
                                                const CBasketId &basketId,
                                                const string correlationId,
                                                const datetime occurredAt,
                                                const CBreakEvenCandidateAudit &audit,
                                                const ulong quoteSequence)
     {
      CBreakEvenCandidateDomainEvent event;
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
