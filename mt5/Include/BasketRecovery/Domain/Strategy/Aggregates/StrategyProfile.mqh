#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_PROFILE_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_PROFILE_MQH

#include <BasketRecovery/Domain/Configuration/ExecutionProfileConfig.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/StrategyMetadata.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ExecutionZone.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitDistributionPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RiskPlan.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

class CStrategyProfile
  {
private:
   string                   m_strategyId;
   int                      m_schemaVersion;
   CStrategyMetadata        m_metadata;
   CExecutionZone           m_executionZone;
   CRecoveryPlan            m_recoveryPlan;
   CProfitDistributionPlan  m_profitDistributionPlan;
   CBreakEvenPlan           m_breakEvenPlan;
   CRiskPlan                m_riskPlan;
   CExecutionProfileConfig  m_executionPolicy;
   CUtcTime                 m_boundAt;

public:
                     CStrategyProfile(void) {}

                     CStrategyProfile(const CStrategyProfile &other)
     {
      m_strategyId=other.m_strategyId;
      m_schemaVersion=other.m_schemaVersion;
      m_metadata=other.m_metadata;
      m_executionZone=other.m_executionZone;
      m_recoveryPlan=other.m_recoveryPlan;
      m_profitDistributionPlan=other.m_profitDistributionPlan;
      m_breakEvenPlan=other.m_breakEvenPlan;
      m_riskPlan=other.m_riskPlan;
      m_executionPolicy=other.m_executionPolicy;
      m_boundAt=other.m_boundAt;
     }

   string                   StrategyId(void) const { return m_strategyId; }
   int                      SchemaVersion(void) const { return m_schemaVersion; }
   CStrategyMetadata        Metadata(void) const { return m_metadata; }
   CExecutionZone           ExecutionZone(void) const { return m_executionZone; }
   CRecoveryPlan            RecoveryPlan(void) const { return m_recoveryPlan; }
   CProfitDistributionPlan  ProfitDistributionPlan(void) const { return m_profitDistributionPlan; }
   CBreakEvenPlan           BreakEvenPlan(void) const { return m_breakEvenPlan; }
   CRiskPlan                RiskPlan(void) const { return m_riskPlan; }
   CExecutionProfileConfig  ExecutionPolicy(void) const { return m_executionPolicy; }
   CUtcTime                 BoundAt(void) const { return m_boundAt; }

   static CStrategyProfile  Create(const string strategyId,
                                   const int schemaVersion,
                                   const CStrategyMetadata &metadata,
                                   const CExecutionZone &executionZone,
                                   const CRecoveryPlan &recoveryPlan,
                                   const CProfitDistributionPlan &profitDistributionPlan,
                                   const CBreakEvenPlan &breakEvenPlan,
                                   const CRiskPlan &riskPlan,
                                   const CExecutionProfileConfig &executionPolicy,
                                   const CUtcTime &boundAt)
     {
      CStrategyProfile profile;
      profile.m_strategyId=strategyId;
      profile.m_schemaVersion=schemaVersion;
      profile.m_metadata=metadata;
      profile.m_executionZone=executionZone;
      profile.m_recoveryPlan=recoveryPlan;
      profile.m_profitDistributionPlan=profitDistributionPlan;
      profile.m_breakEvenPlan=breakEvenPlan;
      profile.m_riskPlan=riskPlan;
      profile.m_executionPolicy=executionPolicy;
      profile.m_boundAt=boundAt;
      return profile;
     }
  };

#endif
