#ifndef BASKET_RECOVERY_INFRASTRUCTURE_BASKET_SERIALIZER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_BASKET_SERIALIZER_MQH

#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Persistence/BasketPersistenceDto.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonWriter.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>
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

   string            BuildPayloadForCrc(const CBasketPersistenceDto &dto) const
     {
      return "\"schema_version\":"+IntegerToString(BRE_PERSISTENCE_SCHEMA_VERSION)+","+BuildBodyFields(dto);
     }

   bool              FromReader(const CJsonReader &reader,CBasketPersistenceDto &dto) const
     {
      dto.basketId=CBasketId(reader.ReadString("basket_id",""));
      dto.correlationKey=reader.ReadString("correlation_key","");
      dto.direction=(ENUM_BRE_TRADE_DIRECTION)reader.ReadInt("direction",BRE_DIRECTION_NONE);
      dto.symbol=reader.ReadString("symbol","");
      dto.lifecycleState=(ENUM_BRE_BASKET_LIFECYCLE_STATE)reader.ReadInt("lifecycle_state",BRE_STATE_NONE);
      dto.recoveryActive=reader.ReadBool("recovery_active",false);
      dto.recoveryPermanentlyDisabled=reader.ReadBool("recovery_permanently_disabled",false);
      dto.riskReductionActive=reader.ReadBool("risk_reduction_active",false);
      dto.maxRiskLockout=reader.ReadBool("max_risk_lockout",false);
      dto.hasProfileSnapshot=reader.ReadBool("has_profile_snapshot",false);
      dto.profileName=reader.ReadString("profile_name","default");

      dto.risk.SetProfileName(dto.profileName);
      dto.risk.SetTargetRiskPct(reader.ReadDouble("risk_target_pct",1.0));
      dto.risk.SetMaxRiskPct(reader.ReadDouble("risk_max_pct",1.2));
      dto.recovery.SetProfileName(dto.profileName);
      dto.recovery.SetRecoveryStepPips(reader.ReadDouble("recovery_step_pips",0.2));
      dto.recovery.SetRecoveryLotSize(reader.ReadDouble("recovery_lot_size",0.01));
      dto.recovery.SetInitialPositionCount(reader.ReadInt("recovery_initial_position_count",3));
      dto.takeProfit.SetProfileName(dto.profileName);
      dto.breakEven.SetProfileName(dto.profileName);
      dto.execution.SetProfileName(dto.profileName);
      dto.profileBoundAt=CUtcTime((datetime)reader.ReadLong("profile_bound_at",0));

      dto.version=reader.ReadLong("version",0);
      dto.lastCommandId=CCommandId(reader.ReadString("last_command_id",""));
      dto.lastEventId=CEventId(reader.ReadString("last_event_id",""));
      dto.lastModifiedUtc=CUtcTime((datetime)reader.ReadLong("last_modified_utc",0));

      dto.signalId=CSignalId(reader.ReadString("signal_id",""));
      dto.signalCorrelationKey=reader.ReadString("signal_correlation_key","");
      dto.signalSequence=reader.ReadString("signal_sequence","");
      dto.signalDirection=(ENUM_BRE_TRADE_DIRECTION)reader.ReadInt("signal_direction",BRE_DIRECTION_NONE);
      dto.signalSymbol=reader.ReadString("signal_symbol","");
      dto.signalDetails.hasDetails=reader.ReadBool("signal_has_details",false);
      dto.signalDetails.stopLoss=reader.ReadDouble("signal_stop_loss",0.0);
      dto.signalDetails.tp1=reader.ReadDouble("signal_tp1",0.0);
      dto.signalDetails.tp2=reader.ReadDouble("signal_tp2",0.0);
      dto.signalDetails.tp3=reader.ReadDouble("signal_tp3",0.0);
      dto.signalDetails.tp4=reader.ReadDouble("signal_tp4",0.0);
      dto.signalDetails.tpOpen=reader.ReadBool("signal_tp_open",false);
      dto.signalReceivedAt=(datetime)reader.ReadLong("signal_received_at",0);
      dto.signalIsConsumed=reader.ReadBool("signal_is_consumed",false);

      dto.createdAtUtc=CUtcTime((datetime)reader.ReadLong("created_at_utc",0));
      dto.updatedAtUtc=CUtcTime((datetime)reader.ReadLong("updated_at_utc",0));
      dto.realizedProfit=CMoney(reader.ReadDouble("realized_profit",0.0));
      dto.closeReason=reader.ReadString("close_reason","");

      long positionVersions[];
      long positionUpdatedAt[];
      long positionOpenCounts[];
      long positionTxCounts[];
      int positionCount=reader.ReadLongArray("position_versions",positionVersions);
      reader.ReadLongArray("position_updated_at",positionUpdatedAt);
      reader.ReadLongArray("position_open_counts",positionOpenCounts);
      reader.ReadLongArray("position_tx_counts",positionTxCounts);
      ArrayResize(dto.positionSnapshots,positionCount);
      for(int i=0;i<positionCount;i++)
        {
         dto.positionSnapshots[i].version=(int)positionVersions[i];
         dto.positionSnapshots[i].basketId=dto.basketId.Value();
         dto.positionSnapshots[i].updatedAt=(datetime)positionUpdatedAt[i];
         dto.positionSnapshots[i].openCount=(int)positionOpenCounts[i];
         dto.positionSnapshots[i].transactionCount=(int)positionTxCounts[i];
        }

      string commandIds[];
      string eventIds[];
      long auditVersions[];
      long auditTimestamps[];
      int auditCount=reader.ReadStringArray("audit_command_ids",commandIds);
      reader.ReadStringArray("audit_event_ids",eventIds);
      reader.ReadLongArray("audit_versions",auditVersions);
      reader.ReadLongArray("audit_timestamps",auditTimestamps);
      ArrayResize(dto.commandHistory,auditCount);
      ArrayResize(dto.eventHistory,auditCount);
      for(int i=0;i<auditCount;i++)
        {
         CAuditRecord record;
         record.SetCommandId(CCommandId(commandIds[i]));
         record.SetEventId(CEventId(eventIds[i]));
         record.SetVersion(auditVersions[i]);
         record.SetTimestampUtc(CUtcTime((datetime)auditTimestamps[i]));
         dto.commandHistory[i]=record;
         dto.eventHistory[i]=record;
        }
      return !dto.basketId.IsEmpty();
     }

public:
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

      if(reader.ValidateSchemaVersion(BRE_PERSISTENCE_SCHEMA_VERSION).IsFail())
         return CResult<CBasketAggregate>::Fail(BRE_ERR_PERSIST_SCHEMA_UNSUPPORTED,"Unsupported basket schema version");

      CBasketPersistenceDto dto;
      if(!FromReader(reader,dto))
         return CResult<CBasketAggregate>::Fail(BRE_ERR_PERSIST_CORRUPT,"Basket payload is invalid");

      string payloadForCrc="\"schema_version\":"+IntegerToString(BRE_PERSISTENCE_SCHEMA_VERSION)+","+BuildBodyFields(dto);
      if(reader.ValidateCrc(payloadForCrc).IsFail())
         return CResult<CBasketAggregate>::Fail(BRE_ERR_PERSIST_CRC_MISMATCH,"Basket CRC validation failed");

      CBasketAggregate aggregate;
      if(!aggregate.RestoreFromDto(dto))
         return CResult<CBasketAggregate>::Fail(BRE_ERR_PERSIST_CORRUPT,"Basket restore failed");

      return CResult<CBasketAggregate>::Ok(aggregate);
     }
  };

#endif
