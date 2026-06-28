#ifndef BRE_APP_MANUAL_PROFIT_CLOSE_CANDIDATE_REGISTRATION_SERVICE_MQH
#define BRE_APP_MANUAL_PROFIT_CLOSE_CANDIDATE_REGISTRATION_SERVICE_MQH

#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateEventBuffer.mqh>
#include <BasketRecovery/Application/Execution/ProfitCloseCandidateSubmissionValidator.mqh>
#include <BasketRecovery/Application/Execution/ProfitLevelCloseExecutionTracker.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevelCloseCandidate.mqh>
#include <BasketRecovery/Domain/Strategy/Context/StrategyEvaluationContext.mqh>
#include <BasketRecovery/Domain/Events/ManualProfitCloseCandidateDomainEvent.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotStatus.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Application/Ports/IAccountPositionModelProvider.mqh>
#include <BasketRecovery/Domain/Market/Enums/AccountPositionModel.mqh>

class CManualProfitCloseCandidateRegistrationService
  {
private:
   CManualProfitCloseCandidateRegistry     *m_registry;
   CManualProfitCloseCandidateEventBuffer  *m_eventBuffer;
   CProfitCloseCandidateSubmissionValidator *m_validator;
   CProfitLevelCloseExecutionTracker       *m_levelTracker;
   IPositionSnapshotStore                  *m_snapshotStore;
   IAccountPositionModelProvider           *m_positionModelProvider;
   IClock                                  *m_clock;
   IUniqueIdGenerator                      *m_idGenerator;
   int                                     m_candidateExpirySeconds;

   bool              TryFindOpenPosition(const CBasketId &basketId,
                                         const ulong ticket,
                                         CPositionSnapshotEntry &outEntry) const
     {
      if(m_snapshotStore==NULL)
         return false;
      CPositionSnapshot *snapshot=m_snapshotStore.Get(basketId);
      if(snapshot==NULL)
         return false;
      int total=snapshot.EntryCount();
      for(int i=0;i<total;i++)
        {
         CPositionSnapshotEntry entry;
         if(!snapshot.EntryAt(i,entry))
            continue;
         if(entry.Status()!=BRE_POSITION_SNAPSHOT_OPEN)
            continue;
         if(entry.Ticket()!=ticket)
            continue;
         outEntry=entry;
         return true;
        }
      return false;
     }

public:
                     CManualProfitCloseCandidateRegistrationService(CManualProfitCloseCandidateRegistry *registry,
                                                                    CManualProfitCloseCandidateEventBuffer *eventBuffer,
                                                                    CProfitCloseCandidateSubmissionValidator *validator,
                                                                    CProfitLevelCloseExecutionTracker *levelTracker,
                                                                    IPositionSnapshotStore *snapshotStore,
                                                                    IAccountPositionModelProvider *positionModelProvider,
                                                                    IClock *clock,
                                                                    IUniqueIdGenerator *idGenerator,
                                                                    const int candidateExpirySeconds=30)
     {
      m_registry=registry;
      m_eventBuffer=eventBuffer;
      m_validator=validator;
      m_levelTracker=levelTracker;
      m_snapshotStore=snapshotStore;
      m_positionModelProvider=positionModelProvider;
      m_clock=clock;
      m_idGenerator=idGenerator;
      m_candidateExpirySeconds=candidateExpirySeconds>0 ? candidateExpirySeconds : 30;
     }

   int               TryRegisterFromCandidate(const CBasketAggregate &basket,
                                              const CProfitLevelCloseCandidate &candidate,
                                              const CRecoveryRiskGateInput &gateInput)
     {
      if(m_registry==NULL || !gateInput.HasQuote())
         return 0;

      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : gateInput.TimestampUtc();
      m_registry.ExpireStale(nowUtc);

      ENUM_BRE_ACCOUNT_POSITION_MODEL positionModel=BRE_ACCOUNT_POSITION_MODEL_UNKNOWN;
      if(m_positionModelProvider!=NULL)
         positionModel=m_positionModelProvider.Capture();

      if(m_validator!=NULL)
        {
         CVoidResult eligible=m_validator.ValidateRegistrationEligible(candidate,positionModel);
         if(eligible.IsFail())
            return 0;
        }
      else if(!candidate.IsDue() || candidate.Audit().ReductionCount()!=1 ||
              !CAccountPositionModelHelper::SupportsExplicitTicketPartialClose(positionModel))
         return 0;

      if(m_levelTracker!=NULL &&
         m_levelTracker.IsLevelCompleted(basket.Id().Value(),candidate.Audit().ProfitLevelId()))
         return 0;

      CPositionReductionInstruction instruction;
      if(!candidate.Audit().ReductionAt(0,instruction))
         return 0;

      CPositionSnapshotEntry position;
      if(!TryFindOpenPosition(basket.Id(),instruction.Ticket(),position))
         return 0;

      CProfitLevelCloseAudit audit=candidate.Audit();
      string executionRequestId=m_idGenerator!=NULL ? "profit-close-manual:"+m_idGenerator.NewGuid() : "profit-close-manual:unknown";
      datetime expiresAt=nowUtc+m_candidateExpirySeconds;

      CManualProfitCloseCandidateEntry entry=CManualProfitCloseCandidateEntry::Create(audit.IdempotencyKey(),
                                                                                      executionRequestId,
                                                                                      audit.IdempotencyKey(),
                                                                                      basket.Id(),
                                                                                      audit.ProfitLevelId(),
                                                                                      audit.ProfitLevelIndex(),
                                                                                      audit.StrategyProfileHash(),
                                                                                      audit.BasketVersion(),
                                                                                      basket.Symbol(),
                                                                                      basket.Direction(),
                                                                                      position.Direction(),
                                                                                      instruction.Ticket(),
                                                                                      position.Volume(),
                                                                                      instruction.ProposedCloseVolume(),
                                                                                      instruction.EstimatedCloseMoney(),
                                                                                      audit.TriggerType(),
                                                                                      audit.TriggerValue(),
                                                                                      audit.QuoteSequence(),
                                                                                      nowUtc,
                                                                                      expiresAt,
                                                                                      positionModel);
      if(!m_registry.TryRegister(entry))
         return 0;

      Print("BRE manual_profit_close_candidate_available | candidate_id=",entry.CandidateId(),
            " | execution_request_id=",entry.ExecutionRequestId(),
            " | basket_id=",entry.BasketId().Value(),
            " | profit_level_id=",entry.ProfitLevelId(),
            " | ticket=",entry.PositionTicket(),
            " | volume=",DoubleToString(entry.ProposedCloseVolume(),8),
            " | position_model=",CAccountPositionModelHelper::ToString(entry.AccountPositionModel()),
            " | status=DUE");

      if(m_eventBuffer!=NULL)
        {
         CManualProfitCloseCandidateDomainEvent event=CManualProfitCloseCandidateDomainEvent::Create(
            BRE_EVENT_PROFIT_LEVEL_CLOSE_CANDIDATE_AVAILABLE,
            basket.Id(),
            gateInput.CorrelationKey(),
            nowUtc,
            entry.CandidateId(),
            entry.ExecutionRequestId(),
            entry.ProfitLevelId(),
            "manual-review-candidate");
         m_eventBuffer.TryEmit(event);
        }
      return 1;
     }
  };

#endif
