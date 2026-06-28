#ifndef BRE_DOMAIN_RECOVERY_CANDIDATE_AUDIT_MQH
#define BRE_DOMAIN_RECOVERY_CANDIDATE_AUDIT_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/RecoveryCandidateStatus.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/RecoveryCandidateReason.mqh>

class CRecoveryCandidateAudit
  {
private:
   CBasketId                         m_basketId;
   string                            m_strategyProfileHash;
   long                              m_basketVersion;
   string                            m_symbol;
   ENUM_BRE_TRADE_DIRECTION          m_direction;
   int                               m_recoveryStepIndex;
   double                            m_triggerReferencePrice;
   double                            m_bid;
   double                            m_ask;
   double                            m_zoneLow;
   double                            m_zoneHigh;
   double                            m_proposedVolume;
   double                            m_basketStopLoss;
   ulong                             m_quoteSequence;
   ENUM_BRE_RECOVERY_CANDIDATE_STATUS m_status;
   ENUM_BRE_RECOVERY_CANDIDATE_REASON m_reason;
   string                            m_idempotencyKey;
   datetime                          m_timestampUtc;

public:
                     CRecoveryCandidateAudit(void) {}

   CBasketId                         BasketId(void) const { return m_basketId; }
   string                            StrategyProfileHash(void) const { return m_strategyProfileHash; }
   long                              BasketVersion(void) const { return m_basketVersion; }
   string                            Symbol(void) const { return m_symbol; }
   ENUM_BRE_TRADE_DIRECTION          Direction(void) const { return m_direction; }
   int                               RecoveryStepIndex(void) const { return m_recoveryStepIndex; }
   double                            TriggerReferencePrice(void) const { return m_triggerReferencePrice; }
   double                            Bid(void) const { return m_bid; }
   double                            Ask(void) const { return m_ask; }
   double                            ZoneLow(void) const { return m_zoneLow; }
   double                            ZoneHigh(void) const { return m_zoneHigh; }
   double                            ProposedVolume(void) const { return m_proposedVolume; }
   double                            BasketStopLoss(void) const { return m_basketStopLoss; }
   ulong                             QuoteSequence(void) const { return m_quoteSequence; }
   ENUM_BRE_RECOVERY_CANDIDATE_STATUS Status(void) const { return m_status; }
   ENUM_BRE_RECOVERY_CANDIDATE_REASON Reason(void) const { return m_reason; }
   string                            IdempotencyKey(void) const { return m_idempotencyKey; }
   datetime                          TimestampUtc(void) const { return m_timestampUtc; }

   static CRecoveryCandidateAudit    Create(const CBasketId &basketId,
                                              const string strategyProfileHash,
                                              const long basketVersion,
                                              const string symbol,
                                              const ENUM_BRE_TRADE_DIRECTION direction,
                                              const int recoveryStepIndex,
                                              const double triggerReferencePrice,
                                              const double bid,
                                              const double ask,
                                              const double zoneLow,
                                              const double zoneHigh,
                                              const double proposedVolume,
                                              const double basketStopLoss,
                                              const ulong quoteSequence,
                                              const ENUM_BRE_RECOVERY_CANDIDATE_STATUS status,
                                              const ENUM_BRE_RECOVERY_CANDIDATE_REASON reason,
                                              const string idempotencyKey,
                                              const datetime timestampUtc)
     {
      CRecoveryCandidateAudit audit;
      audit.m_basketId=basketId;
      audit.m_strategyProfileHash=strategyProfileHash;
      audit.m_basketVersion=basketVersion;
      audit.m_symbol=symbol;
      audit.m_direction=direction;
      audit.m_recoveryStepIndex=recoveryStepIndex;
      audit.m_triggerReferencePrice=triggerReferencePrice;
      audit.m_bid=bid;
      audit.m_ask=ask;
      audit.m_zoneLow=zoneLow;
      audit.m_zoneHigh=zoneHigh;
      audit.m_proposedVolume=proposedVolume;
      audit.m_basketStopLoss=basketStopLoss;
      audit.m_quoteSequence=quoteSequence;
      audit.m_status=status;
      audit.m_reason=reason;
      audit.m_idempotencyKey=idempotencyKey;
      audit.m_timestampUtc=timestampUtc;
      return audit;
     }
  };

#endif
