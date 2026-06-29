#ifndef BRE_DOMAIN_BREAK_EVEN_EVALUATION_CONTEXT_MQH
#define BRE_DOMAIN_BREAK_EVEN_EVALUATION_CONTEXT_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/PositionRuntimeView.mqh>
#include <BasketRecovery/Domain/Strategy/Context/ProfitLevelRuntimeState.mqh>
#include <BasketRecovery/Domain/Basket/BasketProfitLevelProgress.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>

class CBreakEvenEvaluationContext
  {
private:
   CBasketId                         m_basketId;
   long                              m_basketVersion;
   string                            m_strategyProfileHash;
   string                            m_symbol;
   ENUM_BRE_TRADE_DIRECTION          m_direction;
   ENUM_BRE_BASKET_LIFECYCLE_STATE   m_lifecycleState;
   bool                              m_basketLocked;
   bool                              m_breakEvenActive;
   bool                              m_manualBreakEvenRequested;
   bool                              m_riskReductionCompleted;
   string                            m_executedBreakEvenRuleIds[];
   CStrategyProfile                  m_profile;
   CMarketContext                    m_market;
   CPositionRuntimeView              m_positions[];
   CProfitLevelRuntimeState          m_profitLevelStates[];
   CBasketProfitLevelProgress        m_levelProgress[];
   double                            m_floatingProfitUsd;
   double                            m_realizedProfitUsd;
   double                            m_equity;
   double                            m_targetRiskMoney;
   bool                              m_targetRiskReached;
   double                            m_basketStopLoss;
   double                            m_point;
   double                            m_tickSize;
   CSymbolTradingConstraints         m_constraints;
   ulong                             m_quoteSequence;
   int                               m_quoteFreshnessAgeMs;
   int                               m_quoteStaleThresholdMs;
   bool                              m_unresolvedPendingExecution;
   bool                              m_profileValid;
   bool                              m_marketSessionValid;
   datetime                          m_timestampUtc;

public:
                     CBreakEvenEvaluationContext(void)
     {
      m_basketVersion=0;
      m_direction=BRE_DIRECTION_NONE;
      m_lifecycleState=BRE_STATE_NONE;
      m_basketLocked=false;
      m_breakEvenActive=false;
      m_manualBreakEvenRequested=false;
      m_riskReductionCompleted=false;
      m_floatingProfitUsd=0.0;
      m_realizedProfitUsd=0.0;
      m_equity=0.0;
      m_targetRiskMoney=0.0;
      m_targetRiskReached=false;
      m_basketStopLoss=0.0;
      m_point=0.0;
      m_tickSize=0.0;
      m_quoteSequence=0;
      m_quoteFreshnessAgeMs=0;
      m_quoteStaleThresholdMs=0;
      m_unresolvedPendingExecution=false;
      m_profileValid=false;
      m_marketSessionValid=false;
      m_timestampUtc=0;
     }

   CBasketId                         BasketId(void) const { return m_basketId; }
   long                              BasketVersion(void) const { return m_basketVersion; }
   string                            StrategyProfileHash(void) const { return m_strategyProfileHash; }
   string                            Symbol(void) const { return m_symbol; }
   ENUM_BRE_TRADE_DIRECTION          Direction(void) const { return m_direction; }
   ENUM_BRE_BASKET_LIFECYCLE_STATE   LifecycleState(void) const { return m_lifecycleState; }
   bool                              BasketLocked(void) const { return m_basketLocked; }
   bool                              BreakEvenActive(void) const { return m_breakEvenActive; }
   bool                              ManualBreakEvenRequested(void) const { return m_manualBreakEvenRequested; }
   bool                              RiskReductionCompleted(void) const { return m_riskReductionCompleted; }
   CStrategyProfile                  Profile(void) const { return m_profile; }
   CMarketContext                    Market(void) const { return m_market; }
   int                               PositionCount(void) const { return ArraySize(m_positions); }
   double                            FloatingProfitUsd(void) const { return m_floatingProfitUsd; }
   double                            RealizedProfitUsd(void) const { return m_realizedProfitUsd; }
   double                            Equity(void) const { return m_equity; }
   double                            TargetRiskMoney(void) const { return m_targetRiskMoney; }
   bool                              TargetRiskReached(void) const { return m_targetRiskReached; }
   double                            BasketStopLoss(void) const { return m_basketStopLoss; }
   double                            Point(void) const { return m_point; }
   double                            TickSize(void) const { return m_tickSize; }
   CSymbolTradingConstraints         Constraints(void) const { return m_constraints; }
   ulong                             QuoteSequence(void) const { return m_quoteSequence; }
   int                               QuoteFreshnessAgeMs(void) const { return m_quoteFreshnessAgeMs; }
   int                               QuoteStaleThresholdMs(void) const { return m_quoteStaleThresholdMs; }
   bool                              UnresolvedPendingExecution(void) const { return m_unresolvedPendingExecution; }
   bool                              ProfileValid(void) const { return m_profileValid; }
   bool                              MarketSessionValid(void) const { return m_marketSessionValid; }
   datetime                          TimestampUtc(void) const { return m_timestampUtc; }

   bool                              HasExecutedBreakEvenRule(const string ruleId) const
     {
      for(int i=0;i<ArraySize(m_executedBreakEvenRuleIds);i++)
        {
         if(m_executedBreakEvenRuleIds[i]==ruleId)
            return true;
        }
      return false;
     }

   bool                              PositionAt(const int index,CPositionRuntimeView &outPosition) const
     {
      if(index<0 || index>=ArraySize(m_positions))
         return false;
      outPosition=m_positions[index];
      return true;
     }

   bool                              FindProfitLevelState(const string levelId,CProfitLevelRuntimeState &outState) const
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

   bool                              FindLevelProgress(const string levelId,CBasketProfitLevelProgress &outProgress) const
     {
      for(int i=0;i<ArraySize(m_levelProgress);i++)
        {
         if(m_levelProgress[i].LevelId()==levelId)
           {
            outProgress=m_levelProgress[i];
            return true;
           }
        }
      return false;
     }

   static CBreakEvenEvaluationContext  Create(const CBasketId &basketId,
                                              const long basketVersion,
                                              const string strategyProfileHash,
                                              const string symbol,
                                              const ENUM_BRE_TRADE_DIRECTION direction,
                                              const ENUM_BRE_BASKET_LIFECYCLE_STATE lifecycleState,
                                              const bool basketLocked,
                                              const bool breakEvenActive,
                                              const bool manualBreakEvenRequested,
                                              const bool riskReductionCompleted,
                                              const string &executedRuleIds[],
                                              const int executedRuleCount,
                                              const CStrategyProfile &profile,
                                              const CMarketContext &market,
                                              const CPositionRuntimeView &positions[],
                                              const int positionCount,
                                              const CProfitLevelRuntimeState &profitLevelStates[],
                                              const int profitLevelStateCount,
                                              const CBasketProfitLevelProgress &levelProgress[],
                                              const int levelProgressCount,
                                              const double floatingProfitUsd,
                                              const double realizedProfitUsd,
                                              const double equity,
                                              const double targetRiskMoney,
                                              const bool targetRiskReached,
                                              const double basketStopLoss,
                                              const double point,
                                              const double tickSize,
                                              const CSymbolTradingConstraints &constraints,
                                              const ulong quoteSequence,
                                              const int freshnessAgeMs,
                                              const int staleThresholdMs,
                                              const bool unresolvedPendingExecution,
                                              const bool profileValid,
                                              const bool marketSessionValid,
                                              const datetime timestampUtc)
     {
      CBreakEvenEvaluationContext ctx;
      ctx.m_basketId=basketId;
      ctx.m_basketVersion=basketVersion;
      ctx.m_strategyProfileHash=strategyProfileHash;
      ctx.m_symbol=symbol;
      ctx.m_direction=direction;
      ctx.m_lifecycleState=lifecycleState;
      ctx.m_basketLocked=basketLocked;
      ctx.m_breakEvenActive=breakEvenActive;
      ctx.m_manualBreakEvenRequested=manualBreakEvenRequested;
      ctx.m_riskReductionCompleted=riskReductionCompleted;
      ArrayResize(ctx.m_executedBreakEvenRuleIds,executedRuleCount);
      for(int i=0;i<executedRuleCount;i++)
         ctx.m_executedBreakEvenRuleIds[i]=executedRuleIds[i];
      ctx.m_profile=profile;
      ctx.m_market=market;
      ArrayResize(ctx.m_positions,positionCount);
      for(int i=0;i<positionCount;i++)
         ctx.m_positions[i]=positions[i];
      ArrayResize(ctx.m_profitLevelStates,profitLevelStateCount);
      for(int i=0;i<profitLevelStateCount;i++)
         ctx.m_profitLevelStates[i]=profitLevelStates[i];
      ArrayResize(ctx.m_levelProgress,levelProgressCount);
      for(int i=0;i<levelProgressCount;i++)
         ctx.m_levelProgress[i]=levelProgress[i];
      ctx.m_floatingProfitUsd=floatingProfitUsd;
      ctx.m_realizedProfitUsd=realizedProfitUsd;
      ctx.m_equity=equity;
      ctx.m_targetRiskMoney=targetRiskMoney;
      ctx.m_targetRiskReached=targetRiskReached;
      ctx.m_basketStopLoss=basketStopLoss;
      ctx.m_point=point;
      ctx.m_tickSize=tickSize;
      ctx.m_constraints=constraints;
      ctx.m_quoteSequence=quoteSequence;
      ctx.m_quoteFreshnessAgeMs=freshnessAgeMs;
      ctx.m_quoteStaleThresholdMs=staleThresholdMs;
      ctx.m_unresolvedPendingExecution=unresolvedPendingExecution;
      ctx.m_profileValid=profileValid;
      ctx.m_marketSessionValid=marketSessionValid;
      ctx.m_timestampUtc=timestampUtc;
      return ctx;
     }
  };

#endif
