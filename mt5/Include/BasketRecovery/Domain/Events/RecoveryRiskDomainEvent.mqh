#ifndef BRE_DOMAIN_RECOVERY_RISK_DOMAIN_EVENT_MQH
#define BRE_DOMAIN_RECOVERY_RISK_DOMAIN_EVENT_MQH

#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RecoveryRiskDecisionAudit.mqh>
#include <BasketRecovery/Domain/Risk/Enums/RecoveryRiskBlockReason.mqh>

class CRecoveryRiskDomainEvent : public CDomainEvent
  {
private:
   string                            m_strategyDecisionId;
   string                            m_idempotencyKey;
   ulong                             m_quoteSequence;
   ENUM_BRE_RECOVERY_RISK_BLOCK_REASON m_blockReason;
   CRecoveryRiskDecisionAudit        m_audit;

public:
                     CRecoveryRiskDomainEvent(void)
     {
      m_strategyDecisionId="";
      m_idempotencyKey="";
      m_quoteSequence=0;
      m_blockReason=BRE_RECOVERY_RISK_BLOCK_NONE;
     }

   string            StrategyDecisionId(void) const { return m_strategyDecisionId; }
   string            IdempotencyKey(void) const { return m_idempotencyKey; }
   ulong             QuoteSequence(void) const { return m_quoteSequence; }
   ENUM_BRE_RECOVERY_RISK_BLOCK_REASON BlockReason(void) const { return m_blockReason; }
   CRecoveryRiskDecisionAudit Audit(void) const { return m_audit; }

   void              SetStrategyDecisionId(const string value) { m_strategyDecisionId=value; }
   void              SetIdempotencyKey(const string value) { m_idempotencyKey=value; }
   void              SetQuoteSequence(const ulong value) { m_quoteSequence=value; }
   void              SetBlockReason(const ENUM_BRE_RECOVERY_RISK_BLOCK_REASON value) { m_blockReason=value; }
   void              SetAudit(const CRecoveryRiskDecisionAudit &value) { m_audit=value; }

   static CRecoveryRiskDomainEvent CreateValidated(const CBasketId &basketId,
                                                   const string correlationId,
                                                   const datetime occurredAt,
                                                   const CRecoveryRiskDecisionAudit &audit,
                                                   const ulong quoteSequence)
     {
      CRecoveryRiskDomainEvent event;
      event.SetEventType(BRE_EVENT_RECOVERY_RISK_VALIDATED);
      event.SetBasketId(basketId);
      event.SetCorrelationId(correlationId);
      event.SetOccurredAt(occurredAt);
      event.SetStrategyDecisionId(audit.StrategyDecisionId());
      event.SetIdempotencyKey(audit.StrategyDecisionId());
      event.SetQuoteSequence(quoteSequence);
      event.SetAudit(audit);
      return event;
     }

   static CRecoveryRiskDomainEvent CreateBlocked(const CBasketId &basketId,
                                                 const string correlationId,
                                                 const datetime occurredAt,
                                                 const CRecoveryRiskDecisionAudit &audit,
                                                 const ulong quoteSequence)
     {
      CRecoveryRiskDomainEvent event;
      event.SetEventType(BRE_EVENT_RECOVERY_BLOCKED_BY_RISK);
      event.SetBasketId(basketId);
      event.SetCorrelationId(correlationId);
      event.SetOccurredAt(occurredAt);
      event.SetStrategyDecisionId(audit.StrategyDecisionId());
      event.SetIdempotencyKey(audit.StrategyDecisionId());
      event.SetQuoteSequence(quoteSequence);
      event.SetBlockReason(audit.BlockReason());
      event.SetAudit(audit);
      return event;
     }

   static CRecoveryRiskDomainEvent CreateReductionSuggested(const CBasketId &basketId,
                                                            const string correlationId,
                                                            const datetime occurredAt,
                                                            const CRecoveryRiskDecisionAudit &audit,
                                                            const ulong quoteSequence)
     {
      CRecoveryRiskDomainEvent event;
      event.SetEventType(BRE_EVENT_RISK_REDUCTION_SUGGESTED);
      event.SetBasketId(basketId);
      event.SetCorrelationId(correlationId);
      event.SetOccurredAt(occurredAt);
      event.SetStrategyDecisionId(audit.StrategyDecisionId());
      event.SetIdempotencyKey(audit.StrategyDecisionId());
      event.SetQuoteSequence(quoteSequence);
      event.SetAudit(audit);
      return event;
     }
  };

#endif
