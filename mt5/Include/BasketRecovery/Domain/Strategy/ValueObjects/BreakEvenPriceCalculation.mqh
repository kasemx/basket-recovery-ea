#ifndef BRE_DOMAIN_BREAK_EVEN_PRICE_CALCULATION_MQH
#define BRE_DOMAIN_BREAK_EVEN_PRICE_CALCULATION_MQH

class CBreakEvenPriceCalculation
  {
private:
   double m_weightedAverageEntry;
   double m_totalActiveVolume;
   double m_spreadComponent;
   double m_safetyBufferComponent;
   double m_rawProposedStopLoss;
   double m_normalizedStopLoss;
   bool   m_valid;

public:
                     CBreakEvenPriceCalculation(void)
     {
      m_weightedAverageEntry=0.0;
      m_totalActiveVolume=0.0;
      m_spreadComponent=0.0;
      m_safetyBufferComponent=0.0;
      m_rawProposedStopLoss=0.0;
      m_normalizedStopLoss=0.0;
      m_valid=false;
     }

   double            WeightedAverageEntry(void) const { return m_weightedAverageEntry; }
   double            TotalActiveVolume(void) const { return m_totalActiveVolume; }
   double            SpreadComponent(void) const { return m_spreadComponent; }
   double            SafetyBufferComponent(void) const { return m_safetyBufferComponent; }
   double            RawProposedStopLoss(void) const { return m_rawProposedStopLoss; }
   double            NormalizedStopLoss(void) const { return m_normalizedStopLoss; }
   bool              Valid(void) const { return m_valid; }

   static CBreakEvenPriceCalculation Create(const double weightedAverageEntry,
                                            const double totalActiveVolume,
                                            const double spreadComponent,
                                            const double safetyBufferComponent,
                                            const double rawProposedStopLoss,
                                            const double normalizedStopLoss,
                                            const bool valid)
     {
      CBreakEvenPriceCalculation calc;
      calc.m_weightedAverageEntry=weightedAverageEntry;
      calc.m_totalActiveVolume=totalActiveVolume;
      calc.m_spreadComponent=spreadComponent;
      calc.m_safetyBufferComponent=safetyBufferComponent;
      calc.m_rawProposedStopLoss=rawProposedStopLoss;
      calc.m_normalizedStopLoss=normalizedStopLoss;
      calc.m_valid=valid;
      return calc;
     }

   static CBreakEvenPriceCalculation Invalid(void)
     {
      return CBreakEvenPriceCalculation::Create(0.0,0.0,0.0,0.0,0.0,0.0,false);
     }
  };

#endif
