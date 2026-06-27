#ifndef BASKET_RECOVERY_DOMAIN_RISK_PROFILE_CONFIG_MQH
#define BASKET_RECOVERY_DOMAIN_RISK_PROFILE_CONFIG_MQH

class CRiskProfileConfig
  {
private:
   string m_profileName;
   double m_targetRiskPct;
   double m_maxRiskPct;
   double m_maxRiskReleaseThreshold;
   double m_breakEvenRealizedFraction;
   int    m_riskEvalDebounceMs;
   int    m_waitDetailsTimeoutMinutes;

public:
                     CRiskProfileConfig(void)
     {
      m_profileName="default";
      m_targetRiskPct=1.0;
      m_maxRiskPct=1.2;
      m_maxRiskReleaseThreshold=0.95;
      m_breakEvenRealizedFraction=0.33;
      m_riskEvalDebounceMs=100;
      m_waitDetailsTimeoutMinutes=30;
     }

   string            ProfileName(void) const { return m_profileName; }
   double            TargetRiskPct(void) const { return m_targetRiskPct; }
   double            MaxRiskPct(void) const { return m_maxRiskPct; }
   double            MaxRiskReleaseThreshold(void) const { return m_maxRiskReleaseThreshold; }
   double            BreakEvenRealizedFraction(void) const { return m_breakEvenRealizedFraction; }
   int               RiskEvalDebounceMs(void) const { return m_riskEvalDebounceMs; }
   int               WaitDetailsTimeoutMinutes(void) const { return m_waitDetailsTimeoutMinutes; }

   void              SetProfileName(const string value) { m_profileName=value; }
   void              SetTargetRiskPct(const double value) { m_targetRiskPct=value; }
   void              SetMaxRiskPct(const double value) { m_maxRiskPct=value; }
   void              SetMaxRiskReleaseThreshold(const double value) { m_maxRiskReleaseThreshold=value; }
   void              SetBreakEvenRealizedFraction(const double value) { m_breakEvenRealizedFraction=value; }
   void              SetRiskEvalDebounceMs(const int value) { m_riskEvalDebounceMs=value; }
   void              SetWaitDetailsTimeoutMinutes(const int value) { m_waitDetailsTimeoutMinutes=value; }
  };

#endif
