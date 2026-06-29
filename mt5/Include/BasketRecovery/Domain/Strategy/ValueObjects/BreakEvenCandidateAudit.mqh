#ifndef BRE_DOMAIN_BREAK_EVEN_CANDIDATE_AUDIT_MQH
#define BRE_DOMAIN_BREAK_EVEN_CANDIDATE_AUDIT_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/BreakEvenCandidateTriggerType.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/BreakEvenCandidateStatus.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/BreakEvenReason.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/BreakEvenProgressState.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenPriceCalculation.mqh>

class CBreakEvenCandidateAudit
  {
private:
   CBasketId                               m_basketId;
   string                                  m_strategyProfileHash;
   long                                    m_basketVersion;
   string                                  m_ruleId;
   ENUM_BRE_BREAK_EVEN_CANDIDATE_TRIGGER_TYPE m_triggerType;
   double                                  m_triggerValue;
   double                                  m_weightedAverageEntry;
   double                                  m_totalActiveVolume;
   double                                  m_currentBid;
   double                                  m_currentAsk;
   CBreakEvenPriceCalculation              m_priceCalculation;
   double                                  m_currentBasketStopLoss;
   ENUM_BRE_TRADE_DIRECTION                m_direction;
   ulong                                   m_quoteSequence;
   bool                                    m_recoveryDisableRecommended;
   bool                                    m_lockRecommended;
   bool                                    m_trailingHandoffPlaceholder;
   string                                  m_idempotencyKey;
   datetime                                m_timestampUtc;
   ENUM_BRE_BREAK_EVEN_CANDIDATE_STATUS    m_status;
   ENUM_BRE_BREAK_EVEN_REASON              m_reason;
   ENUM_BRE_BREAK_EVEN_PROGRESS_STATE      m_progressState;

public:
                     CBreakEvenCandidateAudit(void)
     {
      m_basketVersion=0;
      m_triggerType=BRE_BE_CANDIDATE_TRIGGER_NONE;
      m_triggerValue=0.0;
      m_weightedAverageEntry=0.0;
      m_totalActiveVolume=0.0;
      m_currentBid=0.0;
      m_currentAsk=0.0;
      m_currentBasketStopLoss=0.0;
      m_direction=BRE_DIRECTION_NONE;
      m_quoteSequence=0;
      m_recoveryDisableRecommended=false;
      m_lockRecommended=false;
      m_trailingHandoffPlaceholder=false;
      m_timestampUtc=0;
      m_status=BRE_BREAK_EVEN_CANDIDATE_NOT_REACHED;
      m_reason=BRE_BREAK_EVEN_REASON_NONE;
      m_progressState=BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED;
     }

   CBasketId                               BasketId(void) const { return m_basketId; }
   string                                  StrategyProfileHash(void) const { return m_strategyProfileHash; }
   long                                    BasketVersion(void) const { return m_basketVersion; }
   string                                  RuleId(void) const { return m_ruleId; }
   ENUM_BRE_BREAK_EVEN_CANDIDATE_TRIGGER_TYPE TriggerType(void) const { return m_triggerType; }
   double                                  TriggerValue(void) const { return m_triggerValue; }
   double                                  WeightedAverageEntry(void) const { return m_weightedAverageEntry; }
   double                                  TotalActiveVolume(void) const { return m_totalActiveVolume; }
   double                                  CurrentBid(void) const { return m_currentBid; }
   double                                  CurrentAsk(void) const { return m_currentAsk; }
   CBreakEvenPriceCalculation              PriceCalculation(void) const { return m_priceCalculation; }
   double                                  ProposedStopLoss(void) const { return m_priceCalculation.NormalizedStopLoss(); }
   double                                  CurrentBasketStopLoss(void) const { return m_currentBasketStopLoss; }
   ENUM_BRE_TRADE_DIRECTION                Direction(void) const { return m_direction; }
   ulong                                   QuoteSequence(void) const { return m_quoteSequence; }
   bool                                    RecoveryDisableRecommended(void) const { return m_recoveryDisableRecommended; }
   bool                                    LockRecommended(void) const { return m_lockRecommended; }
   bool                                    TrailingHandoffPlaceholder(void) const { return m_trailingHandoffPlaceholder; }
   string                                  IdempotencyKey(void) const { return m_idempotencyKey; }
   datetime                                TimestampUtc(void) const { return m_timestampUtc; }
   ENUM_BRE_BREAK_EVEN_CANDIDATE_STATUS    Status(void) const { return m_status; }
   ENUM_BRE_BREAK_EVEN_REASON              Reason(void) const { return m_reason; }
   ENUM_BRE_BREAK_EVEN_PROGRESS_STATE      ProgressState(void) const { return m_progressState; }

   static CBreakEvenCandidateAudit         Create(const CBasketId &basketId,
                                                  const string strategyProfileHash,
                                                  const long basketVersion,
                                                  const string ruleId,
                                                  const ENUM_BRE_BREAK_EVEN_CANDIDATE_TRIGGER_TYPE triggerType,
                                                  const double triggerValue,
                                                  const double weightedAverageEntry,
                                                  const double totalActiveVolume,
                                                  const double currentBid,
                                                  const double currentAsk,
                                                  const CBreakEvenPriceCalculation &priceCalculation,
                                                  const double currentBasketStopLoss,
                                                  const ENUM_BRE_TRADE_DIRECTION direction,
                                                  const ulong quoteSequence,
                                                  const bool recoveryDisableRecommended,
                                                  const bool lockRecommended,
                                                  const bool trailingHandoffPlaceholder,
                                                  const string idempotencyKey,
                                                  const datetime timestampUtc,
                                                  const ENUM_BRE_BREAK_EVEN_CANDIDATE_STATUS status,
                                                  const ENUM_BRE_BREAK_EVEN_REASON reason,
                                                  const ENUM_BRE_BREAK_EVEN_PROGRESS_STATE progressState)
     {
      CBreakEvenCandidateAudit audit;
      audit.m_basketId=basketId;
      audit.m_strategyProfileHash=strategyProfileHash;
      audit.m_basketVersion=basketVersion;
      audit.m_ruleId=ruleId;
      audit.m_triggerType=triggerType;
      audit.m_triggerValue=triggerValue;
      audit.m_weightedAverageEntry=weightedAverageEntry;
      audit.m_totalActiveVolume=totalActiveVolume;
      audit.m_currentBid=currentBid;
      audit.m_currentAsk=currentAsk;
      audit.m_priceCalculation=priceCalculation;
      audit.m_currentBasketStopLoss=currentBasketStopLoss;
      audit.m_direction=direction;
      audit.m_quoteSequence=quoteSequence;
      audit.m_recoveryDisableRecommended=recoveryDisableRecommended;
      audit.m_lockRecommended=lockRecommended;
      audit.m_trailingHandoffPlaceholder=trailingHandoffPlaceholder;
      audit.m_idempotencyKey=idempotencyKey;
      audit.m_timestampUtc=timestampUtc;
      audit.m_status=status;
      audit.m_reason=reason;
      audit.m_progressState=progressState;
      return audit;
     }
  };

#endif
