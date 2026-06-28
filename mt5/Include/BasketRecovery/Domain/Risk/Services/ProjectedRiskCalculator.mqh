#ifndef BRE_DOMAIN_PROJECTED_RISK_CALCULATOR_MQH
#define BRE_DOMAIN_PROJECTED_RISK_CALCULATOR_MQH

#include <BasketRecovery/Domain/Risk/Services/PositionSlRiskCalculator.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/ProjectedBasketRisk.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>

class CProjectedRiskCalculator
  {
private:
   static double     ResolveProposedEntryPrice(const ENUM_BRE_TRADE_DIRECTION direction,
                                                 const CMarketQuote &quote,
                                                 const CTradeExecutionRequest &request)
     {
      if(request.RequestedPrice()>0.0)
         return request.RequestedPrice();
      if(direction==BRE_DIRECTION_BUY)
         return quote.Ask();
      if(direction==BRE_DIRECTION_SELL)
         return quote.Bid();
      return 0.0;
     }

public:
   static CProjectedBasketRisk ProjectForRequest(const CBasketRiskSnapshot &current,
                                                 const CTradeExecutionRequest &request,
                                                 const CRiskCalculationContext &context)
     {
      if(!current.IsSafe())
         return CProjectedBasketRisk::Create(current,0.0,0.0,BRE_RISK_SAFETY_UNKNOWN);

      if(request.IntentType()!=BRE_EXEC_INTENT_OPEN_POSITION)
         return CProjectedBasketRisk::Create(current,0.0,current.CurrentSlRiskMoney(),BRE_RISK_SAFETY_SAFE);

      const CMarketQuote quote=context.Quote();
      double entryPrice=ResolveProposedEntryPrice(request.Direction(),quote,request);
      CPositionRiskSnapshot proposed=CPositionSlRiskCalculator::CalculateProposed(request.Direction(),
                                                                                entryPrice,
                                                                                request.RequestedVolume(),
                                                                                context);
      if(!proposed.IsSafe())
         return CProjectedBasketRisk::Create(current,0.0,0.0,BRE_RISK_SAFETY_UNKNOWN);

      double projected=current.CurrentSlRiskMoney()+proposed.WorstCaseLossAtSl();
      return CProjectedBasketRisk::Create(current,
                                          proposed.WorstCaseLossAtSl(),
                                          projected,
                                          BRE_RISK_SAFETY_SAFE);
     }
  };

#endif
