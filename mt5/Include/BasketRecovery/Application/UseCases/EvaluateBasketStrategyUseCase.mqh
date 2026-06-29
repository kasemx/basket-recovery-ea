#ifndef BRE_APP_EVALUATE_BASKET_STRATEGY_UC_MQH
#define BRE_APP_EVALUATE_BASKET_STRATEGY_UC_MQH

#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IStrategyEngine.mqh>
#include <BasketRecovery/Application/Ports/ICommandQueue.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Services/StrategyEvaluationContextFactory.mqh>
#include <BasketRecovery/Application/Services/StrategyDecisionCommandMapper.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Application/Strategy/RecoveryCandidatePlanningService.mqh>
#include <BasketRecovery/Application/Strategy/ProfitLevelCloseCandidatePlanningService.mqh>
#include <BasketRecovery/Application/Strategy/BreakEvenCandidatePlanningService.mqh>
#include <BasketRecovery/Application/Strategy/BreakEvenModificationDryRunService.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateRegistrationService.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateRegistrationService.mqh>
#include <BasketRecovery/Application/Ports/IAccountPositionModelProvider.mqh>
#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Application/Commands/CommandBase.mqh>
#include <BasketRecovery/Domain/Basket/BasketRuntimeGuard.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/RiskRuntimeContext.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevelCloseCandidate.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenCandidate.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CEvaluateBasketStrategyUseCase
  {
private:
   IBasketRepository       *m_repository;
   IStrategyEngine         *m_strategyEngine;
   ICommandQueue           *m_queue;
   IClock                  *m_clock;
   IUniqueIdGenerator      *m_idGenerator;
   IPositionSnapshotStore  *m_snapshotStore;
   CRecoveryDecisionRiskGateService *m_riskGateService;
   CRecoveryCandidatePlanningService *m_candidatePlanningService;
   CProfitLevelCloseCandidatePlanningService *m_profitLevelClosePlanningService;
   CBreakEvenCandidatePlanningService *m_breakEvenPlanningService;
   CBreakEvenModificationDryRunService *m_breakEvenModificationDryRunService;
   CManualRecoveryCandidateRegistrationService *m_manualRecoveryRegistrationService;
   CManualProfitCloseCandidateRegistrationService *m_manualProfitCloseRegistrationService;

public:
   IBasketRepository* Repository(void) const { return m_repository; }

   void              ConfigureRecoveryRiskGate(CRecoveryDecisionRiskGateService *riskGateService)
     {
      m_riskGateService=riskGateService;
     }

   void              ConfigureRecoveryCandidatePlanning(CRecoveryCandidatePlanningService *planningService)
     {
      m_candidatePlanningService=planningService;
     }

   CRecoveryDecisionRiskGateService* RiskGateService(void) const { return m_riskGateService; }
   CRecoveryCandidatePlanningService* CandidatePlanningService(void) const { return m_candidatePlanningService; }

   void              ConfigureProfitLevelCloseCandidatePlanning(CProfitLevelCloseCandidatePlanningService *planningService)
     {
      m_profitLevelClosePlanningService=planningService;
     }

   CProfitLevelCloseCandidatePlanningService* ProfitLevelClosePlanningService(void) const
     {
      return m_profitLevelClosePlanningService;
     }

   void              ConfigureBreakEvenCandidatePlanning(CBreakEvenCandidatePlanningService *planningService)
     {
      m_breakEvenPlanningService=planningService;
     }

   CBreakEvenCandidatePlanningService* BreakEvenPlanningService(void) const
     {
      return m_breakEvenPlanningService;
     }

   void              ConfigureBreakEvenModificationDryRun(CBreakEvenModificationDryRunService *dryRunService)
     {
      m_breakEvenModificationDryRunService=dryRunService;
     }

   CBreakEvenModificationDryRunService* BreakEvenModificationDryRunService(void) const
     {
      return m_breakEvenModificationDryRunService;
     }

   void              ConfigureManualRecoveryCandidateRegistration(CManualRecoveryCandidateRegistrationService *registrationService)
     {
      m_manualRecoveryRegistrationService=registrationService;
     }

   CManualRecoveryCandidateRegistrationService* ManualRecoveryRegistrationService(void) const
     {
      return m_manualRecoveryRegistrationService;
     }

   void              ConfigureManualProfitCloseCandidateRegistration(CManualProfitCloseCandidateRegistrationService *registrationService)
     {
      m_manualProfitCloseRegistrationService=registrationService;
     }

   CManualProfitCloseCandidateRegistrationService* ManualProfitCloseRegistrationService(void) const
     {
      return m_manualProfitCloseRegistrationService;
     }

public:
                     CEvaluateBasketStrategyUseCase(IBasketRepository *repository,
                                                    IStrategyEngine *strategyEngine,
                                                    ICommandQueue *queue,
                                                    IClock *clock,
                                                    IUniqueIdGenerator *idGenerator,
                                                    IPositionSnapshotStore *snapshotStore)
     {
      m_repository=repository;
      m_strategyEngine=strategyEngine;
      m_queue=queue;
      m_clock=clock;
      m_idGenerator=idGenerator;
      m_snapshotStore=snapshotStore;
      m_riskGateService=NULL;
      m_candidatePlanningService=NULL;
      m_profitLevelClosePlanningService=NULL;
      m_breakEvenPlanningService=NULL;
      m_breakEvenModificationDryRunService=NULL;
      m_manualRecoveryRegistrationService=NULL;
      m_manualProfitCloseRegistrationService=NULL;
     }

   CStrategyDecisionSet ApplyRecoveryCandidatePlanning(const CBasketAggregate &basket,
                                                     const CStrategyDecisionSet &decisions,
                                                     const CStrategyEvaluationContext &context,
                                                     const CRecoveryRiskGateInput &gateInput) const
     {
      if(m_candidatePlanningService==NULL)
         return decisions;

      CStrategyRiskEvaluationContext riskContext;
      if(m_riskGateService!=NULL && gateInput.HasQuote())
         riskContext=m_riskGateService.BuildRiskContext(basket,
                                                        gateInput.Quote(),
                                                        gateInput.Account(),
                                                        gateInput.QuoteSequence());

      return m_candidatePlanningService.ApplyPlanning(basket,decisions,context,gateInput,riskContext);
     }

   CProfitLevelCloseCandidate ApplyProfitLevelCloseCandidatePlanning(const CBasketAggregate &basket,
                                                                   const CStrategyEvaluationContext &context,
                                                                   const CRecoveryRiskGateInput &gateInput) const
     {
      if(m_profitLevelClosePlanningService==NULL)
        {
         CProfitLevelCloseCandidate empty;
         return empty;
        }

      return m_profitLevelClosePlanningService.EvaluateAndEmit(basket,context,gateInput);
     }

   CBreakEvenCandidate ApplyBreakEvenCandidatePlanning(const CBasketAggregate &basket,
                                                     const CStrategyEvaluationContext &context,
                                                     const CRecoveryRiskGateInput &gateInput) const
     {
      if(m_breakEvenPlanningService==NULL)
        {
         CBreakEvenCandidate empty;
         return empty;
        }

      return m_breakEvenPlanningService.EvaluateAndEmit(basket,context,gateInput);
     }

   CBreakEvenStopLossModificationRequest ApplyBreakEvenModificationDryRun(const CBasketAggregate &basket,
                                                                          const CBreakEvenCandidate &candidate,
                                                                          const CRecoveryRiskGateInput &gateInput) const
     {
      if(m_breakEvenModificationDryRunService==NULL)
        {
         CBreakEvenStopLossModificationRequest empty;
         return empty;
        }
      return m_breakEvenModificationDryRunService.EvaluateDryRun(basket,candidate,gateInput);
     }

   void              RegisterManualProfitCloseCandidates(const CBasketAggregate &basket,
                                                       const CProfitLevelCloseCandidate &candidate,
                                                       const CRecoveryRiskGateInput &gateInput) const
     {
      if(m_manualProfitCloseRegistrationService==NULL || !gateInput.HasQuote())
         return;
      m_manualProfitCloseRegistrationService.TryRegisterFromCandidate(basket,candidate,gateInput);
     }

   CStrategyDecisionSet ApplyRecoveryRiskGate(const CBasketAggregate &basket,
                                            const CStrategyDecisionSet &decisions,
                                            const CRecoveryRiskGateInput &gateInput,
                                            CStrategyEvaluationContext &context) const
     {
      if(m_riskGateService==NULL || !gateInput.HasQuote())
         return decisions;

      CStrategyRiskEvaluationContext riskContext;
      CStrategyDecisionSet gated=m_riskGateService.ApplyGate(basket,decisions,gateInput,riskContext);
      context.SetRiskEvaluationContext(riskContext);
      return gated;
     }

   void              RegisterManualRecoveryCandidates(const CBasketAggregate &basket,
                                                    const CStrategyDecisionSet &decisions,
                                                    const CStrategyEvaluationContext &context,
                                                    const CRecoveryRiskGateInput &gateInput) const
     {
      if(m_manualRecoveryRegistrationService==NULL || !gateInput.HasQuote())
         return;

      CStrategyRiskEvaluationContext riskContext=context.RiskEvaluationContext();
      m_manualRecoveryRegistrationService.TryRegisterFromGatedDecisions(basket,decisions,context,gateInput,riskContext);
     }

   CResult<int>      Execute(const CEvaluateStrategyCommand &command,
                             const CMarketContext &market,
                             const CRiskRuntimeContext &riskContext)
     {
      CRecoveryRiskGateInput emptyGateInput;
      return ExecuteWithRiskGate(command,market,riskContext,emptyGateInput);
     }

   CResult<int>      ExecuteWithRiskGate(const CEvaluateStrategyCommand &command,
                                         const CMarketContext &market,
                                         const CRiskRuntimeContext &riskContext,
                                         const CRecoveryRiskGateInput &gateInput)
     {
      if(m_repository==NULL)
         return CResult<int>::Fail(BRE_ERR_BASKET_NOT_FOUND,"Basket repository is required");

      CResult<CBasketAggregate> loaded=m_repository.Load(command.BasketId());
      if(loaded.IsFail())
         return CResult<int>::Fail(loaded.ErrorCode(),loaded.ErrorMessage());

      CBasketAggregate basket;
      if(!loaded.TryGetValue(basket))
         return CResult<int>::Fail(BRE_ERR_BASKET_NOT_FOUND,"Basket aggregate missing");

      CVoidResult guardResult=CBasketRuntimeGuard::ValidateStrategyCommandContext(basket,
                                                                                  command.ExpectedBasketVersion(),
                                                                                  command.StrategyProfileHash());
      if(guardResult.IsFail())
         return CResult<int>::Fail(guardResult.ErrorCode(),guardResult.ErrorMessage());

      CResult<CStrategyEvaluationContext> contextResult=
         CStrategyEvaluationContextFactory::TryBuild(basket,market,riskContext,m_snapshotStore);
      if(contextResult.IsFail())
         return CResult<int>::Fail(contextResult.ErrorCode(),contextResult.ErrorMessage());

      CStrategyEvaluationContext context;
      contextResult.TryGetValue(context);
      CStrategyDecisionSet decisions=m_strategyEngine.EvaluateAll(context);
      decisions=ApplyRecoveryCandidatePlanning(basket,decisions,context,gateInput);
      CProfitLevelCloseCandidate profitCloseCandidate=ApplyProfitLevelCloseCandidatePlanning(basket,context,gateInput);
      CBreakEvenCandidate breakEvenCandidate=ApplyBreakEvenCandidatePlanning(basket,context,gateInput);
      ApplyBreakEvenModificationDryRun(basket,breakEvenCandidate,gateInput);
      decisions=ApplyRecoveryRiskGate(basket,decisions,gateInput,context);
      RegisterManualRecoveryCandidates(basket,decisions,context,gateInput);
      RegisterManualProfitCloseCandidates(basket,profitCloseCandidate,gateInput);

      CStrategyDecisionCommandMapper mapper;
      ICommand *mappedCommands[];
      CResult<int> mapResult=mapper.MapDecisionSet(decisions,
                                                   basket.Id(),
                                                   basket.Version(),
                                                   basket.StrategyProfileHash(),
                                                   command.CorrelationKey(),
                                                   mappedCommands);
      if(mapResult.IsFail())
         return mapResult;

      int mappedCount=0;
      mapResult.TryGetValue(mappedCount);
      if(m_queue!=NULL)
        {
         for(int i=0;i<mappedCount;i++)
           {
            if(mappedCommands[i]==NULL)
               continue;
            CCommandBase *commandBase=(CCommandBase*)mappedCommands[i];
            commandBase.SetId(CCommandId(m_idGenerator.NewGuid()));
            commandBase.SetEnqueuedAt(m_clock!=NULL ? m_clock.Now() : 0);
            m_queue.Enqueue(mappedCommands[i]);
           }
        }

      CCommandId auditCommandId=command.Id().IsEmpty() ? CCommandId(m_idGenerator.NewGuid()) : command.Id();
      CEventId auditEventId(m_idGenerator.NewGuid());
      CUtcTime timestampUtc(m_clock!=NULL ? m_clock.Now() : 0);
      basket.AppendEvaluationAudit(auditCommandId,auditEventId,timestampUtc);

      CVoidResult saveResult=m_repository.Save(basket);
      if(saveResult.IsFail())
         return CResult<int>::Fail(saveResult.ErrorCode(),saveResult.ErrorMessage());

      return CResult<int>::Ok(mappedCount);
     }

   CResult<int>      ExecuteFastPath(const CBasketAggregate &basket,
                                     const CMarketContext &market,
                                     const CRiskRuntimeContext &riskContext,
                                     ICommandQueue *stagingQueue,
                                     const string correlationKey)
     {
      CRecoveryRiskGateInput emptyGateInput;
      return ExecuteFastPathWithRiskGate(basket,market,riskContext,stagingQueue,correlationKey,emptyGateInput);
     }

   CResult<int>      ExecuteFastPathWithRiskGate(const CBasketAggregate &basket,
                                                 const CMarketContext &market,
                                                 const CRiskRuntimeContext &riskContext,
                                                 ICommandQueue *stagingQueue,
                                                 const string correlationKey,
                                                 const CRecoveryRiskGateInput &gateInput)
     {
      if(stagingQueue==NULL)
         return CResult<int>::Fail(BRE_ERR_COMMAND_INVALID,"Staging queue is required");

      CResult<CStrategyEvaluationContext> contextResult=
         CStrategyEvaluationContextFactory::TryBuild(basket,market,riskContext,m_snapshotStore);
      if(contextResult.IsFail())
         return CResult<int>::Fail(contextResult.ErrorCode(),contextResult.ErrorMessage());

      CStrategyEvaluationContext context;
      contextResult.TryGetValue(context);
      CStrategyDecisionSet decisions=m_strategyEngine.EvaluateAll(context);
      decisions=ApplyRecoveryCandidatePlanning(basket,decisions,context,gateInput);
      CProfitLevelCloseCandidate profitCloseCandidate=ApplyProfitLevelCloseCandidatePlanning(basket,context,gateInput);
      CBreakEvenCandidate breakEvenCandidate=ApplyBreakEvenCandidatePlanning(basket,context,gateInput);
      ApplyBreakEvenModificationDryRun(basket,breakEvenCandidate,gateInput);
      decisions=ApplyRecoveryRiskGate(basket,decisions,gateInput,context);
      RegisterManualRecoveryCandidates(basket,decisions,context,gateInput);
      RegisterManualProfitCloseCandidates(basket,profitCloseCandidate,gateInput);

      CStrategyDecisionCommandMapper mapper;
      ICommand *mappedCommands[];
      CResult<int> mapResult=mapper.MapDecisionSet(decisions,
                                                   basket.Id(),
                                                   basket.Version(),
                                                   basket.StrategyProfileHash(),
                                                   correlationKey,
                                                   mappedCommands);
      if(mapResult.IsFail())
         return mapResult;

      int mappedCount=0;
      mapResult.TryGetValue(mappedCount);
      for(int i=0;i<mappedCount;i++)
        {
         if(mappedCommands[i]==NULL)
            continue;
         CCommandBase *commandBase=(CCommandBase*)mappedCommands[i];
         commandBase.SetId(CCommandId(m_idGenerator.NewGuid()));
         commandBase.SetEnqueuedAt(m_clock!=NULL ? m_clock.Now() : 0);
         stagingQueue.Enqueue(mappedCommands[i]);
        }

      return CResult<int>::Ok(mappedCount);
     }
  };

#endif
