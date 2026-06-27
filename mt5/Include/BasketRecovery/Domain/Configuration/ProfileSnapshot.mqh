#ifndef BASKET_RECOVERY_DOMAIN_PROFILE_SNAPSHOT_MQH
#define BASKET_RECOVERY_DOMAIN_PROFILE_SNAPSHOT_MQH

#include <BasketRecovery/Domain/Configuration/RiskProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/RecoveryProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/TakeProfitProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/BreakEvenProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/ExecutionProfileConfig.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

class CProfileBundle;

class CProfileSnapshot
  {
private:
   string                   m_profileName;
   CRiskProfileConfig       m_risk;
   CRecoveryProfileConfig   m_recovery;
   CTakeProfitProfileConfig m_takeProfit;
   CBreakEvenProfileConfig  m_breakEven;
   CExecutionProfileConfig  m_execution;
   CUtcTime                 m_boundAt;

public:
                     CProfileSnapshot(void) {}

                     CProfileSnapshot(const CProfileSnapshot &other)
     {
      m_profileName=other.m_profileName;
      m_risk=other.m_risk;
      m_recovery=other.m_recovery;
      m_takeProfit=other.m_takeProfit;
      m_breakEven=other.m_breakEven;
      m_execution=other.m_execution;
      m_boundAt=other.m_boundAt;
     }

   string                   ProfileName(void) const { return m_profileName; }
   CRiskProfileConfig       Risk(void) const { return m_risk; }
   CRecoveryProfileConfig   Recovery(void) const { return m_recovery; }
   CTakeProfitProfileConfig TakeProfit(void) const { return m_takeProfit; }
   CBreakEvenProfileConfig  BreakEven(void) const { return m_breakEven; }
   CExecutionProfileConfig  Execution(void) const { return m_execution; }
   CUtcTime                 BoundAt(void) const { return m_boundAt; }

   static CProfileSnapshot  Create(const string profileName,
                                   const CRiskProfileConfig &risk,
                                   const CRecoveryProfileConfig &recovery,
                                   const CTakeProfitProfileConfig &takeProfit,
                                   const CBreakEvenProfileConfig &breakEven,
                                   const CExecutionProfileConfig &execution,
                                   const CUtcTime &boundAt)
     {
      CProfileSnapshot snapshot;
      snapshot.m_profileName=profileName;
      snapshot.m_risk=risk;
      snapshot.m_recovery=recovery;
      snapshot.m_takeProfit=takeProfit;
      snapshot.m_breakEven=breakEven;
      snapshot.m_execution=execution;
      snapshot.m_boundAt=boundAt;
      return snapshot;
     }
  };

#endif
