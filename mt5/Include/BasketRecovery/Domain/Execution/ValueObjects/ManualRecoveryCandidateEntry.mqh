#ifndef BRE_DOMAIN_MANUAL_RECOVERY_CANDIDATE_ENTRY_MQH
#define BRE_DOMAIN_MANUAL_RECOVERY_CANDIDATE_ENTRY_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Execution/Enums/ManualRecoveryCandidateRegistryStatus.mqh>

class CManualRecoveryCandidateEntry
  {
private:
   string                                        m_candidateId;
   string                                        m_executionRequestId;
   string                                        m_strategyDecisionId;
   string                                        m_idempotencyKey;
   CBasketId                                     m_basketId;
   string                                        m_strategyProfileHash;
   long                                          m_basketVersion;
   string                                        m_symbol;
   ENUM_BRE_TRADE_DIRECTION                      m_direction;
   int                                           m_recoveryStepIndex;
   double                                        m_triggerReferencePrice;
   double                                        m_executableBid;
   double                                        m_executableAsk;
   double                                        m_zoneLow;
   double                                        m_zoneHigh;
   double                                        m_proposedVolume;
   double                                        m_basketStopLoss;
   double                                        m_currentSlRisk;
   double                                        m_projectedSlRisk;
   double                                        m_targetRisk;
   double                                        m_maxRisk;
   ulong                                         m_quoteSequence;
   datetime                                      m_createdAtUtc;
   datetime                                      m_expiresAtUtc;
   ENUM_BRE_MANUAL_RECOVERY_CANDIDATE_REGISTRY_STATUS m_status;

public:
                     CManualRecoveryCandidateEntry(void)
     {
      m_basketVersion=0;
      m_direction=BRE_DIRECTION_NONE;
      m_recoveryStepIndex=0;
      m_triggerReferencePrice=0.0;
      m_executableBid=0.0;
      m_executableAsk=0.0;
      m_zoneLow=0.0;
      m_zoneHigh=0.0;
      m_proposedVolume=0.0;
      m_basketStopLoss=0.0;
      m_currentSlRisk=0.0;
      m_projectedSlRisk=0.0;
      m_targetRisk=0.0;
      m_maxRisk=0.0;
      m_quoteSequence=0;
      m_createdAtUtc=0;
      m_expiresAtUtc=0;
      m_status=BRE_MANUAL_RECOVERY_CANDIDATE_AVAILABLE;
     }

   string            CandidateId(void) const { return m_candidateId; }
   string            ExecutionRequestId(void) const { return m_executionRequestId; }
   string            StrategyDecisionId(void) const { return m_strategyDecisionId; }
   string            IdempotencyKey(void) const { return m_idempotencyKey; }
   CBasketId         BasketId(void) const { return m_basketId; }
   string            StrategyProfileHash(void) const { return m_strategyProfileHash; }
   long              BasketVersion(void) const { return m_basketVersion; }
   string            Symbol(void) const { return m_symbol; }
   ENUM_BRE_TRADE_DIRECTION Direction(void) const { return m_direction; }
   int               RecoveryStepIndex(void) const { return m_recoveryStepIndex; }
   double            TriggerReferencePrice(void) const { return m_triggerReferencePrice; }
   double            ExecutableBid(void) const { return m_executableBid; }
   double            ExecutableAsk(void) const { return m_executableAsk; }
   double            ZoneLow(void) const { return m_zoneLow; }
   double            ZoneHigh(void) const { return m_zoneHigh; }
   double            ProposedVolume(void) const { return m_proposedVolume; }
   double            BasketStopLoss(void) const { return m_basketStopLoss; }
   double            CurrentSlRisk(void) const { return m_currentSlRisk; }
   double            ProjectedSlRisk(void) const { return m_projectedSlRisk; }
   double            TargetRisk(void) const { return m_targetRisk; }
   double            MaxRisk(void) const { return m_maxRisk; }
   ulong             QuoteSequence(void) const { return m_quoteSequence; }
   datetime          CreatedAtUtc(void) const { return m_createdAtUtc; }
   datetime          ExpiresAtUtc(void) const { return m_expiresAtUtc; }
   ENUM_BRE_MANUAL_RECOVERY_CANDIDATE_REGISTRY_STATUS Status(void) const { return m_status; }

   double            ExecutablePrice(void) const
     {
      if(m_direction==BRE_DIRECTION_BUY)
         return m_executableAsk;
      if(m_direction==BRE_DIRECTION_SELL)
         return m_executableBid;
      return m_executableBid;
     }

   bool              IsExpired(const datetime nowUtc) const
     {
      return m_expiresAtUtc>0 && nowUtc>=m_expiresAtUtc;
     }

   void              SetStatus(const ENUM_BRE_MANUAL_RECOVERY_CANDIDATE_REGISTRY_STATUS status) { m_status=status; }

   static CManualRecoveryCandidateEntry Create(const string candidateId,
                                               const string executionRequestId,
                                               const string strategyDecisionId,
                                               const string idempotencyKey,
                                               const CBasketId &basketId,
                                               const string strategyProfileHash,
                                               const long basketVersion,
                                               const string symbol,
                                               const ENUM_BRE_TRADE_DIRECTION direction,
                                               const int recoveryStepIndex,
                                               const double triggerReferencePrice,
                                               const double executableBid,
                                               const double executableAsk,
                                               const double zoneLow,
                                               const double zoneHigh,
                                               const double proposedVolume,
                                               const double basketStopLoss,
                                               const double currentSlRisk,
                                               const double projectedSlRisk,
                                               const double targetRisk,
                                               const double maxRisk,
                                               const ulong quoteSequence,
                                               const datetime createdAtUtc,
                                               const datetime expiresAtUtc)
     {
      CManualRecoveryCandidateEntry entry;
      entry.m_candidateId=candidateId;
      entry.m_executionRequestId=executionRequestId;
      entry.m_strategyDecisionId=strategyDecisionId;
      entry.m_idempotencyKey=idempotencyKey;
      entry.m_basketId=basketId;
      entry.m_strategyProfileHash=strategyProfileHash;
      entry.m_basketVersion=basketVersion;
      entry.m_symbol=symbol;
      entry.m_direction=direction;
      entry.m_recoveryStepIndex=recoveryStepIndex;
      entry.m_triggerReferencePrice=triggerReferencePrice;
      entry.m_executableBid=executableBid;
      entry.m_executableAsk=executableAsk;
      entry.m_zoneLow=zoneLow;
      entry.m_zoneHigh=zoneHigh;
      entry.m_proposedVolume=proposedVolume;
      entry.m_basketStopLoss=basketStopLoss;
      entry.m_currentSlRisk=currentSlRisk;
      entry.m_projectedSlRisk=projectedSlRisk;
      entry.m_targetRisk=targetRisk;
      entry.m_maxRisk=maxRisk;
      entry.m_quoteSequence=quoteSequence;
      entry.m_createdAtUtc=createdAtUtc;
      entry.m_expiresAtUtc=expiresAtUtc;
      entry.m_status=BRE_MANUAL_RECOVERY_CANDIDATE_AVAILABLE;
      return entry;
     }
  };

#endif
