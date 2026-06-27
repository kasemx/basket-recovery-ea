#ifndef BASKET_RECOVERY_APPLICATION_ISTRATEGY_ENGINE_MQH
#define BASKET_RECOVERY_APPLICATION_ISTRATEGY_ENGINE_MQH

#include <BasketRecovery/Domain/Strategy/Context/StrategyEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecisionSet.mqh>
#include <BasketRecovery/Domain/Strategy/Services/StrategyEngine.mqh>

class IStrategyEngine
  {
public:
   virtual          ~IStrategyEngine(void) {}
   virtual CStrategyDecisionSet EvaluateRecovery(const CStrategyEvaluationContext &context) const=0;
   virtual CStrategyDecisionSet EvaluateProfitDistribution(const CStrategyEvaluationContext &context) const=0;
   virtual CStrategyDecisionSet EvaluateBreakEven(const CStrategyEvaluationContext &context) const=0;
   virtual CStrategyDecisionSet EvaluateRiskReduction(const CStrategyEvaluationContext &context) const=0;
   virtual CStrategyDecisionSet EvaluateAll(const CStrategyEvaluationContext &context) const=0;
  };

class CStrategyEngineAdapter : public IStrategyEngine
  {
private:
   CStrategyEngine m_engine;

public:
   virtual CStrategyDecisionSet EvaluateRecovery(const CStrategyEvaluationContext &context) const
     {
      return m_engine.EvaluateRecovery(context);
     }

   virtual CStrategyDecisionSet EvaluateProfitDistribution(const CStrategyEvaluationContext &context) const
     {
      return m_engine.EvaluateProfitDistribution(context);
     }

   virtual CStrategyDecisionSet EvaluateBreakEven(const CStrategyEvaluationContext &context) const
     {
      return m_engine.EvaluateBreakEven(context);
     }

   virtual CStrategyDecisionSet EvaluateRiskReduction(const CStrategyEvaluationContext &context) const
     {
      return m_engine.EvaluateRiskReduction(context);
     }

   virtual CStrategyDecisionSet EvaluateAll(const CStrategyEvaluationContext &context) const
     {
      return m_engine.EvaluateAll(context);
     }
  };

#endif
