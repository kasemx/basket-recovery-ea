#ifndef BRE_DOMAIN_PROFIT_LEVEL_TRIGGER_RESOLVER_MQH
#define BRE_DOMAIN_PROFIT_LEVEL_TRIGGER_RESOLVER_MQH

#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevel.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ProfitLevelTriggerType.mqh>

class CProfitLevelTriggerResolution
  {
private:
   ENUM_BRE_PROFIT_LEVEL_TRIGGER_TYPE m_type;
   double                             m_value;
   bool                               m_hasValue;
   bool                               m_supported;

public:
                     CProfitLevelTriggerResolution(void)
     {
      m_type=BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE;
      m_value=0.0;
      m_hasValue=false;
      m_supported=false;
     }

   ENUM_BRE_PROFIT_LEVEL_TRIGGER_TYPE Type(void) const { return m_type; }
   double                             Value(void) const { return m_value; }
   bool                               HasValue(void) const { return m_hasValue; }
   bool                               Supported(void) const { return m_supported; }

   static CProfitLevelTriggerResolution Create(const ENUM_BRE_PROFIT_LEVEL_TRIGGER_TYPE type,
                                               const double value,
                                               const bool hasValue,
                                               const bool supported)
     {
      CProfitLevelTriggerResolution resolution;
      resolution.m_type=type;
      resolution.m_value=value;
      resolution.m_hasValue=hasValue;
      resolution.m_supported=supported;
      return resolution;
     }
  };

class CProfitLevelTriggerResolver
  {
public:
   static CProfitLevelTriggerResolution Resolve(const CProfitLevel &level)
     {
      if(level.TriggerType()!=BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE)
        {
         bool supported=level.TriggerType()!=BRE_PROFIT_LEVEL_TRIGGER_FUTURE_PLACEHOLDER;
         return CProfitLevelTriggerResolution::Create(level.TriggerType(),
                                                      level.TriggerValue(),
                                                      level.HasTriggerValue(),
                                                      supported);
        }

      switch(level.Source())
        {
         case BRE_PROFIT_LEVEL_SOURCE_FIXED_PRICE:
            if(!level.HasPrice())
               return CProfitLevelTriggerResolution::Create(BRE_PROFIT_LEVEL_TRIGGER_STRATEGY_PRICE_LEVEL,0.0,false,false);
            return CProfitLevelTriggerResolution::Create(BRE_PROFIT_LEVEL_TRIGGER_STRATEGY_PRICE_LEVEL,
                                                           level.Price(),true,true);
         case BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY:
            return CProfitLevelTriggerResolution::Create(BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,
                                                           level.HasTriggerValue() ? level.TriggerValue() : level.Price(),
                                                           level.HasTriggerValue() || level.HasPrice(),true);
         case BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_PCT_TARGET_RISK:
            return CProfitLevelTriggerResolution::Create(BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_PCT_TARGET_RISK,
                                                           level.HasTriggerValue() ? level.TriggerValue() : level.Price(),
                                                           level.HasTriggerValue() || level.HasPrice(),true);
         case BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_PCT_EQUITY:
            return CProfitLevelTriggerResolution::Create(BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_PCT_EQUITY,
                                                           level.HasTriggerValue() ? level.TriggerValue() : level.Price(),
                                                           level.HasTriggerValue() || level.HasPrice(),true);
         case BRE_PROFIT_LEVEL_SOURCE_SIGNAL_TP:
         case BRE_PROFIT_LEVEL_SOURCE_DYNAMIC:
         default:
            return CProfitLevelTriggerResolution::Create(BRE_PROFIT_LEVEL_TRIGGER_INFER_FROM_SOURCE,0.0,false,false);
        }
     }
  };

#endif
