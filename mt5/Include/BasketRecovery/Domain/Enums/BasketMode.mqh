#ifndef BASKET_RECOVERY_DOMAIN_BASKET_MODE_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_MODE_MQH

class CBasketModeFlags
  {
private:
   bool m_recoveryActive;
   bool m_recoveryPermanentlyDisabled;
   bool m_riskReductionActive;
   bool m_maxRiskLockout;

public:
                     CBasketModeFlags(void)
     {
      m_recoveryActive=false;
      m_recoveryPermanentlyDisabled=false;
      m_riskReductionActive=false;
      m_maxRiskLockout=false;
     }

   bool              RecoveryActive(void) const { return m_recoveryActive; }
   bool              RecoveryPermanentlyDisabled(void) const { return m_recoveryPermanentlyDisabled; }
   bool              RiskReductionActive(void) const { return m_riskReductionActive; }
   bool              MaxRiskLockout(void) const { return m_maxRiskLockout; }

   void              SetRecoveryActive(const bool value) { m_recoveryActive=value; }
   void              SetRecoveryPermanentlyDisabled(const bool value) { m_recoveryPermanentlyDisabled=value; }
   void              SetRiskReductionActive(const bool value) { m_riskReductionActive=value; }
   void              SetMaxRiskLockout(const bool value) { m_maxRiskLockout=value; }
  };

#endif
