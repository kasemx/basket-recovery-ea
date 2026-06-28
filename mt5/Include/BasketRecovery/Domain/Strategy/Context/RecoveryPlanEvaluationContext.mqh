#ifndef BRE_DOMAIN_RECOVERY_PLAN_EVALUATION_CONTEXT_MQH
#define BRE_DOMAIN_RECOVERY_PLAN_EVALUATION_CONTEXT_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/BasketStrategyState.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryStepState.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>

class CRecoveryPlanEvaluationContext
  {
private:
   CBasketId                         m_basketId;
   long                              m_basketVersion;
   string                            m_strategyProfileHash;
   string                            m_symbol;
   ENUM_BRE_TRADE_DIRECTION          m_direction;
   ENUM_BRE_BASKET_LIFECYCLE_STATE   m_lifecycleState;
   bool                              m_recoveryActive;
   bool                              m_recoveryPermanentlyDisabled;
   bool                              m_basketLocked;
   double                            m_basketStopLoss;
   CStrategyProfile                  m_profile;
   CMarketContext                    m_market;
   CBasketStrategyState              m_basketState;
   CRecoveryStepState                m_stepState;
   CSymbolTradingConstraints         m_constraints;
   ulong                             m_quoteSequence;
   int                               m_quoteFreshnessAgeMs;
   int                               m_quoteStaleThresholdMs;
   bool                              m_unresolvedPendingExecution;
   bool                              m_profileValid;
   bool                              m_marketSessionValid;
   datetime                          m_timestampUtc;

public:
                     CRecoveryPlanEvaluationContext(void) {}

   CBasketId                         BasketId(void) const { return m_basketId; }
   long                              BasketVersion(void) const { return m_basketVersion; }
   string                            StrategyProfileHash(void) const { return m_strategyProfileHash; }
   string                            Symbol(void) const { return m_symbol; }
   ENUM_BRE_TRADE_DIRECTION          Direction(void) const { return m_direction; }
   ENUM_BRE_BASKET_LIFECYCLE_STATE   LifecycleState(void) const { return m_lifecycleState; }
   bool                              RecoveryActive(void) const { return m_recoveryActive; }
   bool                              RecoveryPermanentlyDisabled(void) const { return m_recoveryPermanentlyDisabled; }
   bool                              BasketLocked(void) const { return m_basketLocked; }
   double                            BasketStopLoss(void) const { return m_basketStopLoss; }
   CStrategyProfile                  Profile(void) const { return m_profile; }
   CMarketContext                    Market(void) const { return m_market; }
   CBasketStrategyState              BasketState(void) const { return m_basketState; }
   CRecoveryStepState                StepState(void) const { return m_stepState; }
   CSymbolTradingConstraints         Constraints(void) const { return m_constraints; }
   ulong                             QuoteSequence(void) const { return m_quoteSequence; }
   int                               QuoteFreshnessAgeMs(void) const { return m_quoteFreshnessAgeMs; }
   int                               QuoteStaleThresholdMs(void) const { return m_quoteStaleThresholdMs; }
   bool                              UnresolvedPendingExecution(void) const { return m_unresolvedPendingExecution; }
   bool                              ProfileValid(void) const { return m_profileValid; }
   bool                              MarketSessionValid(void) const { return m_marketSessionValid; }
   datetime                          TimestampUtc(void) const { return m_timestampUtc; }

   static CRecoveryPlanEvaluationContext Create(const CBasketId &basketId,
                                                const long basketVersion,
                                                const string strategyProfileHash,
                                                const string symbol,
                                                const ENUM_BRE_TRADE_DIRECTION direction,
                                                const ENUM_BRE_BASKET_LIFECYCLE_STATE lifecycleState,
                                                const bool recoveryActive,
                                                const bool recoveryPermanentlyDisabled,
                                                const bool basketLocked,
                                                const double basketStopLoss,
                                                const CStrategyProfile &profile,
                                                const CMarketContext &market,
                                                const CBasketStrategyState &basketState,
                                                const CRecoveryStepState &stepState,
                                                const CSymbolTradingConstraints &constraints,
                                                const ulong quoteSequence,
                                                const int quoteFreshnessAgeMs,
                                                const int quoteStaleThresholdMs,
                                                const bool unresolvedPendingExecution,
                                                const bool profileValid,
                                                const bool marketSessionValid,
                                                const datetime timestampUtc)
     {
      CRecoveryPlanEvaluationContext ctx;
      ctx.m_basketId=basketId;
      ctx.m_basketVersion=basketVersion;
      ctx.m_strategyProfileHash=strategyProfileHash;
      ctx.m_symbol=symbol;
      ctx.m_direction=direction;
      ctx.m_lifecycleState=lifecycleState;
      ctx.m_recoveryActive=recoveryActive;
      ctx.m_recoveryPermanentlyDisabled=recoveryPermanentlyDisabled;
      ctx.m_basketLocked=basketLocked;
      ctx.m_basketStopLoss=basketStopLoss;
      ctx.m_profile=profile;
      ctx.m_market=market;
      ctx.m_basketState=basketState;
      ctx.m_stepState=stepState;
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
