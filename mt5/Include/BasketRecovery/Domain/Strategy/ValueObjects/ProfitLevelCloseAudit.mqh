#ifndef BRE_DOMAIN_PROFIT_LEVEL_CLOSE_AUDIT_MQH
#define BRE_DOMAIN_PROFIT_LEVEL_CLOSE_AUDIT_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ProfitLevelTriggerType.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ProfitLevelCloseCandidateStatus.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ProfitLevelCloseReason.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ProfitLevelProgressState.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/CloseMode.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/PositionReductionInstruction.mqh>

class CProfitLevelCloseAudit
  {
private:
   CBasketId                               m_basketId;
   string                                  m_strategyProfileHash;
   long                                    m_basketVersion;
   string                                  m_profitLevelId;
   int                                     m_profitLevelIndex;
   ENUM_BRE_PROFIT_LEVEL_TRIGGER_TYPE      m_triggerType;
   double                                  m_triggerValue;
   double                                  m_evaluatedFloatingProfitUsd;
   double                                  m_targetClosePercent;
   double                                  m_targetCloseMoney;
   CPositionReductionInstruction           m_reductions[];
   ENUM_BRE_CLOSE_MODE                     m_closeMode;
   ulong                                   m_quoteSequence;
   string                                  m_idempotencyKey;
   datetime                                m_timestampUtc;
   ENUM_BRE_PROFIT_LEVEL_CLOSE_CANDIDATE_STATUS m_status;
   ENUM_BRE_PROFIT_LEVEL_CLOSE_REASON      m_reason;
   ENUM_BRE_PROFIT_LEVEL_PROGRESS_STATE    m_progressState;
   bool                                    m_minimumVolumeOverrun;

public:
                     CProfitLevelCloseAudit(void)
     {
      m_basketVersion=0;
      m_profitLevelIndex=0;
      m_triggerType=BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE;
      m_triggerValue=0.0;
      m_evaluatedFloatingProfitUsd=0.0;
      m_targetClosePercent=0.0;
      m_targetCloseMoney=0.0;
      m_closeMode=BRE_CLOSE_MODE_NONE;
      m_quoteSequence=0;
      m_timestampUtc=0;
      m_status=BRE_PROFIT_LEVEL_CLOSE_NOT_REACHED;
      m_reason=BRE_PROFIT_LEVEL_CLOSE_REASON_NONE;
      m_progressState=BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED;
      m_minimumVolumeOverrun=false;
     }

   CBasketId                               BasketId(void) const { return m_basketId; }
   string                                  StrategyProfileHash(void) const { return m_strategyProfileHash; }
   long                                    BasketVersion(void) const { return m_basketVersion; }
   string                                  ProfitLevelId(void) const { return m_profitLevelId; }
   int                                     ProfitLevelIndex(void) const { return m_profitLevelIndex; }
   ENUM_BRE_PROFIT_LEVEL_TRIGGER_TYPE      TriggerType(void) const { return m_triggerType; }
   double                                  TriggerValue(void) const { return m_triggerValue; }
   double                                  EvaluatedFloatingProfitUsd(void) const { return m_evaluatedFloatingProfitUsd; }
   double                                  TargetClosePercent(void) const { return m_targetClosePercent; }
   double                                  TargetCloseMoney(void) const { return m_targetCloseMoney; }
   int                                     ReductionCount(void) const { return ArraySize(m_reductions); }
   ENUM_BRE_CLOSE_MODE                     CloseMode(void) const { return m_closeMode; }
   ulong                                   QuoteSequence(void) const { return m_quoteSequence; }
   string                                  IdempotencyKey(void) const { return m_idempotencyKey; }
   datetime                                TimestampUtc(void) const { return m_timestampUtc; }
   ENUM_BRE_PROFIT_LEVEL_CLOSE_CANDIDATE_STATUS Status(void) const { return m_status; }
   ENUM_BRE_PROFIT_LEVEL_CLOSE_REASON      Reason(void) const { return m_reason; }
   ENUM_BRE_PROFIT_LEVEL_PROGRESS_STATE    ProgressState(void) const { return m_progressState; }
   bool                                    MinimumVolumeOverrun(void) const { return m_minimumVolumeOverrun; }

   bool                                    ReductionAt(const int index,CPositionReductionInstruction &outInstruction) const
     {
      if(index<0 || index>=ArraySize(m_reductions))
         return false;
      outInstruction=m_reductions[index];
      return true;
     }

   static CProfitLevelCloseAudit           Create(const CBasketId &basketId,
                                                  const string strategyProfileHash,
                                                  const long basketVersion,
                                                  const string profitLevelId,
                                                  const int profitLevelIndex,
                                                  const ENUM_BRE_PROFIT_LEVEL_TRIGGER_TYPE triggerType,
                                                  const double triggerValue,
                                                  const double evaluatedFloatingProfitUsd,
                                                  const double targetClosePercent,
                                                  const double targetCloseMoney,
                                                  const CPositionReductionInstruction &reductions[],
                                                  const int reductionCount,
                                                  const ENUM_BRE_CLOSE_MODE closeMode,
                                                  const ulong quoteSequence,
                                                  const string idempotencyKey,
                                                  const datetime timestampUtc,
                                                  const ENUM_BRE_PROFIT_LEVEL_CLOSE_CANDIDATE_STATUS status,
                                                  const ENUM_BRE_PROFIT_LEVEL_CLOSE_REASON reason,
                                                  const ENUM_BRE_PROFIT_LEVEL_PROGRESS_STATE progressState,
                                                  const bool minimumVolumeOverrun)
     {
      CProfitLevelCloseAudit audit;
      audit.m_basketId=basketId;
      audit.m_strategyProfileHash=strategyProfileHash;
      audit.m_basketVersion=basketVersion;
      audit.m_profitLevelId=profitLevelId;
      audit.m_profitLevelIndex=profitLevelIndex;
      audit.m_triggerType=triggerType;
      audit.m_triggerValue=triggerValue;
      audit.m_evaluatedFloatingProfitUsd=evaluatedFloatingProfitUsd;
      audit.m_targetClosePercent=targetClosePercent;
      audit.m_targetCloseMoney=targetCloseMoney;
      ArrayResize(audit.m_reductions,reductionCount);
      for(int i=0;i<reductionCount;i++)
         audit.m_reductions[i]=reductions[i];
      audit.m_closeMode=closeMode;
      audit.m_quoteSequence=quoteSequence;
      audit.m_idempotencyKey=idempotencyKey;
      audit.m_timestampUtc=timestampUtc;
      audit.m_status=status;
      audit.m_reason=reason;
      audit.m_progressState=progressState;
      audit.m_minimumVolumeOverrun=minimumVolumeOverrun;
      return audit;
     }
  };

#endif
