#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_EXECUTION_ZONE_RESOLVER_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_EXECUTION_ZONE_RESOLVER_MQH

#include <BasketRecovery/Domain/Strategy/ValueObjects/ExecutionZone.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CEffectiveRecoveryZone
  {
private:
   double m_low;
   double m_high;

public:
                     CEffectiveRecoveryZone(void) {}

                     CEffectiveRecoveryZone(const CEffectiveRecoveryZone &other)
     {
      m_low=other.m_low;
      m_high=other.m_high;
     }

   double            Low(void) const { return m_low; }
   double            High(void) const { return m_high; }

   bool              ContainsPrice(const double price) const
     {
      return price>=m_low && price<=m_high;
     }

   static CEffectiveRecoveryZone Create(const double low,const double high)
     {
      CEffectiveRecoveryZone zone;
      zone.m_low=low;
      zone.m_high=high;
      return zone;
     }
  };

class CExecutionZoneResolver
  {
private:
   double            PipsToPrice(const double pips,const double pipSize) const
     {
      return pips*pipSize;
     }

public:
   CEffectiveRecoveryZone Resolve(const CExecutionZone &zone,
                                  const ENUM_BRE_TRADE_DIRECTION direction,
                                  const double signalRangeLow,
                                  const double signalRangeHigh,
                                  const double pipSize) const
     {
      double low=signalRangeLow;
      double high=signalRangeHigh;

      if(zone.Source()==BRE_EXECUTION_ZONE_SOURCE_FIXED_RANGE && zone.HasFixedRange())
        {
         low=zone.FixedRangeLow();
         high=zone.FixedRangeHigh();
        }

      if(!zone.ExpansionDisabled())
        {
         switch(zone.ExpansionMode())
           {
            case BRE_ZONE_EXPANSION_SYMMETRIC:
               low-=PipsToPrice(zone.BelowEntryPips(),pipSize);
               high+=PipsToPrice(zone.AboveEntryPips(),pipSize);
               break;
            case BRE_ZONE_EXPANSION_ABOVE_ONLY:
               if(direction==BRE_DIRECTION_SELL)
                  high+=PipsToPrice(zone.AboveEntryPips(),pipSize);
               else if(direction==BRE_DIRECTION_BUY)
                  low-=PipsToPrice(zone.BelowEntryPips()>0.0 ? zone.BelowEntryPips() : zone.AboveEntryPips(),pipSize);
               break;
            case BRE_ZONE_EXPANSION_BELOW_ONLY:
               if(direction==BRE_DIRECTION_BUY)
                  low-=PipsToPrice(zone.BelowEntryPips(),pipSize);
               else if(direction==BRE_DIRECTION_SELL)
                  low-=PipsToPrice(zone.BelowEntryPips(),pipSize);
               break;
            case BRE_ZONE_EXPANSION_ASYMMETRIC:
               low-=PipsToPrice(zone.BelowEntryPips(),pipSize);
               high+=PipsToPrice(zone.AboveEntryPips(),pipSize);
               break;
            default:
               break;
           }
        }

      if(zone.HasMaxRecoveryDistance())
        {
         double maxDistance=PipsToPrice(zone.MaxRecoveryDistancePips(),pipSize);
         if(high-low>maxDistance)
            high=low+maxDistance;
        }

      if(low>high)
        {
         double swap=low;
         low=high;
         high=swap;
        }

      return CEffectiveRecoveryZone::Create(low,high);
     }
  };

#endif
