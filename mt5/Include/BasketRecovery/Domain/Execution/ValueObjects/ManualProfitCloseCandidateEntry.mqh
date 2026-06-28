#ifndef BRE_DOMAIN_MANUAL_PROFIT_CLOSE_CANDIDATE_ENTRY_MQH
#define BRE_DOMAIN_MANUAL_PROFIT_CLOSE_CANDIDATE_ENTRY_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ProfitLevelTriggerType.mqh>
#include <BasketRecovery/Domain/Market/Enums/AccountPositionModel.mqh>
#include <BasketRecovery/Domain/Execution/Enums/ManualProfitCloseCandidateRegistryStatus.mqh>

class CManualProfitCloseCandidateEntry
  {
private:
   string                                        m_candidateId;
   string                                        m_executionRequestId;
   string                                        m_idempotencyKey;
   CBasketId                                     m_basketId;
   string                                        m_profitLevelId;
   int                                           m_profitLevelIndex;
   string                                        m_strategyProfileHash;
   long                                          m_basketVersion;
   string                                        m_symbol;
   ENUM_BRE_TRADE_DIRECTION                      m_basketDirection;
   ENUM_BRE_TRADE_DIRECTION                      m_positionDirection;
   ENUM_BRE_TRADE_DIRECTION                      m_closeDirection;
   ulong                                         m_positionTicket;
   double                                        m_originalPositionVolume;
   double                                        m_proposedCloseVolume;
   double                                        m_estimatedCloseMoney;
   ENUM_BRE_PROFIT_LEVEL_TRIGGER_TYPE            m_triggerType;
   double                                        m_triggerValue;
   ulong                                         m_quoteSequence;
   datetime                                      m_createdAtUtc;
   datetime                                      m_expiresAtUtc;
   ENUM_BRE_ACCOUNT_POSITION_MODEL               m_accountPositionModel;
   ENUM_BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_REGISTRY_STATUS m_status;

public:
                     CManualProfitCloseCandidateEntry(void)
     {
      m_profitLevelIndex=0;
      m_basketVersion=0;
      m_basketDirection=BRE_DIRECTION_NONE;
      m_positionDirection=BRE_DIRECTION_NONE;
      m_closeDirection=BRE_DIRECTION_NONE;
      m_positionTicket=0;
      m_originalPositionVolume=0.0;
      m_proposedCloseVolume=0.0;
      m_estimatedCloseMoney=0.0;
      m_triggerType=BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE;
      m_triggerValue=0.0;
      m_quoteSequence=0;
      m_createdAtUtc=0;
      m_expiresAtUtc=0;
      m_accountPositionModel=BRE_ACCOUNT_POSITION_MODEL_UNKNOWN;
      m_status=BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_AVAILABLE;
     }

   string            CandidateId(void) const { return m_candidateId; }
   string            ExecutionRequestId(void) const { return m_executionRequestId; }
   string            IdempotencyKey(void) const { return m_idempotencyKey; }
   CBasketId         BasketId(void) const { return m_basketId; }
   string            ProfitLevelId(void) const { return m_profitLevelId; }
   int               ProfitLevelIndex(void) const { return m_profitLevelIndex; }
   string            StrategyProfileHash(void) const { return m_strategyProfileHash; }
   long              BasketVersion(void) const { return m_basketVersion; }
   string            Symbol(void) const { return m_symbol; }
   ENUM_BRE_TRADE_DIRECTION BasketDirection(void) const { return m_basketDirection; }
   ENUM_BRE_TRADE_DIRECTION PositionDirection(void) const { return m_positionDirection; }
   ENUM_BRE_TRADE_DIRECTION CloseDirection(void) const { return m_closeDirection; }
   ulong             PositionTicket(void) const { return m_positionTicket; }
   double            OriginalPositionVolume(void) const { return m_originalPositionVolume; }
   double            ProposedCloseVolume(void) const { return m_proposedCloseVolume; }
   double            EstimatedCloseMoney(void) const { return m_estimatedCloseMoney; }
   ENUM_BRE_PROFIT_LEVEL_TRIGGER_TYPE TriggerType(void) const { return m_triggerType; }
   double            TriggerValue(void) const { return m_triggerValue; }
   ulong             QuoteSequence(void) const { return m_quoteSequence; }
   datetime          CreatedAtUtc(void) const { return m_createdAtUtc; }
   datetime          ExpiresAtUtc(void) const { return m_expiresAtUtc; }
   ENUM_BRE_ACCOUNT_POSITION_MODEL AccountPositionModel(void) const { return m_accountPositionModel; }
   ENUM_BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_REGISTRY_STATUS Status(void) const { return m_status; }

   bool              IsExpired(const datetime nowUtc) const
     {
      return m_expiresAtUtc>0 && nowUtc>=m_expiresAtUtc;
     }

   void              SetStatus(const ENUM_BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_REGISTRY_STATUS status) { m_status=status; }

   static ENUM_BRE_TRADE_DIRECTION CloseDirectionForPosition(const ENUM_BRE_TRADE_DIRECTION positionDirection)
     {
      if(positionDirection==BRE_DIRECTION_BUY)
         return BRE_DIRECTION_SELL;
      if(positionDirection==BRE_DIRECTION_SELL)
         return BRE_DIRECTION_BUY;
      return BRE_DIRECTION_NONE;
     }

   static CManualProfitCloseCandidateEntry Create(const string candidateId,
                                                  const string executionRequestId,
                                                  const string idempotencyKey,
                                                  const CBasketId &basketId,
                                                  const string profitLevelId,
                                                  const int profitLevelIndex,
                                                  const string strategyProfileHash,
                                                  const long basketVersion,
                                                  const string symbol,
                                                  const ENUM_BRE_TRADE_DIRECTION basketDirection,
                                                  const ENUM_BRE_TRADE_DIRECTION positionDirection,
                                                  const ulong positionTicket,
                                                  const double originalPositionVolume,
                                                  const double proposedCloseVolume,
                                                  const double estimatedCloseMoney,
                                                  const ENUM_BRE_PROFIT_LEVEL_TRIGGER_TYPE triggerType,
                                                  const double triggerValue,
                                                  const ulong quoteSequence,
                                                  const datetime createdAtUtc,
                                                  const datetime expiresAtUtc,
                                                  const ENUM_BRE_ACCOUNT_POSITION_MODEL accountPositionModel)
     {
      CManualProfitCloseCandidateEntry entry;
      entry.m_candidateId=candidateId;
      entry.m_executionRequestId=executionRequestId;
      entry.m_idempotencyKey=idempotencyKey;
      entry.m_basketId=basketId;
      entry.m_profitLevelId=profitLevelId;
      entry.m_profitLevelIndex=profitLevelIndex;
      entry.m_strategyProfileHash=strategyProfileHash;
      entry.m_basketVersion=basketVersion;
      entry.m_symbol=symbol;
      entry.m_basketDirection=basketDirection;
      entry.m_positionDirection=positionDirection;
      entry.m_closeDirection=CloseDirectionForPosition(positionDirection);
      entry.m_positionTicket=positionTicket;
      entry.m_originalPositionVolume=originalPositionVolume;
      entry.m_proposedCloseVolume=proposedCloseVolume;
      entry.m_estimatedCloseMoney=estimatedCloseMoney;
      entry.m_triggerType=triggerType;
      entry.m_triggerValue=triggerValue;
      entry.m_quoteSequence=quoteSequence;
      entry.m_createdAtUtc=createdAtUtc;
      entry.m_expiresAtUtc=expiresAtUtc;
      entry.m_accountPositionModel=accountPositionModel;
      entry.m_status=BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_AVAILABLE;
      return entry;
     }
  };

#endif
