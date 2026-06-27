#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_EVALUATION_CONTEXT_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_EVALUATION_CONTEXT_MQH

#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/BasketStrategyState.mqh>
#include <BasketRecovery/Domain/Strategy/Context/ProfitLevelRuntimeState.mqh>
#include <BasketRecovery/Domain/Strategy/Context/RiskRuntimeContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/PositionRuntimeView.mqh>

class CStrategyEvaluationContext
  {
private:
   CStrategyProfile            m_profile;
   CMarketContext              m_market;
   CBasketStrategyState        m_basketState;
   CRiskRuntimeContext         m_riskContext;
   CProfitLevelRuntimeState    m_profitLevelStates[];
   CPositionRuntimeView        m_positions[];
   double                      m_adverseMovePips;
   double                      m_floatingProfitUsd;

                     CStrategyEvaluationContext(void) {}

public:
   CStrategyProfile            Profile(void) const { return m_profile; }
   CMarketContext              Market(void) const { return m_market; }
   CBasketStrategyState        BasketState(void) const { return m_basketState; }
   CRiskRuntimeContext         RiskContext(void) const { return m_riskContext; }
   double                      AdverseMovePips(void) const { return m_adverseMovePips; }
   double                      FloatingProfitUsd(void) const { return m_floatingProfitUsd; }
   int                         ProfitLevelStateCount(void) const { return ArraySize(m_profitLevelStates); }
   int                         PositionCount(void) const { return ArraySize(m_positions); }

   CProfitLevelRuntimeState    ProfitLevelStateAt(const int index) const
     {
      if(index<0 || index>=ArraySize(m_profitLevelStates))
         return CProfitLevelRuntimeState::Create("",false,false,0.0,false);
      return m_profitLevelStates[index];
     }

   CPositionRuntimeView        PositionAt(const int index) const
     {
      if(index<0 || index>=ArraySize(m_positions))
         return CPositionRuntimeView::Create(0,0.0,0.0,0.0,0.0,0,BRE_DIRECTION_NONE,BRE_TRADE_ROLE_NONE);
      return m_positions[index];
     }

   bool                        FindProfitLevelState(const string levelId,CProfitLevelRuntimeState &outState) const
     {
      for(int i=0;i<ArraySize(m_profitLevelStates);i++)
        {
         if(m_profitLevelStates[i].LevelId()==levelId)
           {
            outState=m_profitLevelStates[i];
            return true;
           }
        }
      return false;
     }

   static CStrategyEvaluationContext Create(const CStrategyProfile &profile,
                                            const CMarketContext &market,
                                            const CBasketStrategyState &basketState,
                                            const CRiskRuntimeContext &riskContext,
                                            const CProfitLevelRuntimeState &profitLevelStates[],
                                            const int profitLevelStateCount,
                                            const CPositionRuntimeView &positions[],
                                            const int positionCount,
                                            const double adverseMovePips,
                                            const double floatingProfitUsd)
     {
      CStrategyEvaluationContext context;
      context.m_profile=profile;
      context.m_market=market;
      context.m_basketState=basketState;
      context.m_riskContext=riskContext;
      context.m_adverseMovePips=adverseMovePips;
      context.m_floatingProfitUsd=floatingProfitUsd;
      ArrayResize(context.m_profitLevelStates,profitLevelStateCount);
      for(int i=0;i<profitLevelStateCount;i++)
         context.m_profitLevelStates[i]=profitLevelStates[i];
      ArrayResize(context.m_positions,positionCount);
      for(int i=0;i<positionCount;i++)
         context.m_positions[i]=positions[i];
      return context;
     }
  };

#endif
