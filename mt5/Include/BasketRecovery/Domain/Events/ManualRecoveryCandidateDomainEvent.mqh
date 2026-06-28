#ifndef BRE_DOMAIN_MANUAL_RECOVERY_CANDIDATE_DOMAIN_EVENT_MQH
#define BRE_DOMAIN_MANUAL_RECOVERY_CANDIDATE_DOMAIN_EVENT_MQH

#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualRecoveryCandidateEntry.mqh>

class CManualRecoveryCandidateDomainEvent : public CDomainEvent
  {
private:
   string                        m_candidateId;
   string                        m_executionRequestId;
   string                        m_detail;

public:
   string                        CandidateId(void) const { return m_candidateId; }
   string                        ExecutionRequestId(void) const { return m_executionRequestId; }
   string                        Detail(void) const { return m_detail; }

   static CManualRecoveryCandidateDomainEvent Create(const ENUM_BRE_EVENT_TYPE eventType,
                                                     const CBasketId &basketId,
                                                     const string correlationId,
                                                     const datetime occurredAt,
                                                     const string candidateId,
                                                     const string executionRequestId,
                                                     const string detail)
     {
      CManualRecoveryCandidateDomainEvent event;
      event.SetEventType(eventType);
      event.SetBasketId(basketId);
      event.SetCorrelationId(correlationId);
      event.SetOccurredAt(occurredAt);
      event.m_candidateId=candidateId;
      event.m_executionRequestId=executionRequestId;
      event.m_detail=detail;
      return event;
     }
  };

#endif
