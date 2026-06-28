#ifndef BRE_DOMAIN_RECOVERY_RISK_DECISION_AUDIT_MQH
#define BRE_DOMAIN_RECOVERY_RISK_DECISION_AUDIT_MQH

#include <BasketRecovery/Domain/Risk/Enums/RecoveryRiskBlockReason.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>

class CRecoveryRiskDecisionAudit
  {
private:
   CBasketId                         m_basketId;
   string                            m_strategyDecisionId;
   ENUM_BRE_TRADE_DIRECTION          m_proposedDirection;
   double                            m_proposedVolume;
   double                            m_proposedEntryPrice;
   double                            m_basketStopLoss;
   double                            m_currentSlRisk;
   double                            m_projectedSlRisk;
   double                            m_targetRisk;
   double                            m_maxRisk;
   double                            m_maxRiskRemaining;
   bool                              m_allowed;
   ENUM_BRE_RECOVERY_RISK_BLOCK_REASON m_blockReason;
   string                            m_strategyProfileHash;
   long                              m_basketVersion;
   datetime                          m_timestampUtc;

public:
                     CRecoveryRiskDecisionAudit(void)
     {
      m_proposedDirection=BRE_DIRECTION_NONE;
      m_proposedVolume=0.0;
      m_proposedEntryPrice=0.0;
      m_basketStopLoss=0.0;
      m_currentSlRisk=0.0;
      m_projectedSlRisk=0.0;
      m_targetRisk=0.0;
      m_maxRisk=0.0;
      m_maxRiskRemaining=0.0;
      m_allowed=false;
      m_blockReason=BRE_RECOVERY_RISK_BLOCK_NONE;
      m_basketVersion=0;
      m_timestampUtc=0;
     }

   CBasketId         BasketId(void) const { return m_basketId; }
   string            StrategyDecisionId(void) const { return m_strategyDecisionId; }
   ENUM_BRE_TRADE_DIRECTION ProposedDirection(void) const { return m_proposedDirection; }
   double            ProposedVolume(void) const { return m_proposedVolume; }
   double            ProposedEntryPrice(void) const { return m_proposedEntryPrice; }
   double            BasketStopLoss(void) const { return m_basketStopLoss; }
   double            CurrentSlRisk(void) const { return m_currentSlRisk; }
   double            ProjectedSlRisk(void) const { return m_projectedSlRisk; }
   double            TargetRisk(void) const { return m_targetRisk; }
   double            MaxRisk(void) const { return m_maxRisk; }
   double            MaxRiskRemaining(void) const { return m_maxRiskRemaining; }
   bool              Allowed(void) const { return m_allowed; }
   ENUM_BRE_RECOVERY_RISK_BLOCK_REASON BlockReason(void) const { return m_blockReason; }
   string            StrategyProfileHash(void) const { return m_strategyProfileHash; }
   long              BasketVersion(void) const { return m_basketVersion; }
   datetime          TimestampUtc(void) const { return m_timestampUtc; }

   static CRecoveryRiskDecisionAudit Create(const CBasketId &basketId,
                                            const string strategyDecisionId,
                                            const ENUM_BRE_TRADE_DIRECTION proposedDirection,
                                            const double proposedVolume,
                                            const double proposedEntryPrice,
                                            const double basketStopLoss,
                                            const double currentSlRisk,
                                            const double projectedSlRisk,
                                            const double targetRisk,
                                            const double maxRisk,
                                            const double maxRiskRemaining,
                                            const bool allowed,
                                            const ENUM_BRE_RECOVERY_RISK_BLOCK_REASON blockReason,
                                            const string strategyProfileHash,
                                            const long basketVersion,
                                            const datetime timestampUtc)
     {
      CRecoveryRiskDecisionAudit audit;
      audit.m_basketId=basketId;
      audit.m_strategyDecisionId=strategyDecisionId;
      audit.m_proposedDirection=proposedDirection;
      audit.m_proposedVolume=proposedVolume;
      audit.m_proposedEntryPrice=proposedEntryPrice;
      audit.m_basketStopLoss=basketStopLoss;
      audit.m_currentSlRisk=currentSlRisk;
      audit.m_projectedSlRisk=projectedSlRisk;
      audit.m_targetRisk=targetRisk;
      audit.m_maxRisk=maxRisk;
      audit.m_maxRiskRemaining=maxRiskRemaining;
      audit.m_allowed=allowed;
      audit.m_blockReason=blockReason;
      audit.m_strategyProfileHash=strategyProfileHash;
      audit.m_basketVersion=basketVersion;
      audit.m_timestampUtc=timestampUtc;
      return audit;
     }
  };

#endif
