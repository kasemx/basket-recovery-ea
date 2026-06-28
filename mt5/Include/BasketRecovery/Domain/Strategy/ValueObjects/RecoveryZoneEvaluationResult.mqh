#ifndef BRE_DOMAIN_RECOVERY_ZONE_EVALUATION_RESULT_MQH
#define BRE_DOMAIN_RECOVERY_ZONE_EVALUATION_RESULT_MQH

class CRecoveryZoneEvaluationResult
  {
private:
   bool    m_withinZone;
   double  m_zoneLow;
   double  m_zoneHigh;
   double  m_evaluatedPrice;

public:
                     CRecoveryZoneEvaluationResult(void) {}

   bool              WithinZone(void) const { return m_withinZone; }
   double            ZoneLow(void) const { return m_zoneLow; }
   double            ZoneHigh(void) const { return m_zoneHigh; }
   double            EvaluatedPrice(void) const { return m_evaluatedPrice; }

   static CRecoveryZoneEvaluationResult Create(const bool withinZone,
                                               const double zoneLow,
                                               const double zoneHigh,
                                               const double evaluatedPrice)
     {
      CRecoveryZoneEvaluationResult result;
      result.m_withinZone=withinZone;
      result.m_zoneLow=zoneLow;
      result.m_zoneHigh=zoneHigh;
      result.m_evaluatedPrice=evaluatedPrice;
      return result;
     }
  };

#endif
