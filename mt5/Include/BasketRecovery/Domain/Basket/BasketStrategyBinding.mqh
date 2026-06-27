#ifndef BASKET_RECOVERY_DOMAIN_BASKET_STRATEGY_BINDING_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_STRATEGY_BINDING_MQH

#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfileSnapshot.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class CBasketStrategyBinding
  {
private:
   bool                     m_bound;
   CStrategyProfileSnapshot m_snapshot;

public:
                     CBasketStrategyBinding(void)
     {
      m_bound=false;
     }

   bool              IsBound(void) const { return m_bound; }
   CStrategyProfileSnapshot Snapshot(void) const { return m_snapshot; }
   string            StrategyId(void) const { return m_bound ? m_snapshot.StrategyId() : ""; }
   int               SchemaVersion(void) const { return m_bound ? m_snapshot.SchemaVersion() : 0; }
   string            ProfileHash(void) const { return m_bound ? m_snapshot.ProfileHash() : ""; }
   CUtcTime          BoundAtUtc(void) const { return m_bound ? m_snapshot.BoundAtUtc() : CUtcTime(0); }

   bool              TryGetProfile(CStrategyProfile &outProfile) const
     {
      if(!m_bound)
         return false;
      outProfile=m_snapshot.Profile();
      return true;
     }

   CVoidResult       Bind(const CStrategyProfileSnapshot &snapshot)
     {
      if(m_bound)
         return CVoidResult::Fail(BRE_ERR_STRATEGY_ALREADY_BOUND,"Strategy profile is already bound");
      if(snapshot.StrategyId()=="")
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Strategy id is required for binding");
      if(snapshot.ProfileHash()=="")
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Strategy profile hash is required for binding");
      m_snapshot=snapshot;
      m_bound=true;
      return CVoidResult::Ok();
     }

   void              Restore(const CStrategyProfileSnapshot &snapshot)
     {
      m_snapshot=snapshot;
      m_bound=snapshot.StrategyId()!="";
     }
  };

#endif
