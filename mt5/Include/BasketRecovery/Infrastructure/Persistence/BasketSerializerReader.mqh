#ifndef BASKET_RECOVERY_INFRASTRUCTURE_BASKET_SERIALIZER_READER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_BASKET_SERIALIZER_READER_MQH

bool CBasketSerializer::FromReader(const CJsonReader &reader,CBasketPersistenceDto &dto,const int schemaVersion) const
  {
   dto.basketId=CBasketId(reader.ReadString("basket_id",""));
   dto.correlationKey=reader.ReadString("correlation_key","");
   dto.direction=(ENUM_BRE_TRADE_DIRECTION)reader.ReadInt("direction",BRE_DIRECTION_NONE);
   dto.symbol=reader.ReadString("symbol","");
   int rawLifecycle=reader.ReadInt("lifecycle_state",BRE_STATE_NONE);
   dto.lifecycleState=CBasketLifecycleStateHelper::FromLegacyInt(rawLifecycle);
   if(schemaVersion<BRE_PERSISTENCE_SCHEMA_VERSION && CBasketLifecycleStateHelper::WasLegacyProfitState(rawLifecycle))
      dto.breakEvenActive=(rawLifecycle==BRE_LEGACY_STATE_BREAK_EVEN);

   dto.recoveryActive=reader.ReadBool("recovery_active",false);
   dto.recoveryPermanentlyDisabled=reader.ReadBool("recovery_permanently_disabled",false);
   dto.breakEvenActive=reader.ReadBool("break_even_active",dto.breakEvenActive);
   dto.trailingActive=reader.ReadBool("trailing_active",false);
   dto.locked=reader.ReadBool("locked",false);
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

   dto.hasStrategySnapshot=reader.ReadBool("has_strategy_snapshot",false);
   dto.strategyMigrationRequired=reader.ReadBool("strategy_migration_required",schemaVersion<BRE_PERSISTENCE_SCHEMA_VERSION);
   dto.strategyId=reader.ReadString("strategy_id","");
   dto.strategySchemaVersion=reader.ReadInt("strategy_schema_version",0);
   dto.strategyProfileHash=reader.ReadString("strategy_profile_hash","");
   dto.strategyCanonicalJson=reader.ReadString("strategy_canonical_json","");
   dto.strategyBoundAtUtc=CUtcTime((datetime)reader.ReadLong("strategy_bound_at_utc",0));
   if(schemaVersion<BRE_PERSISTENCE_SCHEMA_VERSION && !dto.hasStrategySnapshot)
      dto.strategyMigrationRequired=true;

   string levelIds[];
   long reachedFlags[];
   long closeRequestedFlags[];
   long closeCompletedFlags[];
   double realizedProfits[];
   long reachedAt[];
   long completedAt[];
   string commandIds[];
   string eventIds[];
   int levelCount=reader.ReadStringArray("profit_level_ids",levelIds);
   reader.ReadLongArray("profit_level_reached",reachedFlags);
   reader.ReadLongArray("profit_level_close_requested",closeRequestedFlags);
   reader.ReadLongArray("profit_level_close_completed",closeCompletedFlags);
   reader.ReadDoubleArray("profit_level_realized_profit",realizedProfits);
   reader.ReadLongArray("profit_level_reached_at",reachedAt);
   reader.ReadLongArray("profit_level_completed_at",completedAt);
   reader.ReadStringArray("profit_level_command_ids",commandIds);
   reader.ReadStringArray("profit_level_event_ids",eventIds);
   ArrayResize(dto.profitLevelProgress,levelCount);
   for(int i=0;i<levelCount;i++)
     {
      dto.profitLevelProgress[i].levelId=levelIds[i];
      dto.profitLevelProgress[i].reached=(i<ArraySize(reachedFlags) && reachedFlags[i]!=0);
      dto.profitLevelProgress[i].closeRequested=(i<ArraySize(closeRequestedFlags) && closeRequestedFlags[i]!=0);
      dto.profitLevelProgress[i].closeCompleted=(i<ArraySize(closeCompletedFlags) && closeCompletedFlags[i]!=0);
      dto.profitLevelProgress[i].realizedProfit=(i<ArraySize(realizedProfits) ? realizedProfits[i] : 0.0);
      dto.profitLevelProgress[i].reachedAtUtc=(i<ArraySize(reachedAt) ? reachedAt[i] : 0);
      dto.profitLevelProgress[i].completedAtUtc=(i<ArraySize(completedAt) ? completedAt[i] : 0);
      dto.profitLevelProgress[i].executionCommandId=(i<ArraySize(commandIds) ? commandIds[i] : "");
      dto.profitLevelProgress[i].executionEventId=(i<ArraySize(eventIds) ? eventIds[i] : "");
     }
   reader.ReadStringArray("executed_break_even_rule_ids",dto.executedBreakEvenRuleIds);

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

   string auditCommandIds[];
   string auditEventIds[];
   long auditVersions[];
   long auditTimestamps[];
   int auditCount=reader.ReadStringArray("audit_command_ids",auditCommandIds);
   reader.ReadStringArray("audit_event_ids",auditEventIds);
   reader.ReadLongArray("audit_versions",auditVersions);
   reader.ReadLongArray("audit_timestamps",auditTimestamps);
   ArrayResize(dto.commandHistory,auditCount);
   ArrayResize(dto.eventHistory,auditCount);
   for(int i=0;i<auditCount;i++)
     {
      CAuditRecord record;
      record.SetCommandId(CCommandId(auditCommandIds[i]));
      record.SetEventId(CEventId(auditEventIds[i]));
      record.SetVersion(auditVersions[i]);
      record.SetTimestampUtc(CUtcTime((datetime)auditTimestamps[i]));
      dto.commandHistory[i]=record;
      dto.eventHistory[i]=record;
     }
   return !dto.basketId.IsEmpty();
  }

#endif
