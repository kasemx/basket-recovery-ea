#ifndef BRE_DOMAIN_SYMBOL_TRADING_CONSTRAINTS_MQH
#define BRE_DOMAIN_SYMBOL_TRADING_CONSTRAINTS_MQH

class CSymbolTradingConstraints
  {
private:
   int    m_stopsLevel;
   int    m_freezeLevel;
   double m_volumeMin;
   double m_volumeMax;
   double m_volumeStep;

public:
                     CSymbolTradingConstraints(void)
     {
      m_stopsLevel=0;
      m_freezeLevel=0;
      m_volumeMin=0.0;
      m_volumeMax=0.0;
      m_volumeStep=0.0;
     }

                     CSymbolTradingConstraints(const CSymbolTradingConstraints &other)
     {
      m_stopsLevel=other.m_stopsLevel;
      m_freezeLevel=other.m_freezeLevel;
      m_volumeMin=other.m_volumeMin;
      m_volumeMax=other.m_volumeMax;
      m_volumeStep=other.m_volumeStep;
     }

   int               StopsLevel(void) const { return m_stopsLevel; }
   int               FreezeLevel(void) const { return m_freezeLevel; }
   double            VolumeMin(void) const { return m_volumeMin; }
   double            VolumeMax(void) const { return m_volumeMax; }
   double            VolumeStep(void) const { return m_volumeStep; }

   static CSymbolTradingConstraints Create(const int stopsLevel,
                                             const int freezeLevel,
                                             const double volumeMin,
                                             const double volumeMax,
                                             const double volumeStep)
     {
      CSymbolTradingConstraints constraints;
      constraints.m_stopsLevel=stopsLevel;
      constraints.m_freezeLevel=freezeLevel;
      constraints.m_volumeMin=volumeMin;
      constraints.m_volumeMax=volumeMax;
      constraints.m_volumeStep=volumeStep;
      return constraints;
     }
  };

#endif
