#ifndef BASKET_RECOVERY_DOMAIN_BASKET_AGGREGATE_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_AGGREGATE_MQH

#include <BasketRecovery/Domain/Aggregates/IBasketReadModel.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Enums/BasketMode.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
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
   CBasketVersion                    m_versionState;
   CTradingSignal                    m_signal;
   CPositionSnapshot                *m_positionSnapshots[];
   int                               m_positionSnapshotCount;
   CBasketMetadata                   m_metadata;
   CAuditRecord                      m_commandHistory[];
   int                               m_commandHistoryCount;
   CAuditRecord                      m_eventHistory[];
   int                               m_eventHistoryCount;

   void              RecordAudit(const CCommandId &commandId,const CEventId &eventId,const CUtcTime timestampUtc)
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

   void              BumpVersion(const CCommandId &commandId,const CEventId &eventId,const CUtcTime timestampUtc)
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
      ArrayResize(m_positionSnapshots,0);
      ArrayResize(m_commandHistory,0);
      ArrayResize(m_eventHistory,0);
     }

                     CBasketAggregate(const CBasketAggregate &other)
     {
      m_id=other.m_id;
      m_correlationKey=other.m_correlationKey;
      m_direction=other.m_direction;
      m_symbol=other.m_symbol;
      m_lifecycleState=other.m_lifecycleState;
      m_modeFlags=other.m_modeFlags;
      m_profileSnapshot=other.m_profileSnapshot;
      m_hasProfileSnapshot=other.m_hasProfileSnapshot;
      m_versionState=other.m_versionState;
      m_signal=other.m_signal;
      m_metadata=other.m_metadata;
      m_positionSnapshotCount=other.m_positionSnapshotCount;
      m_commandHistoryCount=other.m_commandHistoryCount;
      m_eventHistoryCount=other.m_eventHistoryCount;

      ArrayResize(m_positionSnapshots,m_positionSnapshotCount);
      for(int i=0;i<m_positionSnapshotCount;i++)
        {
         if(other.m_positionSnapshots[i]!=NULL)
           {
            m_positionSnapshots[i]=new CPositionSnapshot();
            m_positionSnapshots[i].SetBasketId(other.m_positionSnapshots[i].BasketId());
            m_positionSnapshots[i].SetVersion(other.m_positionSnapshots[i].Version());
            m_positionSnapshots[i].SetUpdatedAt(other.m_positionSnapshots[i].UpdatedAt());
            m_positionSnapshots[i].SetOpenCount(other.m_positionSnapshots[i].OpenCount());
            m_positionSnapshots[i].SetTransactionCount(other.m_positionSnapshots[i].TransactionCount());
           }
         else
            m_positionSnapshots[i]=NULL;
        }

      ArrayResize(m_commandHistory,m_commandHistoryCount);
      for(int i=0;i<m_commandHistoryCount;i++)
         m_commandHistory[i]=other.m_commandHistory[i];

      ArrayResize(m_eventHistory,m_eventHistoryCount);
      for(int i=0;i<m_eventHistoryCount;i++)
         m_eventHistory[i]=other.m_eventHistory[i];
     }

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

   CPositionSnapshot*                PositionSnapshotAt(const int index) const
     {
      if(index<0 || index>=m_positionSnapshotCount)
         return NULL;
      return m_positionSnapshots[index];
     }

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

   bool                              InitializeFromFactory(const CBasketId &id,
                                                           const string correlationKey,
                                                           const ENUM_BRE_TRADE_DIRECTION direction,
                                                           const string symbol,
                                                           const CProfileSnapshot &profileSnapshot,
                                                           const CTradingSignal &signal,
                                                           const CUtcTime createdAtUtc,
                                                           const CCommandId &commandId,
                                                           const CEventId &eventId)
     {
      if(id.IsEmpty() || m_lifecycleState!=BRE_STATE_NONE)
         return false;
      if(m_hasProfileSnapshot)
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

   bool                              ApplyLifecycleTransition(const CTransitionResult &transitionResult,
                                                                const CCommandId &commandId,
                                                                const CEventId &eventId,
                                                                const CUtcTime timestampUtc)
     {
      if(!transitionResult.Applied())
         return false;
      if(transitionResult.PreviousState()!=m_lifecycleState)
         return false;

      m_lifecycleState=transitionResult.NewState();
      BumpVersion(commandId,eventId,timestampUtc);
      return true;
     }

   bool                              ApplySignalDetails(const CSignalDetails &details,
                                                          const CCommandId &commandId,
                                                          const CEventId &eventId,
                                                          const CUtcTime timestampUtc)
     {
      m_signal.SetDetails(details);
      BumpVersion(commandId,eventId,timestampUtc);
      return true;
     }

   bool                              ApplyStopLossUpdate(const CPrice &stopLoss,
                                                         const CCommandId &commandId,
                                                         const CEventId &eventId,
                                                         const CUtcTime timestampUtc)
     {
      CSignalDetails details=m_signal.Details();
      details.SetStopLoss(stopLoss);
      details.SetHasDetails(true);
      m_signal.SetDetails(details);
      BumpVersion(commandId,eventId,timestampUtc);
      return true;
     }

   bool                              ApplyTakeProfitUpdate(const CSignalDetails &details,
                                                           const CCommandId &commandId,
                                                           const CEventId &eventId,
                                                           const CUtcTime timestampUtc)
     {
      m_signal.SetDetails(details);
      BumpVersion(commandId,eventId,timestampUtc);
      return true;
     }

   bool                              ApplyCloseReason(const string closeReason)
     {
      m_metadata.SetCloseReason(closeReason);
      return true;
     }

   bool                              AttachPositionSnapshot(CPositionSnapshot *snapshot)
     {
      if(snapshot==NULL)
         return false;
      ArrayResize(m_positionSnapshots,m_positionSnapshotCount+1);
      m_positionSnapshots[m_positionSnapshotCount]=snapshot;
      m_positionSnapshotCount++;
      return true;
     }

   bool                              RestoreFromDto(const CBasketPersistenceDto &dto)
     {
      if(dto.basketId.IsEmpty())
         return false;

      for(int i=0;i<m_positionSnapshotCount;i++)
        {
         if(m_positionSnapshots[i]!=NULL)
           {
            delete m_positionSnapshots[i];
            m_positionSnapshots[i]=NULL;
           }
        }

      m_id=dto.basketId;
      m_correlationKey=dto.correlationKey;
      m_direction=dto.direction;
      m_symbol=dto.symbol;
      m_lifecycleState=dto.lifecycleState;
      m_modeFlags.SetRecoveryActive(dto.recoveryActive);
      m_modeFlags.SetRecoveryPermanentlyDisabled(dto.recoveryPermanentlyDisabled);
      m_modeFlags.SetRiskReductionActive(dto.riskReductionActive);
      m_modeFlags.SetMaxRiskLockout(dto.maxRiskLockout);
      m_hasProfileSnapshot=dto.hasProfileSnapshot;
      if(dto.hasProfileSnapshot)
        {
         m_profileSnapshot=CProfileSnapshot::Create(dto.profileName,
                                                    dto.risk,
                                                    dto.recovery,
                                                    dto.takeProfit,
                                                    dto.breakEven,
                                                    dto.execution,
                                                    dto.profileBoundAt);
        }

      m_versionState.SetVersion(dto.version);
      m_versionState.SetLastCommandId(dto.lastCommandId);
      m_versionState.SetLastEventId(dto.lastEventId);
      m_versionState.SetLastModifiedUtc(dto.lastModifiedUtc);

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

      m_metadata.SetCreatedAtUtc(dto.createdAtUtc);
      m_metadata.SetUpdatedAtUtc(dto.updatedAtUtc);
      m_metadata.SetRealizedProfit(dto.realizedProfit);
      m_metadata.SetCloseReason(dto.closeReason);

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

      m_commandHistoryCount=ArraySize(dto.commandHistory);
      ArrayResize(m_commandHistory,m_commandHistoryCount);
      for(int i=0;i<m_commandHistoryCount;i++)
         m_commandHistory[i]=dto.commandHistory[i];

      m_eventHistoryCount=ArraySize(dto.eventHistory);
      ArrayResize(m_eventHistory,m_eventHistoryCount);
      for(int i=0;i<m_eventHistoryCount;i++)
         m_eventHistory[i]=dto.eventHistory[i];

      return true;
     }
  };

#endif
