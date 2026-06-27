#ifndef BASKET_RECOVERY_DOMAIN_TAKE_PROFIT_PROFILE_CONFIG_MQH
#define BASKET_RECOVERY_DOMAIN_TAKE_PROFIT_PROFILE_CONFIG_MQH

class CTakeProfitProfileConfig
  {
private:
   string m_profileName;
   double m_tp1RealizeFraction;
   double m_tp2RealizeFraction;
   bool   m_requireFloatingProfitPositive;

public:
                     CTakeProfitProfileConfig(void)
     {
      m_profileName="default";
      m_tp1RealizeFraction=0.33;
      m_tp2RealizeFraction=0.66;
      m_requireFloatingProfitPositive=true;
     }

   string            ProfileName(void) const { return m_profileName; }
   double            Tp1RealizeFraction(void) const { return m_tp1RealizeFraction; }
   double            Tp2RealizeFraction(void) const { return m_tp2RealizeFraction; }
   bool              RequireFloatingProfitPositive(void) const { return m_requireFloatingProfitPositive; }

   void              SetProfileName(const string value) { m_profileName=value; }
   void              SetTp1RealizeFraction(const double value) { m_tp1RealizeFraction=value; }
   void              SetTp2RealizeFraction(const double value) { m_tp2RealizeFraction=value; }
   void              SetRequireFloatingProfitPositive(const bool value) { m_requireFloatingProfitPositive=value; }
  };

#endif
