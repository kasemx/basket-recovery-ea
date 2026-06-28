#ifndef BRE_DOMAIN_PROFIT_LEVEL_CLOSE_CANDIDATE_DOMAIN_EVENT_MQH
#define BRE_DOMAIN_PROFIT_LEVEL_CLOSE_CANDIDATE_DOMAIN_EVENT_MQH

#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevelCloseAudit.mqh>

class CProfitLevelCloseCandidateDomainEvent : public CDomainEvent
  {
private:
   CProfitLevelCloseAudit m_audit;
   ulong                  m_quoteSequence;

public:
                     CProfitLevelCloseCandidateDomainEvent(void)
     {
      m_quoteSequence=0;
     }

   CProfitLevelCloseAudit Audit(void) const { return m_audit; }
   ulong                  QuoteSequence(void) const { return m_quoteSequence; }

   static CProfitLevelCloseCandidateDomainEvent Create(const ENUM_BRE_EVENT_TYPE eventType,
                                                       const CBasketId &basketId,
                                                       const string correlationId,
                                                       const datetime occurredAt,
                                                       const CProfitLevelCloseAudit &audit,
                                                       const ulong quoteSequence)
     {
      CProfitLevelCloseCandidateDomainEvent event;
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
