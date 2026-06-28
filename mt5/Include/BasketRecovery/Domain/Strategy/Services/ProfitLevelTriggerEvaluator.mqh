#ifndef BRE_DOMAIN_PROFIT_LEVEL_TRIGGER_EVALUATOR_MQH
#define BRE_DOMAIN_PROFIT_LEVEL_TRIGGER_EVALUATOR_MQH

#include <BasketRecovery/Domain/Strategy/Context/ProfitLevelEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevel.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ProfitLevelTriggerResolver.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CProfitLevelTriggerEvaluation
  {
private:
   bool                              m_reached;
   bool                              m_supported;
   ENUM_BRE_PROFIT_LEVEL_TRIGGER_TYPE m_triggerType;
   double                            m_triggerValue;

public:
                     CProfitLevelTriggerEvaluation(void)
     {
      m_reached=false;
      m_supported=false;
      m_triggerType=BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE;
      m_triggerValue=0.0;
     }

   bool                              Reached(void) const { return m_reached; }
   bool                              Supported(void) const { return m_supported; }
   ENUM_BRE_PROFIT_LEVEL_TRIGGER_TYPE TriggerType(void) const { return m_triggerType; }
   double                            TriggerValue(void) const { return m_triggerValue; }

   static CProfitLevelTriggerEvaluation Create(const bool reached,
                                                 const bool supported,
                                                 const ENUM_BRE_PROFIT_LEVEL_TRIGGER_TYPE triggerType,
                                                 const double triggerValue)
     {
      CProfitLevelTriggerEvaluation evaluation;
      evaluation.m_reached=reached;
      evaluation.m_supported=supported;
      evaluation.m_triggerType=triggerType;
      evaluation.m_triggerValue=triggerValue;
      return evaluation;
     }
  };

class CProfitLevelTriggerEvaluator
  {
private:
   static double     ExecutableClosePrice(const CProfitLevelEvaluationContext &ctx)
     {
      if(ctx.Direction()==BRE_DIRECTION_BUY)
         return ctx.Market().Bid();
      if(ctx.Direction()==BRE_DIRECTION_SELL)
         return ctx.Market().Ask();
      return 0.0;
     }

   static bool       IsPriceLevelReached(const CProfitLevelEvaluationContext &ctx,const double levelPrice)
     {
      if(levelPrice<=0.0)
         return false;
      double executable=ExecutableClosePrice(ctx);
      if(ctx.Direction()==BRE_DIRECTION_BUY)
         return executable>=levelPrice;
      if(ctx.Direction()==BRE_DIRECTION_SELL)
         return executable<=levelPrice;
      return false;
     }

public:
   static CProfitLevelTriggerEvaluation Evaluate(const CProfitLevelEvaluationContext &ctx,
                                                 const CProfitLevel &level)
     {
      CProfitLevelTriggerResolution resolution=CProfitLevelTriggerResolver::Resolve(level);
      if(!resolution.Supported())
         return CProfitLevelTriggerEvaluation::Create(false,false,resolution.Type(),resolution.Value());

      if(!resolution.HasValue() && resolution.Type()!=BRE_PROFIT_LEVEL_TRIGGER_STRATEGY_PRICE_LEVEL)
         return CProfitLevelTriggerEvaluation::Create(false,false,resolution.Type(),resolution.Value());

      double floatingProfit=ctx.FloatingProfitUsd();
      bool reached=false;
      switch(resolution.Type())
        {
         case BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY:
            reached=floatingProfit>=resolution.Value();
            break;
         case BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_PCT_TARGET_RISK:
           {
            double threshold=ctx.TargetRiskMoney()*resolution.Value()/100.0;
            reached=threshold>0.0 && floatingProfit>=threshold;
            break;
           }
         case BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_PCT_EQUITY:
           {
            double threshold=ctx.Equity()*resolution.Value()/100.0;
            reached=threshold>0.0 && floatingProfit>=threshold;
            break;
           }
         case BRE_PROFIT_LEVEL_TRIGGER_STRATEGY_PRICE_LEVEL:
            reached=IsPriceLevelReached(ctx,resolution.Value());
            break;
         default:
            return CProfitLevelTriggerEvaluation::Create(false,false,resolution.Type(),resolution.Value());
        }

      return CProfitLevelTriggerEvaluation::Create(reached,true,resolution.Type(),resolution.Value());
     }
  };

#endif
