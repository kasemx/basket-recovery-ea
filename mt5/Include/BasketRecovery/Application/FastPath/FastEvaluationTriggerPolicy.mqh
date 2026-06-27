#ifndef BRE_APP_FAST_EVALUATION_TRIGGER_POLICY_MQH
#define BRE_APP_FAST_EVALUATION_TRIGGER_POLICY_MQH

#include <BasketRecovery/Application/Configuration/FastPathConfig.mqh>
#include <BasketRecovery/Application/FastPath/BasketFastState.mqh>
#include <BasketRecovery/Application/FastPath/MaterialQuoteChangePolicy.mqh>
#include <BasketRecovery/Application/FastPath/QuoteSequenceGuard.mqh>
#include <BasketRecovery/Application/FastPath/ForceReevaluationFlag.mqh>
#include <BasketRecovery/Application/FastPath/FastPathSkipReason.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ExecutionZoneResolver.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitDistributionPlan.mqh>

class CFastEvaluationTriggerPolicy
  {
private:
   CFastPathConfig           m_config;
   CMaterialQuoteChangePolicy m_materialPolicy;
   CQuoteSequenceGuard       m_sequenceGuard;
   CExecutionZoneResolver    m_zoneResolver;

   bool              CrossedPrice(const double previousMid,
                                  const double currentMid,
                                  const double levelPrice) const
     {
      if(levelPrice<=0.0)
         return false;
      return (previousMid<levelPrice && currentMid>=levelPrice) ||
             (previousMid>levelPrice && currentMid<=levelPrice);
     }

   bool              CrossedProfitLevel(const CBasketAggregate &basket,
                                        const double previousMid,
                                        const double currentMid) const
     {
      CStrategyProfile profile;
      if(!basket.StrategyProfile(profile))
         return false;

      CProfitDistributionPlan plan=profile.ProfitDistributionPlan();
      for(int i=0;i<plan.LevelCount();i++)
        {
         CProfitLevel level=plan.LevelAt(i);
         if(!level.Enabled() || !level.HasPrice())
            continue;

         CBasketProfitLevelProgress progress;
         if(basket.FindProfitLevelProgress(level.LevelId(),progress) && progress.CloseCompleted())
            continue;

         if(CrossedPrice(previousMid,currentMid,level.Price()))
            return true;
        }
      return false;
     }

   bool              CrossedRecoveryThreshold(const CBasketAggregate &basket,
                                              const double previousMid,
                                              const double currentMid,
                                              const double pipSize) const
     {
      CStrategyProfile profile;
      if(!basket.StrategyProfile(profile))
         return false;

      CSignalDetails details=basket.SignalDetails();
      CEffectiveRecoveryZone zone=m_zoneResolver.Resolve(profile.ExecutionZone(),
                                                         basket.Direction(),
                                                         details.RangeLow().Value(),
                                                         details.RangeHigh().Value(),
                                                         pipSize);
      return CrossedPrice(previousMid,currentMid,zone.Low()) ||
             CrossedPrice(previousMid,currentMid,zone.High());
     }

public:
                     CFastEvaluationTriggerPolicy(const CFastPathConfig &config)
     {
      m_config=config;
     }

   ENUM_BRE_FAST_PATH_SKIP_REASON ResolveSkipReason(const CBasketAggregate &basket,
                                                  CBasketFastState &state,
                                                  const double bid,
                                                  const double ask,
                                                  const double point,
                                                  const double pipSize,
                                                  const ulong quoteSequence,
                                                  const datetime nowUtc) const
     {
      if(CForceReevaluationFlag::IsSet(state))
         return BRE_FAST_SKIP_NONE;

      if(state.NextAllowedEvaluationUtc()>0 && nowUtc<state.NextAllowedEvaluationUtc())
         return BRE_FAST_SKIP_MIN_INTERVAL_GATE;

      if(m_sequenceGuard.IsDuplicateSequence(state.LastEvaluatedQuoteSequence(),quoteSequence))
         return BRE_FAST_SKIP_DUPLICATE_QUOTE_SEQUENCE;

      double currentMid=(bid+ask)*0.5;
      double previousMid=(state.LastEvaluatedBid()+state.LastEvaluatedAsk())*0.5;
      if(previousMid<=0.0)
         previousMid=currentMid;

      if(CrossedProfitLevel(basket,previousMid,currentMid))
         return BRE_FAST_SKIP_NONE;

      if(CrossedRecoveryThreshold(basket,previousMid,currentMid,pipSize))
         return BRE_FAST_SKIP_NONE;

      if(m_materialPolicy.HasMaterialChange(state.LastEvaluatedBid(),state.LastEvaluatedAsk(),
                                            bid,ask,point,m_config.MaterialQuoteChangePoints()))
         return BRE_FAST_SKIP_NONE;

      if(state.LastEvaluatedTickTimeMsc()>0)
        {
         ulong elapsedMs=(ulong)GetTickCount64()-state.LastEvaluatedTickTimeMsc();
         if(elapsedMs>=(ulong)m_config.MaxEvaluationAgeMs())
            return BRE_FAST_SKIP_NONE;
        }

      return BRE_FAST_SKIP_TRIGGER_POLICY;
     }

   bool              ShouldEvaluate(const CBasketAggregate &basket,
                                    CBasketFastState &state,
                                    const double bid,
                                    const double ask,
                                    const double point,
                                    const double pipSize,
                                    const ulong quoteSequence,
                                    const datetime nowUtc) const
     {
      return ResolveSkipReason(basket,state,bid,ask,point,pipSize,quoteSequence,nowUtc)==BRE_FAST_SKIP_NONE;
     }
  };

#endif
