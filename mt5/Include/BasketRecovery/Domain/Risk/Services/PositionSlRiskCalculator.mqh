#ifndef BRE_DOMAIN_POSITION_SL_RISK_CALCULATOR_MQH
#define BRE_DOMAIN_POSITION_SL_RISK_CALCULATOR_MQH

#include <BasketRecovery/Domain/Risk/Services/SlRiskMath.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/PositionRiskSnapshot.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskCalculationContext.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>

class CPositionSlRiskCalculator
  {
public:
   static CPositionRiskSnapshot Calculate(const CPositionSnapshotEntry &entry,
                                          const CRiskCalculationContext &context)
     {
      const CMarketQuote quote=context.Quote();
      const CRiskCalculationSettings settings=context.Settings();
      double effectiveSl=context.BasketStopLoss();
      if(effectiveSl<=0.0)
         return CPositionRiskSnapshot::Unknown(entry.Ticket(),entry.Symbol());

      double spreadBuffer=0.0;
      if(settings.IncludeSpreadBuffer())
         spreadBuffer=quote.SpreadPoints()*quote.Point()*settings.SpreadBufferMultiplier();

      double worstLoss=0.0;
      if(!CSlRiskMath::TryWorstCaseLossAtSl(entry.EntryPrice(),
                                            effectiveSl,
                                            entry.Volume(),
                                            quote.TickSize(),
                                            quote.TickValue(),
                                            entry.Commission(),
                                            entry.Swap(),
                                            settings,
                                            spreadBuffer,
                                            worstLoss))
         return CPositionRiskSnapshot::Unknown(entry.Ticket(),entry.Symbol());

      return CPositionRiskSnapshot::Create(entry.Ticket(),
                                           entry.Symbol(),
                                           entry.Direction(),
                                           entry.EntryPrice(),
                                           entry.Volume(),
                                           effectiveSl,
                                           entry.Commission(),
                                           entry.Swap(),
                                           entry.FloatingProfit(),
                                           worstLoss,
                                           BRE_RISK_SAFETY_SAFE);
     }

   static CPositionRiskSnapshot CalculateProposed(const ENUM_BRE_TRADE_DIRECTION direction,
                                                  const double entryPrice,
                                                  const double volume,
                                                  const CRiskCalculationContext &context)
     {
      const CMarketQuote quote=context.Quote();
      const CRiskCalculationSettings settings=context.Settings();
      double effectiveSl=context.BasketStopLoss();
      if(effectiveSl<=0.0 || entryPrice<=0.0 || volume<=0.0)
         return CPositionRiskSnapshot::Unknown(0,quote.Symbol());

      double spreadBuffer=0.0;
      if(settings.IncludeSpreadBuffer())
         spreadBuffer=quote.SpreadPoints()*quote.Point()*settings.SpreadBufferMultiplier();

      double worstLoss=0.0;
      if(!CSlRiskMath::TryWorstCaseLossAtSl(entryPrice,
                                            effectiveSl,
                                            volume,
                                            quote.TickSize(),
                                            quote.TickValue(),
                                            0.0,
                                            0.0,
                                            settings,
                                            spreadBuffer,
                                            worstLoss))
         return CPositionRiskSnapshot::Unknown(0,quote.Symbol());

      return CPositionRiskSnapshot::Create(0,
                                           quote.Symbol(),
                                           direction,
                                           entryPrice,
                                           volume,
                                           effectiveSl,
                                           0.0,
                                           0.0,
                                           0.0,
                                           worstLoss,
                                           BRE_RISK_SAFETY_SAFE);
     }
  };

#endif
