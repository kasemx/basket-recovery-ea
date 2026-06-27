#ifndef BASKET_RECOVERY_DOMAIN_BASKET_AGGREGATE_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_AGGREGATE_MQH

#include <BasketRecovery/Domain/Aggregates/IBasketReadModel.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Enums/BasketMode.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Domain/Basket/BasketRuntimeState.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfileSnapshot.mqh>
#include <BasketRecovery/Domain/ValueObjects/BasketVersion.mqh>
#include <BasketRecovery/Domain/ValueObjects/SignalDetails.mqh>
#include <BasketRecovery/Domain/ValueObjects/BasketMetadata.mqh>
#include <BasketRecovery/Domain/ValueObjects/AuditRecord.mqh>
#include <BasketRecovery/Domain/Entities/TradingSignal.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshot.mqh>
#include <BasketRecovery/Domain/StateMachine/TransitionResult.mqh>
#include <BasketRecovery/Domain/Persistence/BasketPersistenceDto.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CBasketAggregate : public IBasketReadModel
  {
private:
   CBasketId                         m_id;
   string                            m_correlationKey;
   ENUM_BRE_TRADE_DIRECTION          m_direction;
   string                            m_symbol;
   ENUM_BRE_BASKET_LIFECYCLE_STATE   m_lifecycleState;
   CBasketModeFlags                  m_modeFlags;
   CProfileSnapshot                  m_profileSnapshot;
   bool                              m_hasProfileSnapshot;
   CBasketRuntimeState               m_runtimeState;
   CBasketVersion                    m_versionState;
   CTradingSignal                    m_signal;
   CPositionSnapshot                *m_positionSnapshots[];
   int                               m_positionSnapshotCount;
   CBasketMetadata                   m_metadata;
   CAuditRecord                      m_commandHistory[];
   int                               m_commandHistoryCount;
   CAuditRecord                      m_eventHistory[];
   int                               m_eventHistoryCount;
   bool                              m_creationBindingOpen;

   void              RecordAudit(const CCommandId &commandId,const CEventId &eventId,const CUtcTime &timestampUtc)
     {
      CAuditRecord record;
      record.SetCommandId(commandId);
      record.SetEventId(eventId);
      record.SetTimestampUtc(timestampUtc);
      record.SetVersion(m_versionState.Version());
      ArrayResize(m_commandHistory,m_commandHistoryCount+1);
      m_commandHistory[m_commandHistoryCount]=record;
      m_commandHistoryCount++;
      ArrayResize(m_eventHistory,m_eventHistoryCount+1);
      m_eventHistory[m_eventHistoryCount]=record;
      m_eventHistoryCount++;
     }

   void              BumpVersion(const CCommandId &commandId,const CEventId &eventId,const CUtcTime &timestampUtc)
     {
      m_versionState.SetVersion(m_versionState.Version()+1);
      m_versionState.SetLastCommandId(commandId);
      m_versionState.SetLastEventId(eventId);
      m_versionState.SetLastModifiedUtc(timestampUtc);
      m_metadata.SetUpdatedAtUtc(timestampUtc);
      RecordAudit(commandId,eventId,timestampUtc);
     }

public:
                     CBasketAggregate(void)
     {
      m_correlationKey="";
      m_direction=BRE_DIRECTION_NONE;
      m_symbol="";
      m_lifecycleState=BRE_STATE_NONE;
      m_hasProfileSnapshot=false;
      m_positionSnapshotCount=0;
      m_commandHistoryCount=0;
      m_eventHistoryCount=0;
      m_creationBindingOpen=true;
      ArrayResize(m_positionSnapshots,0);
      ArrayResize(m_commandHistory,0);
      ArrayResize(m_eventHistory,0);
     }

                     CBasketAggregate(const CBasketAggregate &other);

                    ~CBasketAggregate(void)
     {
      for(int i=0;i<m_positionSnapshotCount;i++)
        {
         if(m_positionSnapshots[i]!=NULL)
           {
            delete m_positionSnapshots[i];
            m_positionSnapshots[i]=NULL;
           }
        }
     }

   CBasketId                         Id(void) const { return m_id; }
   string                            CorrelationKey(void) const { return m_correlationKey; }
   ENUM_BRE_TRADE_DIRECTION          Direction(void) const { return m_direction; }
   string                            Symbol(void) const { return m_symbol; }
   virtual ENUM_BRE_BASKET_LIFECYCLE_STATE LifecycleState(void) const { return m_lifecycleState; }
   CBasketModeFlags                  ModeFlags(void) const { return m_modeFlags; }
   bool                              HasProfileSnapshot(void) const { return m_hasProfileSnapshot; }
   CProfileSnapshot                  ProfileSnapshot(void) const { return m_profileSnapshot; }
   CBasketVersion                    VersionState(void) const { return m_versionState; }
   long                              Version(void) const { return m_versionState.Version(); }
   CTradingSignal                    Signal(void) const { return m_signal; }
   virtual CSignalDetails            SignalDetails(void) const { return m_signal.Details(); }
   virtual bool                      RecoveryPermanentlyDisabled(void) const { return m_modeFlags.RecoveryPermanentlyDisabled(); }
   CBasketMetadata                   Metadata(void) const { return m_metadata; }
   int                               PositionSnapshotCount(void) const { return m_positionSnapshotCount; }
   int                               CommandHistoryCount(void) const { return m_commandHistoryCount; }
   int                               EventHistoryCount(void) const { return m_eventHistoryCount; }
   bool                              CommandHistoryAt(const int index,CAuditRecord &outRecord) const
     {
      if(index<0 || index>=m_commandHistoryCount)
         return false;
      outRecord=m_commandHistory[index];
      return true;
     }

   bool                              EventHistoryAt(const int index,CAuditRecord &outRecord) const
     {
      if(index<0 || index>=m_eventHistoryCount)
         return false;
      outRecord=m_eventHistory[index];
      return true;
     }

   void                              ApplyCloseReason(const string closeReason)
     {
      m_metadata.SetCloseReason(closeReason);
     }

   bool                              ApplyStopLossUpdate(const CPrice &stopLoss,
                                                         const CCommandId &commandId,
                                                         const CEventId &eventId,
                                                         const CUtcTime &timestampUtc)
     {
      CSignalDetails details=m_signal.Details();
      details.SetStopLoss(stopLoss);
      details.SetHasDetails(true);
      return ApplySignalDetails(details,commandId,eventId,timestampUtc);
     }

   bool                              ApplyTakeProfitUpdate(const CSignalDetails &details,
                                                           const CCommandId &commandId,
                                                           const CEventId &eventId,
                                                           const CUtcTime &timestampUtc)
     {
      return ApplySignalDetails(details,commandId,eventId,timestampUtc);
     }

   bool                              CreationBindingOpen(void) const { return m_creationBindingOpen; }

   bool                              HasStrategyProfile(void) const { return m_runtimeState.HasStrategyProfile(); }
   bool                              StrategyMigrationRequired(void) const { return m_runtimeState.StrategyMigrationRequired(); }
   string                            StrategyId(void) const { return m_runtimeState.StrategyBinding().StrategyId(); }
   int                               StrategySchemaVersion(void) const { return m_runtimeState.StrategyBinding().SchemaVersion(); }
   string                            StrategyProfileHash(void) const { return m_runtimeState.StrategyBinding().ProfileHash(); }
   CUtcTime                          BoundAtUtc(void) const { return m_runtimeState.StrategyBinding().BoundAtUtc(); }
   int                               ProfitLevelProgressCount(void) const { return m_runtimeState.ProfitLevelCount(); }

   bool                              StrategyProfile(CStrategyProfile &outProfile) const
     {
      return m_runtimeState.StrategyBinding().TryGetProfile(outProfile);
     }

   bool                              FindProfitLevelProgress(const string levelId,CBasketProfitLevelProgress &outProgress) const
     {
      return m_runtimeState.FindProfitLevel(levelId,outProgress);
     }

   bool                              ProfitLevelProgressAt(const int index,CBasketProfitLevelProgress &outProgress) const
     {
      return m_runtimeState.ProfitLevelAt(index,outProgress);
     }

   void                              CopyExecutedBreakEvenRuleIds(string &outRuleIds[],int &outCount) const
     {
      m_runtimeState.CopyExecutedBreakEvenRulesTo(outRuleIds,outCount);
     }

   bool                              HasExecutedBreakEvenRule(const string ruleId) const
     {
      return m_runtimeState.HasExecutedBreakEvenRule(ruleId);
     }

   CPositionSnapshot*                PositionSnapshotAt(const int index) const
     {
      if(index<0 || index>=m_positionSnapshotCount)
         return NULL;
      return m_positionSnapshots[index];
     }

   CVoidResult                       BindStrategyProfile(const CStrategyProfileSnapshot &snapshot)
     {
      if(!m_creationBindingOpen)
         return CVoidResult::Fail(BRE_ERR_STRATEGY_ALREADY_BOUND,"Strategy binding is only allowed during basket creation");
      return m_runtimeState.BindStrategyProfile(snapshot);
     }

   bool                              InitializeFromFactory(const CBasketId &id,const string correlationKey,
                                                           const ENUM_BRE_TRADE_DIRECTION direction,
                                                           const string symbol,
                                                           const CProfileSnapshot &profileSnapshot,
                                                           const CTradingSignal &signal,
                                                           const CUtcTime &createdAtUtc,
                                                           const CCommandId &commandId,
                                                           const CEventId &eventId)
     {
      if(id.IsEmpty() || m_lifecycleState!=BRE_STATE_NONE)
         return false;
      m_id=id;
      m_correlationKey=correlationKey;
      m_direction=direction;
      m_symbol=symbol;
      m_profileSnapshot=profileSnapshot;
      m_hasProfileSnapshot=true;
      m_signal=signal;
      m_lifecycleState=BRE_STATE_PENDING_OPEN;
      m_metadata.SetCreatedAtUtc(createdAtUtc);
      m_metadata.SetUpdatedAtUtc(createdAtUtc);
      m_versionState.SetVersion(0);
      BumpVersion(commandId,eventId,createdAtUtc);
      return true;
     }

   void                              FinalizeCreationBinding(void) { m_creationBindingOpen=false; }

   bool                              ApplyLifecycleTransition(const CTransitionResult &transitionResult,
                                                                const CCommandId &commandId,
                                                                const CEventId &eventId,
                                                                const CUtcTime &timestampUtc)
     {
      if(!transitionResult.Applied() || transitionResult.PreviousState()!=m_lifecycleState)
         return false;
      m_lifecycleState=transitionResult.NewState();
      BumpVersion(commandId,eventId,timestampUtc);
      return true;
     }

   CVoidResult                       ApplyProfitLevelReached(const string levelId,const CUtcTime &timestampUtc,
                                                             const CCommandId &commandId,const CEventId &eventId)
     {
      CVoidResult result=m_runtimeState.MarkProfitLevelReached(levelId,timestampUtc,commandId,eventId);
      if(result.IsFail())
         return result;
      BumpVersion(commandId,eventId,timestampUtc);
      return CVoidResult::Ok();
     }

   CVoidResult                       ApplyBreakEvenActivated(const string ruleId,const CCommandId &commandId,
                                                             const CEventId &eventId,const CUtcTime &timestampUtc)
     {
      CVoidResult result=m_runtimeState.MarkBreakEvenRuleExecuted(ruleId);
      if(result.IsFail())
         return result;
      m_modeFlags.SetBreakEvenActive(true);
      BumpVersion(commandId,eventId,timestampUtc);
      return CVoidResult::Ok();
     }

   CVoidResult                       ApplyProfitLevelCloseRequested(const string levelId,
                                                                    const CCommandId &commandId,
                                                                    const CEventId &eventId,
                                                                    const CUtcTime &timestampUtc)
     {
      CVoidResult result=m_runtimeState.MarkProfitLevelCloseRequested(levelId,timestampUtc,commandId);
      if(result.IsFail())
         return result;
      BumpVersion(commandId,eventId,timestampUtc);
      return CVoidResult::Ok();
     }

   CVoidResult                       ApplyProfitLevelCloseCompleted(const string levelId,
                                                                   const CMoney &realizedProfit,
                                                                   const CCommandId &commandId,
                                                                   const CEventId &eventId,
                                                                   const CUtcTime &timestampUtc)
     {
      CVoidResult result=m_runtimeState.MarkProfitLevelCloseCompleted(levelId,realizedProfit,timestampUtc,eventId);
      if(result.IsFail())
         return result;
      BumpVersion(commandId,eventId,timestampUtc);
      return CVoidResult::Ok();
     }

   CVoidResult                       ApplyBasketLocked(const CCommandId &commandId,const CEventId &eventId,
                                                     const CUtcTime &timestampUtc)
     {
      m_modeFlags.SetLocked(true);
      BumpVersion(commandId,eventId,timestampUtc);
      return CVoidResult::Ok();
     }

   CVoidResult                       ApplyRiskReductionRequested(const CCommandId &commandId,
                                                                 const CEventId &eventId,
                                                                 const CUtcTime &timestampUtc)
     {
      m_modeFlags.SetRiskReductionActive(true);
      BumpVersion(commandId,eventId,timestampUtc);
      return CVoidResult::Ok();
     }

   CVoidResult                       CompleteStrategyMigration(const CStrategyProfileSnapshot &snapshot,
                                                               const CCommandId &commandId,
                                                               const CEventId &eventId,
                                                               const CUtcTime &timestampUtc)
     {
      if(!m_runtimeState.StrategyMigrationRequired())
         return CVoidResult::Fail(BRE_ERR_STRATEGY_ALREADY_BOUND,"Basket does not require strategy migration");
      if(m_runtimeState.HasStrategyProfile())
         return CVoidResult::Fail(BRE_ERR_STRATEGY_ALREADY_BOUND,"Strategy profile is already bound");
      m_runtimeState.CompleteStrategyMigration(snapshot);
      BumpVersion(commandId,eventId,timestampUtc);
      return CVoidResult::Ok();
     }

   void                              ApplyRecoveryDisabled(const CCommandId &commandId,const CEventId &eventId,
                                                           const CUtcTime &timestampUtc)
     {
      m_modeFlags.SetRecoveryPermanentlyDisabled(true);
      m_modeFlags.SetRecoveryActive(false);
      BumpVersion(commandId,eventId,timestampUtc);
     }

   bool                              ApplySignalDetails(const CSignalDetails &details,const CCommandId &commandId,
                                                        const CEventId &eventId,const CUtcTime &timestampUtc)
     {
      m_signal.SetDetails(details);
      BumpVersion(commandId,eventId,timestampUtc);
      return true;
     }

   bool                              RestoreFromDto(const CBasketPersistenceDto &dto);

   void                              ClearForRestore(void);
   void                              SetIdentity(const CBasketId &id,const string correlationKey,
                                                 const ENUM_BRE_TRADE_DIRECTION direction,const string symbol);
   void                              SetLifecycleState(const ENUM_BRE_BASKET_LIFECYCLE_STATE state) { m_lifecycleState=state; }
   void                              SetModeFlagsFromDto(const CBasketPersistenceDto &dto);
   void                              SetLegacyProfileSnapshot(const bool hasSnapshot,const string profileName,
                                                                const CRiskProfileConfig &risk,
                                                                const CRecoveryProfileConfig &recovery,
                                                                const CTakeProfitProfileConfig &takeProfit,
                                                                const CBreakEvenProfileConfig &breakEven,
                                                                const CExecutionProfileConfig &execution,
                                                                const CUtcTime &boundAt);
   void                              RestoreStrategyBinding(const CStrategyProfileSnapshot &snapshot,
                                                            const bool migrationRequired);
   void                              RestoreProfitLevels(const CBasketProfitLevelProgress &levels[],const int count);
   void                              RestoreExecutedBreakEvenRules(const string &ruleIds[]);
   void                              SetVersionState(const long version,const CCommandId &commandId,
                                                     const CEventId &eventId,const CUtcTime &modifiedUtc);
   void                              SetSignalFromDto(const CBasketPersistenceDto &dto);
   void                              SetMetadataFromDto(const CBasketPersistenceDto &dto);
   void                              SetPositionSnapshotsFromDto(const CBasketPersistenceDto &dto);
   void                              SetAuditHistoryFromDto(const CBasketPersistenceDto &dto);
   void                              CopyRuntimeStateToDto(CBasketPersistenceDto &dto) const;
   void                              AppendEvaluationAudit(const CCommandId &commandId,const CEventId &eventId,
                                                           const CUtcTime &timestampUtc);
  };

#include <BasketRecovery/Domain/Aggregates/BasketAggregateRestoreImpl.mqh>

#endif
