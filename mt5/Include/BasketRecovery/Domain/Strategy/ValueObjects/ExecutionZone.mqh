#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_EXECUTION_ZONE_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_EXECUTION_ZONE_MQH

#include <BasketRecovery/Domain/Strategy/Enums/ExecutionZoneExpansionMode.mqh>

class CExecutionZone
  {
private:
   ENUM_BRE_EXECUTION_ZONE_SOURCE        m_source;
   ENUM_BRE_EXECUTION_ZONE_EXPANSION_MODE m_expansionMode;
   double                                m_fixedRangeLow;
   double                                m_fixedRangeHigh;
   bool                                  m_hasFixedRange;
   double                                m_aboveEntryPips;
   double                                m_belowEntryPips;
   double                                m_maxRecoveryDistancePips;
   bool                                  m_hasMaxRecoveryDistance;
   bool                                  m_expansionDisabled;

public:
                     CExecutionZone(void) {}

                     CExecutionZone(const CExecutionZone &other)
     {
      m_source=other.m_source;
      m_expansionMode=other.m_expansionMode;
      m_fixedRangeLow=other.m_fixedRangeLow;
      m_fixedRangeHigh=other.m_fixedRangeHigh;
      m_hasFixedRange=other.m_hasFixedRange;
      m_aboveEntryPips=other.m_aboveEntryPips;
      m_belowEntryPips=other.m_belowEntryPips;
      m_maxRecoveryDistancePips=other.m_maxRecoveryDistancePips;
      m_hasMaxRecoveryDistance=other.m_hasMaxRecoveryDistance;
      m_expansionDisabled=other.m_expansionDisabled;
     }

   ENUM_BRE_EXECUTION_ZONE_SOURCE        Source(void) const { return m_source; }
   ENUM_BRE_EXECUTION_ZONE_EXPANSION_MODE ExpansionMode(void) const { return m_expansionMode; }
   bool                                  HasFixedRange(void) const { return m_hasFixedRange; }
   double                                FixedRangeLow(void) const { return m_fixedRangeLow; }
   double                                FixedRangeHigh(void) const { return m_fixedRangeHigh; }
   double                                AboveEntryPips(void) const { return m_aboveEntryPips; }
   double                                BelowEntryPips(void) const { return m_belowEntryPips; }
   bool                                  HasMaxRecoveryDistance(void) const { return m_hasMaxRecoveryDistance; }
   double                                MaxRecoveryDistancePips(void) const { return m_maxRecoveryDistancePips; }
   bool                                  ExpansionDisabled(void) const { return m_expansionDisabled; }

   static CExecutionZone CreateSignalRange(const ENUM_BRE_EXECUTION_ZONE_EXPANSION_MODE expansionMode,
                                           const double aboveEntryPips,
                                           const double belowEntryPips,
                                           const bool expansionDisabled,
                                           const double maxRecoveryDistancePips,
                                           const bool hasMaxRecoveryDistance)
     {
      CExecutionZone zone;
      zone.m_source=BRE_EXECUTION_ZONE_SOURCE_SIGNAL_RANGE;
      zone.m_expansionMode=expansionMode;
      zone.m_aboveEntryPips=aboveEntryPips;
      zone.m_belowEntryPips=belowEntryPips;
      zone.m_expansionDisabled=expansionDisabled;
      zone.m_maxRecoveryDistancePips=maxRecoveryDistancePips;
      zone.m_hasMaxRecoveryDistance=hasMaxRecoveryDistance;
      zone.m_hasFixedRange=false;
      return zone;
     }

   static CExecutionZone CreateFixedRange(const double rangeLow,
                                          const double rangeHigh,
                                          const ENUM_BRE_EXECUTION_ZONE_EXPANSION_MODE expansionMode,
                                          const double aboveEntryPips,
                                          const double belowEntryPips,
                                          const bool expansionDisabled,
                                          const double maxRecoveryDistancePips,
                                          const bool hasMaxRecoveryDistance)
     {
      CExecutionZone zone;
      zone.m_source=BRE_EXECUTION_ZONE_SOURCE_FIXED_RANGE;
      zone.m_fixedRangeLow=rangeLow;
      zone.m_fixedRangeHigh=rangeHigh;
      zone.m_hasFixedRange=true;
      zone.m_expansionMode=expansionMode;
      zone.m_aboveEntryPips=aboveEntryPips;
      zone.m_belowEntryPips=belowEntryPips;
      zone.m_expansionDisabled=expansionDisabled;
      zone.m_maxRecoveryDistancePips=maxRecoveryDistancePips;
      zone.m_hasMaxRecoveryDistance=hasMaxRecoveryDistance;
      return zone;
     }
  };

#endif
