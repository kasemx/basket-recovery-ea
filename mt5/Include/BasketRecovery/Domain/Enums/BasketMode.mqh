#ifndef BASKET_RECOVERY_DOMAIN_BASKET_MODE_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_MODE_MQH

class CBasketModeFlags
  {
private:
   bool m_recoveryActive;
   bool m_recoveryPermanentlyDisabled;
   bool m_breakEvenActive;
   bool m_trailingActive;
   bool m_locked;
   bool m_riskReductionActive;
   bool m_maxRiskLockout;

public:
                     CBasketModeFlags(void)
     {
      m_recoveryActive=false;
      m_recoveryPermanentlyDisabled=false;
      m_breakEvenActive=false;
      m_trailingActive=false;
      m_locked=false;
      m_riskReductionActive=false;
      m_maxRiskLockout=false;
     }

   bool              RecoveryActive(void) const { return m_recoveryActive; }
   bool              RecoveryPermanentlyDisabled(void) const { return m_recoveryPermanentlyDisabled; }
   bool              BreakEvenActive(void) const { return m_breakEvenActive; }
   bool              TrailingActive(void) const { return m_trailingActive; }
   bool              Locked(void) const { return m_locked; }
   bool              RiskReductionActive(void) const { return m_riskReductionActive; }
   bool              MaxRiskLockout(void) const { return m_maxRiskLockout; }

   void              SetRecoveryActive(const bool value) { m_recoveryActive=value; }
   void              SetRecoveryPermanentlyDisabled(const bool value) { m_recoveryPermanentlyDisabled=value; }
   void              SetBreakEvenActive(const bool value) { m_breakEvenActive=value; }
   void              SetTrailingActive(const bool value) { m_trailingActive=value; }
   void              SetLocked(const bool value) { m_locked=value; }
   void              SetRiskReductionActive(const bool value) { m_riskReductionActive=value; }
   void              SetMaxRiskLockout(const bool value) { m_maxRiskLockout=value; }
  };

#endif
