#ifndef BRE_DOMAIN_RISK_CALCULATION_SETTINGS_MQH
#define BRE_DOMAIN_RISK_CALCULATION_SETTINGS_MQH

class CRiskCalculationSettings
  {
private:
   bool   m_includeCommission;
   bool   m_includeSwap;
   bool   m_includeSpreadBuffer;
   double m_spreadBufferMultiplier;
   bool   m_requireCrossCurrencyConversion;
   bool   m_crossCurrencyConversionAvailable;

public:
                     CRiskCalculationSettings(void)
     {
      m_includeCommission=true;
      m_includeSwap=true;
      m_includeSpreadBuffer=true;
      m_spreadBufferMultiplier=1.0;
      m_requireCrossCurrencyConversion=false;
      m_crossCurrencyConversionAvailable=true;
     }

   bool              IncludeCommission(void) const { return m_includeCommission; }
   bool              IncludeSwap(void) const { return m_includeSwap; }
   bool              IncludeSpreadBuffer(void) const { return m_includeSpreadBuffer; }
   double            SpreadBufferMultiplier(void) const { return m_spreadBufferMultiplier; }
   bool              RequireCrossCurrencyConversion(void) const { return m_requireCrossCurrencyConversion; }
   bool              CrossCurrencyConversionAvailable(void) const { return m_crossCurrencyConversionAvailable; }

   static CRiskCalculationSettings CreateDefault(void)
     {
      CRiskCalculationSettings settings;
      return settings;
     }
  };

#endif
