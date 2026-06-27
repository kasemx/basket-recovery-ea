#ifndef BASKET_RECOVERY_DOMAIN_IBASKET_READ_MODEL_MQH
#define BASKET_RECOVERY_DOMAIN_IBASKET_READ_MODEL_MQH

#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/ValueObjects/SignalDetails.mqh>

class IBasketReadModel
  {
public:
   virtual          ~IBasketReadModel(void) {}
   virtual ENUM_BRE_BASKET_LIFECYCLE_STATE LifecycleState(void) const=0;
   virtual bool      RecoveryPermanentlyDisabled(void) const=0;
   virtual bool      HasProfileSnapshot(void) const=0;
   virtual CSignalDetails SignalDetails(void) const=0;
  };

#endif
