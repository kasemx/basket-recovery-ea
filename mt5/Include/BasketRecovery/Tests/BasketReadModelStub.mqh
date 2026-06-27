#ifndef BASKET_RECOVERY_TESTS_BASKET_READ_MODEL_STUB_MQH
#define BASKET_RECOVERY_TESTS_BASKET_READ_MODEL_STUB_MQH

#include <BasketRecovery/Domain/Aggregates/IBasketReadModel.mqh>

class CBasketReadModelStub : public IBasketReadModel
  {
private:
   ENUM_BRE_BASKET_LIFECYCLE_STATE m_lifecycleState;
   bool                              m_recoveryPermanentlyDisabled;
   bool                              m_hasProfileSnapshot;
   CSignalDetails                    m_details;

public:
                     CBasketReadModelStub(void)
     {
      m_lifecycleState=BRE_STATE_NONE;
      m_recoveryPermanentlyDisabled=false;
      m_hasProfileSnapshot=false;
     }

   void              SetLifecycleState(const ENUM_BRE_BASKET_LIFECYCLE_STATE value) { m_lifecycleState=value; }
   void              SetRecoveryPermanentlyDisabled(const bool value) { m_recoveryPermanentlyDisabled=value; }
   void              SetHasProfileSnapshot(const bool value) { m_hasProfileSnapshot=value; }
   void              SetSignalDetails(const CSignalDetails &value) { m_details=value; }

   virtual ENUM_BRE_BASKET_LIFECYCLE_STATE LifecycleState(void) const { return m_lifecycleState; }
   virtual bool      RecoveryPermanentlyDisabled(void) const { return m_recoveryPermanentlyDisabled; }
   virtual bool      HasProfileSnapshot(void) const { return m_hasProfileSnapshot; }
   virtual CSignalDetails SignalDetails(void) const { return m_details; }
  };

#endif
