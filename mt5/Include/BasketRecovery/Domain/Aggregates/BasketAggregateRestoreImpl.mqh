#ifndef BASKET_RECOVERY_DOMAIN_BASKET_AGGREGATE_RESTORE_IMPL_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_AGGREGATE_RESTORE_IMPL_MQH

bool CBasketAggregate::RestoreFromDto(const CBasketPersistenceDto &dto)
  {
   return CBasketAggregateRestorer::Restore(*this,dto);
  }

void CBasketAggregate::ClearForRestore(void)
  {
   for(int i=0;i<m_positionSnapshotCount;i++)
     {
      if(m_positionSnapshots[i]!=NULL)
        {
         delete m_positionSnapshots[i];
         m_positionSnapshots[i]=NULL;
        }
     }
   m_positionSnapshotCount=0;
   m_commandHistoryCount=0;
   m_eventHistoryCount=0;
   ArrayResize(m_positionSnapshots,0);
   ArrayResize(m_commandHistory,0);
   ArrayResize(m_eventHistory,0);
   m_creationBindingOpen=false;
  }

void CBasketAggregate::SetIdentity(const CBasketId &id,const string correlationKey,
                                   const ENUM_BRE_TRADE_DIRECTION direction,const string symbol)
  {
   m_id=id;
   m_correlationKey=correlationKey;
   m_direction=direction;
   m_symbol=symbol;
  }

void CBasketAggregate::SetModeFlagsFromDto(const CBasketPersistenceDto &dto)
  {
   m_modeFlags.SetRecoveryActive(dto.recoveryActive);
   m_modeFlags.SetRecoveryPermanentlyDisabled(dto.recoveryPermanentlyDisabled);
   m_modeFlags.SetBreakEvenActive(dto.breakEvenActive);
   m_modeFlags.SetTrailingActive(dto.trailingActive);
   m_modeFlags.SetLocked(dto.locked);
   m_modeFlags.SetRiskReductionActive(dto.riskReductionActive);
   m_modeFlags.SetMaxRiskLockout(dto.maxRiskLockout);
  }

void CBasketAggregate::SetLegacyProfileSnapshot(const bool hasSnapshot,const string profileName,
                                                const CRiskProfileConfig &risk,
                                                const CRecoveryProfileConfig &recovery,
                                                const CTakeProfitProfileConfig &takeProfit,
                                                const CBreakEvenProfileConfig &breakEven,
                                                const CExecutionProfileConfig &execution,
                                                const CUtcTime &boundAt)
  {
   m_hasProfileSnapshot=hasSnapshot;
   if(hasSnapshot)
      m_profileSnapshot=CProfileSnapshot::Create(profileName,risk,recovery,takeProfit,breakEven,execution,boundAt);
  }

void CBasketAggregate::RestoreStrategyBinding(const CStrategyProfileSnapshot &snapshot,
                                              const bool migrationRequired)
  {
   m_runtimeState.RestoreStrategyBinding(snapshot,migrationRequired);
  }

void CBasketAggregate::RestoreProfitLevels(const CBasketProfitLevelProgress &levels[],const int count)
  {
   m_runtimeState.RestoreProfitLevels(levels,count);
  }

void CBasketAggregate::RestoreExecutedBreakEvenRules(const string &ruleIds[])
  {
   m_runtimeState.RestoreExecutedBreakEvenRules(ruleIds,ArraySize(ruleIds));
  }

void CBasketAggregate::SetVersionState(const long version,const CCommandId &commandId,
                                       const CEventId &eventId,const CUtcTime &modifiedUtc)
  {
   m_versionState.SetVersion(version);
   m_versionState.SetLastCommandId(commandId);
   m_versionState.SetLastEventId(eventId);
   m_versionState.SetLastModifiedUtc(modifiedUtc);
  }

void CBasketAggregate::SetSignalFromDto(const CBasketPersistenceDto &dto)
  {
   m_signal.SetId(dto.signalId);
   m_signal.SetCorrelationKey(dto.signalCorrelationKey);
   m_signal.SetSequence(dto.signalSequence);
   m_signal.SetDirection(dto.signalDirection);
   m_signal.SetSymbol(dto.signalSymbol);
   m_signal.SetReceivedAt(dto.signalReceivedAt);
   m_signal.SetIsConsumed(dto.signalIsConsumed);
   CSignalDetails details;
   details.SetHasDetails(dto.signalDetails.hasDetails);
   details.SetRangeLow(CPrice(dto.signalDetails.rangeLow));
   details.SetRangeHigh(CPrice(dto.signalDetails.rangeHigh));
   details.SetStopLoss(CPrice(dto.signalDetails.stopLoss));
   details.SetTp1(CPrice(dto.signalDetails.tp1));
   details.SetTp2(CPrice(dto.signalDetails.tp2));
   details.SetTp3(CPrice(dto.signalDetails.tp3));
   details.SetTp4(CPrice(dto.signalDetails.tp4));
   details.SetTpOpen(dto.signalDetails.tpOpen);
   m_signal.SetDetails(details);
  }

void CBasketAggregate::SetMetadataFromDto(const CBasketPersistenceDto &dto)
  {
   m_metadata.SetCreatedAtUtc(dto.createdAtUtc);
   m_metadata.SetUpdatedAtUtc(dto.updatedAtUtc);
   m_metadata.SetRealizedProfit(dto.realizedProfit);
   m_metadata.SetCloseReason(dto.closeReason);
  }

void CBasketAggregate::SetPositionSnapshotsFromDto(const CBasketPersistenceDto &dto)
  {
   m_positionSnapshotCount=ArraySize(dto.positionSnapshots);
   ArrayResize(m_positionSnapshots,m_positionSnapshotCount);
   for(int i=0;i<m_positionSnapshotCount;i++)
     {
      m_positionSnapshots[i]=new CPositionSnapshot();
      m_positionSnapshots[i].SetBasketId(CBasketId(dto.positionSnapshots[i].basketId));
      m_positionSnapshots[i].SetVersion(dto.positionSnapshots[i].version);
      m_positionSnapshots[i].SetUpdatedAt(dto.positionSnapshots[i].updatedAt);
      m_positionSnapshots[i].SetOpenCount(dto.positionSnapshots[i].openCount);
      m_positionSnapshots[i].SetTransactionCount(dto.positionSnapshots[i].transactionCount);
     }
  }

void CBasketAggregate::SetAuditHistoryFromDto(const CBasketPersistenceDto &dto)
  {
   m_commandHistoryCount=ArraySize(dto.commandHistory);
   ArrayResize(m_commandHistory,m_commandHistoryCount);
   for(int i=0;i<m_commandHistoryCount;i++)
      m_commandHistory[i]=dto.commandHistory[i];
   m_eventHistoryCount=ArraySize(dto.eventHistory);
   ArrayResize(m_eventHistory,m_eventHistoryCount);
   for(int i=0;i<m_eventHistoryCount;i++)
      m_eventHistory[i]=dto.eventHistory[i];
  }

void CBasketAggregate::CopyRuntimeStateToDto(CBasketPersistenceDto &dto) const
  {
   dto.hasStrategySnapshot=m_runtimeState.HasStrategyProfile();
   dto.strategyMigrationRequired=m_runtimeState.StrategyMigrationRequired();
   dto.strategyId=m_runtimeState.StrategyBinding().StrategyId();
   dto.strategySchemaVersion=m_runtimeState.StrategyBinding().SchemaVersion();
   dto.strategyProfileHash=m_runtimeState.StrategyBinding().ProfileHash();
   dto.strategyCanonicalJson=m_runtimeState.StrategyBinding().Snapshot().CanonicalJson();
   dto.strategyBoundAtUtc=m_runtimeState.StrategyBinding().BoundAtUtc();

   CBasketProfitLevelProgress levels[];
   int levelCount=0;
   m_runtimeState.CopyProfitLevelsTo(levels,levelCount);
   ArrayResize(dto.profitLevelProgress,levelCount);
   for(int i=0;i<levelCount;i++)
     {
      dto.profitLevelProgress[i].levelId=levels[i].LevelId();
      dto.profitLevelProgress[i].reached=levels[i].Reached();
      dto.profitLevelProgress[i].closeRequested=levels[i].CloseRequested();
      dto.profitLevelProgress[i].closeCompleted=levels[i].CloseCompleted();
      dto.profitLevelProgress[i].realizedProfit=levels[i].RealizedProfit().Amount();
      dto.profitLevelProgress[i].reachedAtUtc=(long)levels[i].ReachedAtUtc().Value();
      dto.profitLevelProgress[i].completedAtUtc=(long)levels[i].CompletedAtUtc().Value();
      dto.profitLevelProgress[i].executionCommandId=levels[i].ExecutionCommandId().Value();
      dto.profitLevelProgress[i].executionEventId=levels[i].ExecutionEventId().Value();
     }

   string ruleIds[];
   int ruleCount=0;
   m_runtimeState.CopyExecutedBreakEvenRulesTo(ruleIds,ruleCount);
   ArrayResize(dto.executedBreakEvenRuleIds,ruleCount);
   for(int i=0;i<ruleCount;i++)
      dto.executedBreakEvenRuleIds[i]=ruleIds[i];
  }

void CBasketAggregate::AppendEvaluationAudit(const CCommandId &commandId,const CEventId &eventId,
                                             const CUtcTime &timestampUtc)
  {
   BumpVersion(commandId,eventId,timestampUtc);
  }

#include <BasketRecovery/Domain/Aggregates/BasketAggregateCopyImpl.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregateRestorerImpl.mqh>

#endif
