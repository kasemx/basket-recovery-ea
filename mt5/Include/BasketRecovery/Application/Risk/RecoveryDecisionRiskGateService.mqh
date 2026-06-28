#ifndef BRE_APP_RECOVERY_DECISION_RISK_GATE_SERVICE_MQH
#define BRE_APP_RECOVERY_DECISION_RISK_GATE_SERVICE_MQH

#include <BasketRecovery/Application/Risk/RecoveryProposedTradeRequestBuilder.mqh>
#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Application/Risk/RecoveryRiskEventBuffer.mqh>
#include <BasketRecovery/Application/Risk/BasketRiskReadModelService.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshot.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskLimitProfile.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskCalculationContext.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskCalculationSettings.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Domain/Risk/Services/RecoveryDecisionRiskValidator.mqh>
#include <BasketRecovery/Domain/Risk/Services/RiskReductionPlanner.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskGatedStrategyDecision.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecisionSet.mqh>
#include <BasketRecovery/Domain/Strategy/Context/StrategyRiskEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/StrategyDecisionType.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Market/AccountContextSnapshot.mqh>
#include <BasketRecovery/Domain/Events/RecoveryRiskDomainEvent.mqh>

class CRecoveryRiskGateInput
  {
private:
   CMarketQuote              m_quote;
   CAccountContextSnapshot   m_account;
   ulong                     m_quoteSequence;
   int                       m_quoteStaleThresholdMs;
   string                    m_expectedStrategyProfileHash;
   string                    m_correlationKey;
   datetime                  m_timestampUtc;
   bool                      m_hasQuote;

public:
                     CRecoveryRiskGateInput(void)
     {
      m_quoteSequence=0;
      m_quoteStaleThresholdMs=5000;
      m_timestampUtc=0;
      m_hasQuote=false;
     }

   bool              HasQuote(void) const { return m_hasQuote; }
   CMarketQuote      Quote(void) const { return m_quote; }
   CAccountContextSnapshot Account(void) const { return m_account; }
   ulong             QuoteSequence(void) const { return m_quoteSequence; }
   int               QuoteStaleThresholdMs(void) const { return m_quoteStaleThresholdMs; }
   string            ExpectedStrategyProfileHash(void) const { return m_expectedStrategyProfileHash; }
   string            CorrelationKey(void) const { return m_correlationKey; }
   datetime          TimestampUtc(void) const { return m_timestampUtc; }

   static CRecoveryRiskGateInput Create(const CMarketQuote &quote,
                                        const CAccountContextSnapshot &account,
                                        const ulong quoteSequence,
                                        const int quoteStaleThresholdMs,
                                        const string expectedStrategyProfileHash,
                                        const string correlationKey,
                                        const datetime timestampUtc)
     {
      CRecoveryRiskGateInput created;
      created.m_quote=quote;
      created.m_account=account;
      created.m_quoteSequence=quoteSequence;
      created.m_quoteStaleThresholdMs=quoteStaleThresholdMs;
      created.m_expectedStrategyProfileHash=expectedStrategyProfileHash;
      created.m_correlationKey=correlationKey;
      created.m_timestampUtc=timestampUtc;
      created.m_hasQuote=true;
      return created;
     }
  };

class CRecoveryDecisionRiskGateService
  {
private:
   IPositionSnapshotStore       *m_snapshotStore;
   CPendingExecutionRegistry    *m_pendingRegistry;
   CRecoveryRiskEventBuffer     *m_eventBuffer;
   int                           m_quoteStaleThresholdMs;

   void              EmitGateEvents(const CBasketAggregate &basket,
                                    const CRecoveryDecisionRiskGateResult &result,
                                    const CRecoveryRiskGateInput &gateInput)
     {
      if(m_eventBuffer==NULL)
         return;

      CRecoveryRiskDecisionAudit audit=result.Audit();
      if(result.Allowed())
        {
         CRecoveryRiskDomainEvent validated=CRecoveryRiskDomainEvent::CreateValidated(basket.Id(),
                                                                                       gateInput.CorrelationKey(),
                                                                                       gateInput.TimestampUtc(),
                                                                                       audit,
                                                                                       gateInput.QuoteSequence());
         m_eventBuffer.TryEmit(validated);
         if(result.HasReductionSuggestion())
           {
            CRecoveryRiskDomainEvent suggested=CRecoveryRiskDomainEvent::CreateReductionSuggested(basket.Id(),
                                                                                                  gateInput.CorrelationKey(),
                                                                                                  gateInput.TimestampUtc(),
                                                                                                  audit,
                                                                                                  gateInput.QuoteSequence());
            m_eventBuffer.TryEmit(suggested);
           }
         return;
        }

      CRecoveryRiskDomainEvent blocked=CRecoveryRiskDomainEvent::CreateBlocked(basket.Id(),
                                                                             gateInput.CorrelationKey(),
                                                                             gateInput.TimestampUtc(),
                                                                             audit,
                                                                             gateInput.QuoteSequence());
      m_eventBuffer.TryEmit(blocked);
     }

public:
                     CRecoveryDecisionRiskGateService(IPositionSnapshotStore *snapshotStore,
                                                      CPendingExecutionRegistry *pendingRegistry,
                                                      CRecoveryRiskEventBuffer *eventBuffer,
                                                      const int quoteStaleThresholdMs=5000)
     {
      m_snapshotStore=snapshotStore;
      m_pendingRegistry=pendingRegistry;
      m_eventBuffer=eventBuffer;
      m_quoteStaleThresholdMs=quoteStaleThresholdMs;
     }

   CStrategyRiskEvaluationContext BuildRiskContext(const CBasketAggregate &basket,
                                                   const CMarketQuote &quote,
                                                   const CAccountContextSnapshot &account,
                                                   const ulong quoteSequence)
     {
      bool unresolved=m_pendingRegistry!=NULL &&
                      CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(*m_pendingRegistry,basket.Id());
      CBasketRiskSnapshot snapshot=CBasketRiskReadModelService::TryCalculateBasketRisk(basket,
                                                                                       quote,
                                                                                       account,
                                                                                       m_snapshotStore,
                                                                                       CRiskCalculationSettings::CreateDefault());
      CStrategyProfile profile;
      basket.StrategyProfile(profile);
      CRiskLimitProfile riskProfile=CRiskLimitProfile::FromRiskPlan(profile.StrategyId(),profile.RiskPlan());
      CRiskCalculationContext context=CRiskCalculationContext::Create(account,
                                                                      quote,
                                                                      riskProfile,
                                                                      basket.SignalDetails().StopLoss().Value(),
                                                                      basket.Direction(),
                                                                      CRiskCalculationSettings::CreateDefault());
      CRiskReductionPlan reductionPlan=CRiskReductionPlanner::Plan(snapshot,context);
      return CStrategyRiskEvaluationContext::Create(riskProfile,
                                                    snapshot,
                                                    basket.SignalDetails().StopLoss().Value(),
                                                    quoteSequence,
                                                    unresolved,
                                                    reductionPlan,
                                                    reductionPlan.HasPlan());
     }

   CStrategyDecisionSet ApplyGate(const CBasketAggregate &basket,
                                  const CStrategyDecisionSet &decisions,
                                  const CRecoveryRiskGateInput &gateInput,
                                  CStrategyRiskEvaluationContext &outRiskContext)
     {
      CStrategyDecisionSet gated=CStrategyDecisionSet::Create();
      if(!gateInput.HasQuote())
         return decisions;

      outRiskContext=BuildRiskContext(basket,gateInput.Quote(),gateInput.Account(),gateInput.QuoteSequence());
      int staleThreshold=gateInput.QuoteStaleThresholdMs()>0 ? gateInput.QuoteStaleThresholdMs() : m_quoteStaleThresholdMs;

      CPositionSnapshotEntry entries[];
      int entryCount=0;
      if(m_snapshotStore!=NULL)
        {
         CPositionSnapshot *snapshot=m_snapshotStore.Get(basket.Id());
         if(snapshot!=NULL)
           {
            int total=snapshot.EntryCount();
            ArrayResize(entries,total);
            for(int i=0;i<total;i++)
              {
               CPositionSnapshotEntry entry;
               if(!snapshot.EntryAt(i,entry))
                  continue;
               if(entry.Status()!=BRE_POSITION_SNAPSHOT_OPEN)
                  continue;
               entries[entryCount]=entry;
               entryCount++;
              }
            if(entryCount!=total)
               ArrayResize(entries,entryCount);
           }
        }

      CStrategyProfile profile;
      basket.StrategyProfile(profile);
      CRiskLimitProfile riskProfile=CRiskLimitProfile::FromRiskPlan(profile.StrategyId(),profile.RiskPlan());
      CRiskCalculationContext calcContext=CRiskCalculationContext::Create(gateInput.Account(),
                                                                        gateInput.Quote(),
                                                                        riskProfile,
                                                                        basket.SignalDetails().StopLoss().Value(),
                                                                        basket.Direction(),
                                                                        CRiskCalculationSettings::CreateDefault());

      int decisionCount=decisions.Count();
      for(int i=0;i<decisionCount;i++)
        {
         CStrategyDecision decision=decisions.DecisionAt(i);
         if(decision.Type()!=BRE_STRATEGY_DECISION_OPEN_RECOVERY)
           {
            gated.Add(decision);
            continue;
           }

         COpenRecoveryPositionDecision openDecision=decision.OpenRecovery();
         CTradeExecutionRequest request=CRecoveryProposedTradeRequestBuilder::Build(basket,
                                                                                    openDecision,
                                                                                    gateInput.CorrelationKey(),
                                                                                    gateInput.TimestampUtc());
         CRecoveryDecisionRiskGateResult gateResult=CRecoveryDecisionRiskValidator::Validate(basket,
                                                                                             openDecision,
                                                                                             request,
                                                                                             entries,
                                                                                             entryCount,
                                                                                             calcContext,
                                                                                             outRiskContext,
                                                                                             staleThreshold,
                                                                                             gateInput.ExpectedStrategyProfileHash(),
                                                                                             gateInput.TimestampUtc());
         EmitGateEvents(basket,gateResult,gateInput);
         if(gateResult.Allowed())
            gated.Add(decision);
        }

      return gated;
     }
  };

#endif
