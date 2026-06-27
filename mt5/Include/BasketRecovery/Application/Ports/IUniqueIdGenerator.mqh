#ifndef BASKET_RECOVERY_APPLICATION_IUNIQUE_ID_GENERATOR_MQH
#define BASKET_RECOVERY_APPLICATION_IUNIQUE_ID_GENERATOR_MQH

class IUniqueIdGenerator
  {
public:
   virtual          ~IUniqueIdGenerator(void) {}
   virtual string    NewGuid(void)=0;
  };

#endif
