#ifndef BRE_DOMAIN_MANUAL_PROFIT_CLOSE_CANDIDATE_DOMAIN_EVENT_MQH
#define BRE_DOMAIN_MANUAL_PROFIT_CLOSE_CANDIDATE_DOMAIN_EVENT_MQH

#include <BasketRecovery/Domain/Events/DomainEvent.mqh>

class CManualProfitCloseCandidateDomainEvent : public CDomainEvent
  {
private:
   string m_candidateId;
   string m_executionRequestId;
   string m_profitLevelId;
   string m_detail;

public:
   string            CandidateId(void) const { return m_candidateId; }
   string            ExecutionRequestId(void) const { return m_executionRequestId; }
   string            ProfitLevelId(void) const { return m_profitLevelId; }
   string            Detail(void) const { return m_detail; }

   static CManualProfitCloseCandidateDomainEvent Create(const ENUM_BRE_EVENT_TYPE eventType,
                                                        const CBasketId &basketId,
                                                        const string correlationId,
                                                        const datetime occurredAt,
                                                        const string candidateId,
                                                        const string executionRequestId,
                                                        const string profitLevelId,
                                                        const string detail)
     {
      CManualProfitCloseCandidateDomainEvent event;
      event.SetEventType(eventType);
      event.SetBasketId(basketId);
      event.SetCorrelationId(correlationId);
      event.SetOccurredAt(occurredAt);
      event.m_candidateId=candidateId;
      event.m_executionRequestId=executionRequestId;
      event.m_profitLevelId=profitLevelId;
      event.m_detail=detail;
      return event;
     }
  };

#endif
