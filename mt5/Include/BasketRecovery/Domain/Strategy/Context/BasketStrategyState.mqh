#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_BASKET_STRATEGY_STATE_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_BASKET_STRATEGY_STATE_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CBasketStrategyState
  {
private:
   CBasketId                 m_basketId;
   ENUM_BRE_TRADE_DIRECTION  m_direction;
   double                    m_signalRangeLow;
   double                    m_signalRangeHigh;
   double                    m_anchorPrice;
   int                       m_currentRecoveryStepIndex;
   bool                      m_recoveryDisabled;
   bool                      m_breakEvenActivated;
   bool                      m_manualBreakEvenRequested;
   string                    m_executedBreakEvenRuleIds[];

public:
                     CBasketStrategyState(void) {}

                     CBasketStrategyState(const CBasketStrategyState &other)
     {
      m_basketId=other.m_basketId;
      m_direction=other.m_direction;
      m_signalRangeLow=other.m_signalRangeLow;
      m_signalRangeHigh=other.m_signalRangeHigh;
      m_anchorPrice=other.m_anchorPrice;
      m_currentRecoveryStepIndex=other.m_currentRecoveryStepIndex;
      m_recoveryDisabled=other.m_recoveryDisabled;
      m_breakEvenActivated=other.m_breakEvenActivated;
      m_manualBreakEvenRequested=other.m_manualBreakEvenRequested;
      int ruleCount=ArraySize(other.m_executedBreakEvenRuleIds);
      ArrayResize(m_executedBreakEvenRuleIds,ruleCount);
      for(int i=0;i<ruleCount;i++)
         m_executedBreakEvenRuleIds[i]=other.m_executedBreakEvenRuleIds[i];
     }

   CBasketId                 BasketId(void) const { return m_basketId; }
   ENUM_BRE_TRADE_DIRECTION  Direction(void) const { return m_direction; }
   double                    SignalRangeLow(void) const { return m_signalRangeLow; }
   double                    SignalRangeHigh(void) const { return m_signalRangeHigh; }
   double                    AnchorPrice(void) const { return m_anchorPrice; }
   int                       CurrentRecoveryStepIndex(void) const { return m_currentRecoveryStepIndex; }
   bool                      RecoveryDisabled(void) const { return m_recoveryDisabled; }
   bool                      BreakEvenActivated(void) const { return m_breakEvenActivated; }
   bool                      ManualBreakEvenRequested(void) const { return m_manualBreakEvenRequested; }

   bool                      HasExecutedBreakEvenRule(const string ruleId) const
     {
      for(int i=0;i<ArraySize(m_executedBreakEvenRuleIds);i++)
        {
         if(m_executedBreakEvenRuleIds[i]==ruleId)
            return true;
        }
      return false;
     }

   static CBasketStrategyState Create(const CBasketId &basketId,
                                      const ENUM_BRE_TRADE_DIRECTION direction,
                                      const double signalRangeLow,
                                      const double signalRangeHigh,
                                      const double anchorPrice,
                                      const int currentRecoveryStepIndex,
                                      const bool recoveryDisabled,
                                      const bool breakEvenActivated,
                                      const bool manualBreakEvenRequested,
                                      const string &executedBreakEvenRuleIds[],
                                      const int executedRuleCount)
     {
      CBasketStrategyState state;
      state.m_basketId=basketId;
      state.m_direction=direction;
      state.m_signalRangeLow=signalRangeLow;
      state.m_signalRangeHigh=signalRangeHigh;
      state.m_anchorPrice=anchorPrice;
      state.m_currentRecoveryStepIndex=currentRecoveryStepIndex;
      state.m_recoveryDisabled=recoveryDisabled;
      state.m_breakEvenActivated=breakEvenActivated;
      state.m_manualBreakEvenRequested=manualBreakEvenRequested;
      ArrayResize(state.m_executedBreakEvenRuleIds,executedRuleCount);
      for(int i=0;i<executedRuleCount;i++)
         state.m_executedBreakEvenRuleIds[i]=executedBreakEvenRuleIds[i];
      return state;
     }

   static CBasketStrategyState Create(const CBasketId &basketId,
                                      const ENUM_BRE_TRADE_DIRECTION direction,
                                      const double signalRangeLow,
                                      const double signalRangeHigh,
                                      const double anchorPrice,
                                      const int currentRecoveryStepIndex,
                                      const bool recoveryDisabled,
                                      const bool breakEvenActivated,
                                      const bool manualBreakEvenRequested)
     {
      string emptyRules[];
      ArrayResize(emptyRules,0);
      return Create(basketId,direction,signalRangeLow,signalRangeHigh,anchorPrice,currentRecoveryStepIndex,
                    recoveryDisabled,breakEvenActivated,manualBreakEvenRequested,emptyRules,0);
     }
  };

#endif
