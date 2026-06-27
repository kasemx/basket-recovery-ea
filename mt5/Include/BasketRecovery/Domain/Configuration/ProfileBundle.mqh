#ifndef BASKET_RECOVERY_DOMAIN_PROFILE_BUNDLE_MQH
#define BASKET_RECOVERY_DOMAIN_PROFILE_BUNDLE_MQH

#include <BasketRecovery/Domain/Configuration/RiskProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/RecoveryProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/TakeProfitProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/BreakEvenProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/ExecutionProfileConfig.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

class CProfileBundle
  {
private:
   string                  m_profileName;
   CRiskProfileConfig      m_risk;
   CRecoveryProfileConfig  m_recovery;
   CTakeProfitProfileConfig m_takeProfit;
   CBreakEvenProfileConfig m_breakEven;
   CExecutionProfileConfig m_execution;
   CUtcTime                m_boundAt;

public:
                     CProfileBundle(void)
     {
      m_profileName="default";
     }

   string                  ProfileName(void) const { return m_profileName; }
   CRiskProfileConfig      Risk(void) const { return m_risk; }
   CRecoveryProfileConfig  Recovery(void) const { return m_recovery; }
   CTakeProfitProfileConfig TakeProfit(void) const { return m_takeProfit; }
   CBreakEvenProfileConfig BreakEven(void) const { return m_breakEven; }
   CExecutionProfileConfig Execution(void) const { return m_execution; }
   CUtcTime                BoundAt(void) const { return m_boundAt; }

   void                    SetProfileName(const string value) { m_profileName=value; }
   void                    SetRisk(const CRiskProfileConfig &value) { m_risk=value; }
   void                    SetRecovery(const CRecoveryProfileConfig &value) { m_recovery=value; }
   void                    SetTakeProfit(const CTakeProfitProfileConfig &value) { m_takeProfit=value; }
   void                    SetBreakEven(const CBreakEvenProfileConfig &value) { m_breakEven=value; }
   void                    SetExecution(const CExecutionProfileConfig &value) { m_execution=value; }
   void                    SetBoundAt(const CUtcTime value) { m_boundAt=value; }
  };

#endif
