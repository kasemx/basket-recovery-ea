#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_PROFILE_SNAPSHOT_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_PROFILE_SNAPSHOT_MQH

#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

class CStrategyProfileSnapshot
  {
private:
   CStrategyProfile m_profile;
   string           m_strategyId;
   int              m_schemaVersion;
   string           m_canonicalJson;
   string           m_profileHash;
   CUtcTime         m_boundAtUtc;

public:
                     CStrategyProfileSnapshot(void) {}

                     CStrategyProfileSnapshot(const CStrategyProfileSnapshot &other)
     {
      m_profile=other.m_profile;
      m_strategyId=other.m_strategyId;
      m_schemaVersion=other.m_schemaVersion;
      m_canonicalJson=other.m_canonicalJson;
      m_profileHash=other.m_profileHash;
      m_boundAtUtc=other.m_boundAtUtc;
     }

   CStrategyProfile Profile(void) const { return m_profile; }
   string           StrategyId(void) const { return m_strategyId; }
   int              SchemaVersion(void) const { return m_schemaVersion; }
   string           CanonicalJson(void) const { return m_canonicalJson; }
   string           ProfileHash(void) const { return m_profileHash; }
   CUtcTime         BoundAtUtc(void) const { return m_boundAtUtc; }

   static CStrategyProfileSnapshot Create(const CStrategyProfile &profile,
                                          const string canonicalJson,
                                          const string profileHash,
                                          const CUtcTime &boundAtUtc)
     {
      CStrategyProfileSnapshot snapshot;
      snapshot.m_profile=profile;
      snapshot.m_strategyId=profile.StrategyId();
      snapshot.m_schemaVersion=profile.SchemaVersion();
      snapshot.m_canonicalJson=canonicalJson;
      snapshot.m_profileHash=profileHash;
      snapshot.m_boundAtUtc=boundAtUtc;
      return snapshot;
     }

   static CStrategyProfileSnapshot CreateUnbound(void)
     {
      CStrategyProfileSnapshot snapshot;
      return snapshot;
     }
  };

#endif
