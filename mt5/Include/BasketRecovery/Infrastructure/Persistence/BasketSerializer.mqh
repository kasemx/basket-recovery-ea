#ifndef BASKET_RECOVERY_INFRASTRUCTURE_BASKET_SERIALIZER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_BASKET_SERIALIZER_MQH

#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Persistence/BasketPersistenceDto.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonWriter.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CBasketSerializer
  {
private:
   CJsonWriter m_writer;

   static void       ToDto(const CBasketAggregate &aggregate,CBasketPersistenceDto &dto)
     {
      dto.basketId=aggregate.Id();
      dto.correlationKey=aggregate.CorrelationKey();
      dto.direction=aggregate.Direction();
      dto.symbol=aggregate.Symbol();
      dto.lifecycleState=aggregate.LifecycleState();
      dto.recoveryActive=aggregate.ModeFlags().RecoveryActive();
      dto.recoveryPermanentlyDisabled=aggregate.ModeFlags().RecoveryPermanentlyDisabled();
      dto.breakEvenActive=aggregate.ModeFlags().BreakEvenActive();
      dto.trailingActive=aggregate.ModeFlags().TrailingActive();
      dto.locked=aggregate.ModeFlags().Locked();
      dto.riskReductionActive=aggregate.ModeFlags().RiskReductionActive();
      dto.maxRiskLockout=aggregate.ModeFlags().MaxRiskLockout();
      dto.hasProfileSnapshot=aggregate.HasProfileSnapshot();
      if(aggregate.HasProfileSnapshot())
        {
         CProfileSnapshot profile=aggregate.ProfileSnapshot();
         dto.profileName=profile.ProfileName();
         dto.risk=profile.Risk();
         dto.recovery=profile.Recovery();
         dto.takeProfit=profile.TakeProfit();
         dto.breakEven=profile.BreakEven();
         dto.execution=profile.Execution();
         dto.profileBoundAt=profile.BoundAt();
        }
      aggregate.CopyRuntimeStateToDto(dto);
      CBasketVersion versionState=aggregate.VersionState();
      dto.version=versionState.Version();
      dto.lastCommandId=versionState.LastCommandId();
      dto.lastEventId=versionState.LastEventId();
      dto.lastModifiedUtc=versionState.LastModifiedUtc();
      CTradingSignal signal=aggregate.Signal();
      dto.signalId=signal.Id();
      dto.signalCorrelationKey=signal.CorrelationKey();
      dto.signalSequence=signal.Sequence();
      dto.signalDirection=signal.Direction();
      dto.signalSymbol=signal.Symbol();
      dto.signalReceivedAt=signal.ReceivedAt();
      dto.signalIsConsumed=signal.IsConsumed();
      CSignalDetails details=signal.Details();
      dto.signalDetails.hasDetails=details.HasDetails();
      dto.signalDetails.rangeLow=details.RangeLow().Value();
      dto.signalDetails.rangeHigh=details.RangeHigh().Value();
      dto.signalDetails.stopLoss=details.StopLoss().Value();
      dto.signalDetails.tp1=details.Tp1().Value();
      dto.signalDetails.tp2=details.Tp2().Value();
      dto.signalDetails.tp3=details.Tp3().Value();
      dto.signalDetails.tp4=details.Tp4().Value();
      dto.signalDetails.tpOpen=details.TpOpen();
      CBasketMetadata metadata=aggregate.Metadata();
      dto.createdAtUtc=metadata.CreatedAtUtc();
      dto.updatedAtUtc=metadata.UpdatedAtUtc();
      dto.realizedProfit=metadata.RealizedProfit();
      dto.closeReason=metadata.CloseReason();
      int positionCount=aggregate.PositionSnapshotCount();
      ArrayResize(dto.positionSnapshots,positionCount);
      for(int i=0;i<positionCount;i++)
        {
         CPositionSnapshot *snapshot=aggregate.PositionSnapshotAt(i);
         if(snapshot==NULL)
            continue;
         dto.positionSnapshots[i].version=snapshot.Version();
         dto.positionSnapshots[i].basketId=snapshot.BasketId().Value();
         dto.positionSnapshots[i].updatedAt=snapshot.UpdatedAt();
         dto.positionSnapshots[i].openCount=snapshot.OpenCount();
         dto.positionSnapshots[i].transactionCount=snapshot.TransactionCount();
        }
      int commandCount=aggregate.CommandHistoryCount();
      ArrayResize(dto.commandHistory,commandCount);
      for(int i=0;i<commandCount;i++)
        {
         CAuditRecord record;
         if(aggregate.CommandHistoryAt(i,record))
            dto.commandHistory[i]=record;
        }
      int eventCount=aggregate.EventHistoryCount();
      ArrayResize(dto.eventHistory,eventCount);
      for(int i=0;i<eventCount;i++)
        {
         CAuditRecord record;
         if(aggregate.EventHistoryAt(i,record))
            dto.eventHistory[i]=record;
        }
     }

   string            BuildBodyFields(const CBasketPersistenceDto &dto) const
     {
      string fields="";
      fields+=m_writer.FieldString("basket_id",dto.basketId.Value())+",";
      fields+=m_writer.FieldString("correlation_key",dto.correlationKey)+",";
      fields+=m_writer.FieldInt("direction",(long)dto.direction)+",";
      fields+=m_writer.FieldString("symbol",dto.symbol)+",";
      fields+=m_writer.FieldInt("lifecycle_state",(long)dto.lifecycleState)+",";
      fields+=m_writer.FieldBool("recovery_active",dto.recoveryActive)+",";
      fields+=m_writer.FieldBool("recovery_permanently_disabled",dto.recoveryPermanentlyDisabled)+",";
      fields+=m_writer.FieldBool("break_even_active",dto.breakEvenActive)+",";
      fields+=m_writer.FieldBool("trailing_active",dto.trailingActive)+",";
      fields+=m_writer.FieldBool("locked",dto.locked)+",";
      fields+=m_writer.FieldBool("risk_reduction_active",dto.riskReductionActive)+",";
      fields+=m_writer.FieldBool("max_risk_lockout",dto.maxRiskLockout)+",";
      fields+=m_writer.FieldBool("has_profile_snapshot",dto.hasProfileSnapshot)+",";
      fields+=m_writer.FieldString("profile_name",dto.profileName)+",";
      fields+=m_writer.FieldDouble("risk_target_pct",dto.risk.TargetRiskPct())+",";
      fields+=m_writer.FieldDouble("risk_max_pct",dto.risk.MaxRiskPct())+",";
      fields+=m_writer.FieldDouble("recovery_step_pips",dto.recovery.RecoveryStepPips())+",";
      fields+=m_writer.FieldDouble("recovery_lot_size",dto.recovery.RecoveryLotSize())+",";
      fields+=m_writer.FieldInt("recovery_initial_position_count",(long)dto.recovery.InitialPositionCount())+",";
      fields+=m_writer.FieldInt("profile_bound_at",(long)dto.profileBoundAt.Value())+",";
      fields+=m_writer.FieldBool("has_strategy_snapshot",dto.hasStrategySnapshot)+",";
      fields+=m_writer.FieldBool("strategy_migration_required",dto.strategyMigrationRequired)+",";
      fields+=m_writer.FieldString("strategy_id",dto.strategyId)+",";
      fields+=m_writer.FieldInt("strategy_schema_version",dto.strategySchemaVersion)+",";
      fields+=m_writer.FieldString("strategy_profile_hash",dto.strategyProfileHash)+",";
      fields+=m_writer.FieldString("strategy_canonical_json",dto.strategyCanonicalJson)+",";
      fields+=m_writer.FieldInt("strategy_bound_at_utc",(long)dto.strategyBoundAtUtc.Value())+",";
      fields+=BuildProfitLevelFields(dto)+",";
      fields+=BuildExecutedBreakEvenFields(dto)+",";
      fields+=BuildVersionAndSignalFields(dto);
      return fields;
     }

   string            BuildProfitLevelFields(const CBasketPersistenceDto &dto) const
     {
      int levelCount=ArraySize(dto.profitLevelProgress);
      string levelIds[];
      long reachedFlags[];
      long closeRequestedFlags[];
      long closeCompletedFlags[];
      double realizedProfits[];
      long reachedAt[];
      long completedAt[];
      string commandIds[];
      string eventIds[];
      ArrayResize(levelIds,levelCount);
      ArrayResize(reachedFlags,levelCount);
      ArrayResize(closeRequestedFlags,levelCount);
      ArrayResize(closeCompletedFlags,levelCount);
      ArrayResize(realizedProfits,levelCount);
      ArrayResize(reachedAt,levelCount);
      ArrayResize(completedAt,levelCount);
      ArrayResize(commandIds,levelCount);
      ArrayResize(eventIds,levelCount);
      for(int i=0;i<levelCount;i++)
        {
         levelIds[i]=dto.profitLevelProgress[i].levelId;
         reachedFlags[i]=dto.profitLevelProgress[i].reached ? 1 : 0;
         closeRequestedFlags[i]=dto.profitLevelProgress[i].closeRequested ? 1 : 0;
         closeCompletedFlags[i]=dto.profitLevelProgress[i].closeCompleted ? 1 : 0;
         realizedProfits[i]=dto.profitLevelProgress[i].realizedProfit;
         reachedAt[i]=dto.profitLevelProgress[i].reachedAtUtc;
         completedAt[i]=dto.profitLevelProgress[i].completedAtUtc;
         commandIds[i]=dto.profitLevelProgress[i].executionCommandId;
         eventIds[i]=dto.profitLevelProgress[i].executionEventId;
        }
      string fields="";
      fields+=m_writer.StringArrayField("profit_level_ids",levelIds,levelCount)+",";
      fields+=m_writer.LongArrayField("profit_level_reached",reachedFlags,levelCount)+",";
      fields+=m_writer.LongArrayField("profit_level_close_requested",closeRequestedFlags,levelCount)+",";
      fields+=m_writer.LongArrayField("profit_level_close_completed",closeCompletedFlags,levelCount)+",";
      fields+=m_writer.DoubleArrayField("profit_level_realized_profit",realizedProfits,levelCount)+",";
      fields+=m_writer.LongArrayField("profit_level_reached_at",reachedAt,levelCount)+",";
      fields+=m_writer.LongArrayField("profit_level_completed_at",completedAt,levelCount)+",";
      fields+=m_writer.StringArrayField("profit_level_command_ids",commandIds,levelCount)+",";
      fields+=m_writer.StringArrayField("profit_level_event_ids",eventIds,levelCount);
      return fields;
     }

   string            BuildExecutedBreakEvenFields(const CBasketPersistenceDto &dto) const
     {
      return m_writer.StringArrayField("executed_break_even_rule_ids",dto.executedBreakEvenRuleIds,
                                       ArraySize(dto.executedBreakEvenRuleIds));
     }

   string            BuildVersionAndSignalFields(const CBasketPersistenceDto &dto) const
     {
      string fields="";
      fields+=m_writer.FieldInt("version",dto.version)+",";
      fields+=m_writer.FieldString("last_command_id",dto.lastCommandId.Value())+",";
      fields+=m_writer.FieldString("last_event_id",dto.lastEventId.Value())+",";
      fields+=m_writer.FieldInt("last_modified_utc",(long)dto.lastModifiedUtc.Value())+",";
      fields+=m_writer.FieldString("signal_id",dto.signalId.Value())+",";
      fields+=m_writer.FieldString("signal_correlation_key",dto.signalCorrelationKey)+",";
      fields+=m_writer.FieldString("signal_sequence",dto.signalSequence)+",";
      fields+=m_writer.FieldInt("signal_direction",(long)dto.signalDirection)+",";
      fields+=m_writer.FieldString("signal_symbol",dto.signalSymbol)+",";
      fields+=m_writer.FieldBool("signal_has_details",dto.signalDetails.hasDetails)+",";
      fields+=m_writer.FieldDouble("signal_range_low",dto.signalDetails.rangeLow)+",";
      fields+=m_writer.FieldDouble("signal_range_high",dto.signalDetails.rangeHigh)+",";
      fields+=m_writer.FieldDouble("signal_stop_loss",dto.signalDetails.stopLoss)+",";
      fields+=m_writer.FieldDouble("signal_tp1",dto.signalDetails.tp1)+",";
      fields+=m_writer.FieldDouble("signal_tp2",dto.signalDetails.tp2)+",";
      fields+=m_writer.FieldDouble("signal_tp3",dto.signalDetails.tp3)+",";
      fields+=m_writer.FieldDouble("signal_tp4",dto.signalDetails.tp4)+",";
      fields+=m_writer.FieldBool("signal_tp_open",dto.signalDetails.tpOpen)+",";
      fields+=m_writer.FieldInt("signal_received_at",(long)dto.signalReceivedAt)+",";
      fields+=m_writer.FieldBool("signal_is_consumed",dto.signalIsConsumed)+",";
      fields+=m_writer.FieldInt("created_at_utc",(long)dto.createdAtUtc.Value())+",";
      fields+=m_writer.FieldInt("updated_at_utc",(long)dto.updatedAtUtc.Value())+",";
      fields+=m_writer.FieldDouble("realized_profit",dto.realizedProfit.Amount())+",";
      fields+=m_writer.FieldString("close_reason",dto.closeReason)+",";
      fields+=BuildPositionAndAuditFields(dto);
      return fields;
     }

   string            BuildPositionAndAuditFields(const CBasketPersistenceDto &dto) const
     {
      int positionCount=ArraySize(dto.positionSnapshots);
      long positionVersions[];
      long positionUpdatedAt[];
      long positionOpenCounts[];
      long positionTxCounts[];
      ArrayResize(positionVersions,positionCount);
      ArrayResize(positionUpdatedAt,positionCount);
      ArrayResize(positionOpenCounts,positionCount);
      ArrayResize(positionTxCounts,positionCount);
      for(int i=0;i<positionCount;i++)
        {
         positionVersions[i]=dto.positionSnapshots[i].version;
         positionUpdatedAt[i]=(long)dto.positionSnapshots[i].updatedAt;
         positionOpenCounts[i]=dto.positionSnapshots[i].openCount;
         positionTxCounts[i]=dto.positionSnapshots[i].transactionCount;
        }
      string fields="";
      fields+=m_writer.LongArrayField("position_versions",positionVersions,positionCount)+",";
      fields+=m_writer.LongArrayField("position_updated_at",positionUpdatedAt,positionCount)+",";
      fields+=m_writer.LongArrayField("position_open_counts",positionOpenCounts,positionCount)+",";
      fields+=m_writer.LongArrayField("position_tx_counts",positionTxCounts,positionCount)+",";
      int commandCount=ArraySize(dto.commandHistory);
      string commandIds[];
      string eventIds[];
      long auditVersions[];
      long auditTimestamps[];
      ArrayResize(commandIds,commandCount);
      ArrayResize(eventIds,commandCount);
      ArrayResize(auditVersions,commandCount);
      ArrayResize(auditTimestamps,commandCount);
      for(int i=0;i<commandCount;i++)
        {
         commandIds[i]=dto.commandHistory[i].CommandId().Value();
         eventIds[i]=dto.commandHistory[i].EventId().Value();
         auditVersions[i]=dto.commandHistory[i].Version();
         auditTimestamps[i]=(long)dto.commandHistory[i].TimestampUtc().Value();
        }
      fields+=m_writer.StringArrayField("audit_command_ids",commandIds,commandCount)+",";
      fields+=m_writer.StringArrayField("audit_event_ids",eventIds,commandCount)+",";
      fields+=m_writer.LongArrayField("audit_versions",auditVersions,commandCount)+",";
      fields+=m_writer.LongArrayField("audit_timestamps",auditTimestamps,commandCount);
      return fields;
     }

public:
   bool              FromReader(const CJsonReader &reader,CBasketPersistenceDto &dto,const int schemaVersion) const;

   string            BuildCrcPayload(const CBasketPersistenceDto &dto) const
     {
      return "\"schema_version\":"+IntegerToString(BRE_PERSISTENCE_SCHEMA_VERSION)+","+BuildBodyFields(dto);
     }

   string            Serialize(const CBasketAggregate &aggregate) const
     {
      CBasketPersistenceDto dto;
      ToDto(aggregate,dto);
      string body=BuildBodyFields(dto);
      return m_writer.BuildEnvelope(BRE_PERSISTENCE_SCHEMA_VERSION,body);
     }

   CResult<CBasketAggregate> Deserialize(const string jsonContent,const bool recoveryMode=false) const
     {
      CJsonReader reader;
      reader.SetRecoveryMode(recoveryMode);
      reader.SetContent(jsonContent);
      int schemaVersion=reader.ReadSchemaVersion();
      if(schemaVersion<=0)
         return CResult<CBasketAggregate>::Fail(BRE_ERR_PERSIST_CORRUPT,"Schema version is missing");
      if(schemaVersion>BRE_PERSISTENCE_SCHEMA_VERSION)
         return CResult<CBasketAggregate>::Fail(BRE_ERR_PERSIST_SCHEMA_UNSUPPORTED,"Unsupported basket schema version");

      CBasketPersistenceDto dto;
      if(!FromReader(reader,dto,schemaVersion))
         return CResult<CBasketAggregate>::Fail(BRE_ERR_PERSIST_CORRUPT,"Basket payload is invalid");

      string payloadForCrc="\"schema_version\":"+IntegerToString(BRE_PERSISTENCE_SCHEMA_VERSION)+","+BuildBodyFields(dto);
      if(schemaVersion==BRE_PERSISTENCE_SCHEMA_VERSION && reader.ValidateCrc(payloadForCrc).IsFail())
         return CResult<CBasketAggregate>::Fail(BRE_ERR_PERSIST_CRC_MISMATCH,"Basket CRC validation failed");

      CBasketAggregate aggregate;
      if(!aggregate.RestoreFromDto(dto))
         return CResult<CBasketAggregate>::Fail(BRE_ERR_PERSIST_CORRUPT,"Basket restore failed");

      return CResult<CBasketAggregate>::Ok(aggregate);
     }
  };

#include <BasketRecovery/Infrastructure/Persistence/BasketSerializerReader.mqh>

#endif
