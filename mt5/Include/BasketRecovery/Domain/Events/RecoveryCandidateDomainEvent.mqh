#ifndef BRE_DOMAIN_RECOVERY_CANDIDATE_DOMAIN_EVENT_MQH
#define BRE_DOMAIN_RECOVERY_CANDIDATE_DOMAIN_EVENT_MQH

#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryCandidateAudit.mqh>

class CRecoveryCandidateDomainEvent : public CDomainEvent
  {
private:
   CRecoveryCandidateAudit           m_audit;
   ulong                             m_quoteSequence;

public:
                     CRecoveryCandidateDomainEvent(void)
     {
      m_quoteSequence=0;
     }

   CRecoveryCandidateAudit           Audit(void) const { return m_audit; }
   ulong                             QuoteSequence(void) const { return m_quoteSequence; }

   static CRecoveryCandidateDomainEvent Create(const ENUM_BRE_EVENT_TYPE eventType,
                                               const CBasketId &basketId,
                                               const string correlationId,
                                               const datetime occurredAt,
                                               const CRecoveryCandidateAudit &audit,
                                               const ulong quoteSequence)
     {
      CRecoveryCandidateDomainEvent event;
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
