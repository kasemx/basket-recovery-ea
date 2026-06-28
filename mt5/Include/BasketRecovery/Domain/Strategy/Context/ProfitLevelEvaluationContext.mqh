#ifndef BRE_DOMAIN_PROFIT_LEVEL_EVALUATION_CONTEXT_MQH
#define BRE_DOMAIN_PROFIT_LEVEL_EVALUATION_CONTEXT_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/PositionRuntimeView.mqh>
#include <BasketRecovery/Domain/Basket/BasketProfitLevelProgress.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>

class CProfitLevelEvaluationContext
  {
private:
   CBasketId                         m_basketId;
   long                              m_basketVersion;
   string                            m_strategyProfileHash;
   string                            m_symbol;
   ENUM_BRE_TRADE_DIRECTION          m_direction;
   ENUM_BRE_BASKET_LIFECYCLE_STATE   m_lifecycleState;
   bool                              m_basketLocked;
   CStrategyProfile                  m_profile;
   CMarketContext                    m_market;
   CPositionRuntimeView              m_positions[];
   CBasketProfitLevelProgress        m_levelProgress[];
   double                            m_floatingProfitUsd;
   double                            m_equity;
   double                            m_targetRiskMoney;
   CSymbolTradingConstraints         m_constraints;
   ulong                             m_quoteSequence;
   int                               m_quoteFreshnessAgeMs;
   int                               m_quoteStaleThresholdMs;
   bool                              m_unresolvedPendingExecution;
   bool                              m_profileValid;
   bool                              m_marketSessionValid;
   datetime                          m_timestampUtc;

public:
                     CProfitLevelEvaluationContext(void)
     {
      m_basketVersion=0;
      m_direction=BRE_DIRECTION_NONE;
      m_lifecycleState=BRE_STATE_NONE;
      m_basketLocked=false;
      m_floatingProfitUsd=0.0;
      m_equity=0.0;
      m_targetRiskMoney=0.0;
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
   CStrategyProfile                  Profile(void) const { return m_profile; }
   CMarketContext                    Market(void) const { return m_market; }
   int                               PositionCount(void) const { return ArraySize(m_positions); }
   int                               LevelProgressCount(void) const { return ArraySize(m_levelProgress); }
   double                            FloatingProfitUsd(void) const { return m_floatingProfitUsd; }
   double                            Equity(void) const { return m_equity; }
   double                            TargetRiskMoney(void) const { return m_targetRiskMoney; }
   CSymbolTradingConstraints         Constraints(void) const { return m_constraints; }
   ulong                             QuoteSequence(void) const { return m_quoteSequence; }
   int                               QuoteFreshnessAgeMs(void) const { return m_quoteFreshnessAgeMs; }
   int                               QuoteStaleThresholdMs(void) const { return m_quoteStaleThresholdMs; }
   bool                              UnresolvedPendingExecution(void) const { return m_unresolvedPendingExecution; }
   bool                              ProfileValid(void) const { return m_profileValid; }
   bool                              MarketSessionValid(void) const { return m_marketSessionValid; }
   datetime                          TimestampUtc(void) const { return m_timestampUtc; }

   CPositionRuntimeView              PositionAt(const int index) const
     {
      if(index<0 || index>=ArraySize(m_positions))
         return CPositionRuntimeView::Create(0,0.0,0.0,0.0,0.0,0,BRE_DIRECTION_NONE,BRE_TRADE_ROLE_NONE);
      return m_positions[index];
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

   static CProfitLevelEvaluationContext Create(const CBasketId &basketId,
                                               const long basketVersion,
                                               const string strategyProfileHash,
                                               const string symbol,
                                               const ENUM_BRE_TRADE_DIRECTION direction,
                                               const ENUM_BRE_BASKET_LIFECYCLE_STATE lifecycleState,
                                               const bool basketLocked,
                                               const CStrategyProfile &profile,
                                               const CMarketContext &market,
                                               const CPositionRuntimeView &positions[],
                                               const int positionCount,
                                               const CBasketProfitLevelProgress &levelProgress[],
                                               const int levelProgressCount,
                                               const double floatingProfitUsd,
                                               const double equity,
                                               const double targetRiskMoney,
                                               const CSymbolTradingConstraints &constraints,
                                               const ulong quoteSequence,
                                               const int quoteFreshnessAgeMs,
                                               const int quoteStaleThresholdMs,
                                               const bool unresolvedPendingExecution,
                                               const bool profileValid,
                                               const bool marketSessionValid,
                                               const datetime timestampUtc)
     {
      CProfitLevelEvaluationContext ctx;
      ctx.m_basketId=basketId;
      ctx.m_basketVersion=basketVersion;
      ctx.m_strategyProfileHash=strategyProfileHash;
      ctx.m_symbol=symbol;
      ctx.m_direction=direction;
      ctx.m_lifecycleState=lifecycleState;
      ctx.m_basketLocked=basketLocked;
      ctx.m_profile=profile;
      ctx.m_market=market;
      ArrayResize(ctx.m_positions,positionCount);
      for(int i=0;i<positionCount;i++)
         ctx.m_positions[i]=positions[i];
      ArrayResize(ctx.m_levelProgress,levelProgressCount);
      for(int i=0;i<levelProgressCount;i++)
         ctx.m_levelProgress[i]=levelProgress[i];
      ctx.m_floatingProfitUsd=floatingProfitUsd;
      ctx.m_equity=equity;
      ctx.m_targetRiskMoney=targetRiskMoney;
      ctx.m_constraints=constraints;
      ctx.m_quoteSequence=quoteSequence;
      ctx.m_quoteFreshnessAgeMs=quoteFreshnessAgeMs;
      ctx.m_quoteStaleThresholdMs=quoteStaleThresholdMs;
      ctx.m_unresolvedPendingExecution=unresolvedPendingExecution;
      ctx.m_profileValid=profileValid;
      ctx.m_marketSessionValid=marketSessionValid;
      ctx.m_timestampUtc=timestampUtc;
      return ctx;
     }
  };

#endif
