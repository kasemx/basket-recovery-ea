#ifndef BRE_DOMAIN_RECOVERY_TRIGGER_EVALUATOR_MQH
#define BRE_DOMAIN_RECOVERY_TRIGGER_EVALUATOR_MQH

#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CRecoveryTriggerEvaluation
  {
private:
   double m_referencePrice;
   double m_executablePrice;
   double m_adverseMovePips;
   double m_requiredDistancePips;
   bool   m_isDue;
   bool   m_favorableMovement;

public:
   double            ReferencePrice(void) const { return m_referencePrice; }
   double            ExecutablePrice(void) const { return m_executablePrice; }
   double            AdverseMovePips(void) const { return m_adverseMovePips; }
   double            RequiredDistancePips(void) const { return m_requiredDistancePips; }
   bool              IsDue(void) const { return m_isDue; }
   bool              FavorableMovement(void) const { return m_favorableMovement; }

   static CRecoveryTriggerEvaluation Create(const double referencePrice,
                                            const double executablePrice,
                                            const double adverseMovePips,
                                            const double requiredDistancePips,
                                            const bool isDue,
                                            const bool favorableMovement)
     {
      CRecoveryTriggerEvaluation evaluation;
      evaluation.m_referencePrice=referencePrice;
      evaluation.m_executablePrice=executablePrice;
      evaluation.m_adverseMovePips=adverseMovePips;
      evaluation.m_requiredDistancePips=requiredDistancePips;
      evaluation.m_isDue=isDue;
      evaluation.m_favorableMovement=favorableMovement;
      return evaluation;
     }
  };

class CRecoveryTriggerEvaluator
  {
public:
   static double     InitialBasketReferencePrice(const ENUM_BRE_TRADE_DIRECTION direction,
                                                   const double signalRangeLow,
                                                   const double signalRangeHigh)
     {
      if(direction==BRE_DIRECTION_BUY)
         return signalRangeHigh;
      if(direction==BRE_DIRECTION_SELL)
         return signalRangeLow;
      return (signalRangeLow+signalRangeHigh)*0.5;
     }

   static double     ExecutablePrice(const ENUM_BRE_TRADE_DIRECTION direction,
                                     const double bid,
                                     const double ask)
     {
      if(direction==BRE_DIRECTION_BUY)
         return ask;
      if(direction==BRE_DIRECTION_SELL)
         return bid;
      return bid;
     }

   static double     ComputeAdverseMovePips(const ENUM_BRE_TRADE_DIRECTION direction,
                                              const double referencePrice,
                                              const double bid,
                                              const double ask,
                                              const double pipSize)
     {
      double safePip=MathMax(pipSize,0.0000001);
      double executable=ExecutablePrice(direction,bid,ask);
      if(direction==BRE_DIRECTION_BUY)
         return (referencePrice-executable)/safePip;
      if(direction==BRE_DIRECTION_SELL)
         return (executable-referencePrice)/safePip;
      return 0.0;
     }

   static CRecoveryTriggerEvaluation Evaluate(const ENUM_BRE_TRADE_DIRECTION direction,
                                                const double triggerReferencePrice,
                                                const double bid,
                                                const double ask,
                                                const double pipSize,
                                                const double requiredDistancePips)
     {
      double executable=ExecutablePrice(direction,bid,ask);
      double adverseMove=ComputeAdverseMovePips(direction,triggerReferencePrice,bid,ask,pipSize);
      bool favorable=adverseMove<0.0;
      bool isDue=!favorable && adverseMove+0.0000001>=requiredDistancePips;
      return CRecoveryTriggerEvaluation::Create(triggerReferencePrice,executable,adverseMove,requiredDistancePips,isDue,favorable);
     }
  };

#endif
