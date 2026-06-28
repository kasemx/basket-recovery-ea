#ifndef BRE_DOMAIN_PROJECTED_BASKET_RISK_MQH
#define BRE_DOMAIN_PROJECTED_BASKET_RISK_MQH

#include <BasketRecovery/Domain/Risk/Enums/RiskSafetyStatus.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/BasketRiskSnapshot.mqh>

class CProjectedBasketRisk
  {
private:
   CBasketRiskSnapshot           m_current;
   double                        m_proposedPositionRiskMoney;
   double                        m_projectedSlRiskMoney;
   double                        m_projectedRiskUtilization;
   double                        m_maxRiskRemainingMoney;
   bool                          m_exceedsMaxRisk;
   ENUM_BRE_RISK_SAFETY_STATUS   m_safetyStatus;

public:
                     CProjectedBasketRisk(void)
     {
      m_proposedPositionRiskMoney=0.0;
      m_projectedSlRiskMoney=0.0;
      m_projectedRiskUtilization=0.0;
      m_maxRiskRemainingMoney=0.0;
      m_exceedsMaxRisk=false;
      m_safetyStatus=BRE_RISK_SAFETY_UNKNOWN;
     }

   CBasketRiskSnapshot Current(void) const { return m_current; }
   double            ProposedPositionRiskMoney(void) const { return m_proposedPositionRiskMoney; }
   double            ProjectedSlRiskMoney(void) const { return m_projectedSlRiskMoney; }
   double            ProjectedRiskUtilization(void) const { return m_projectedRiskUtilization; }
   double            MaxRiskRemainingMoney(void) const { return m_maxRiskRemainingMoney; }
   bool              ExceedsMaxRisk(void) const { return m_exceedsMaxRisk; }
   ENUM_BRE_RISK_SAFETY_STATUS SafetyStatus(void) const { return m_safetyStatus; }

   static CProjectedBasketRisk Create(const CBasketRiskSnapshot &current,
                                      const double proposedPositionRiskMoney,
                                      const double projectedSlRiskMoney,
                                      const ENUM_BRE_RISK_SAFETY_STATUS safetyStatus)
     {
      CProjectedBasketRisk projected;
      projected.m_current=current;
      projected.m_proposedPositionRiskMoney=proposedPositionRiskMoney;
      projected.m_projectedSlRiskMoney=projectedSlRiskMoney;
      projected.m_safetyStatus=safetyStatus;
      projected.m_maxRiskRemainingMoney=current.MaxRiskMoney()-current.CurrentSlRiskMoney();
      projected.m_projectedRiskUtilization=current.MaxRiskMoney()>0.0
                                             ? projectedSlRiskMoney/current.MaxRiskMoney()
                                             : 0.0;
      projected.m_exceedsMaxRisk=projectedSlRiskMoney>current.MaxRiskMoney();
      return projected;
     }
  };

#endif
