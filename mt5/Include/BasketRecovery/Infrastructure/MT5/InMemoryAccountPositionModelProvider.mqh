#ifndef BRE_INF_IN_MEMORY_ACCOUNT_POSITION_MODEL_PROVIDER_MQH
#define BRE_INF_IN_MEMORY_ACCOUNT_POSITION_MODEL_PROVIDER_MQH

#include <BasketRecovery/Application/Ports/IAccountPositionModelProvider.mqh>

class CInMemoryAccountPositionModelProvider : public IAccountPositionModelProvider
  {
private:
   ENUM_BRE_ACCOUNT_POSITION_MODEL m_model;

public:
                     CInMemoryAccountPositionModelProvider(const ENUM_BRE_ACCOUNT_POSITION_MODEL model=BRE_ACCOUNT_POSITION_MODEL_HEDGING)
     {
      m_model=model;
     }

   void              SetModel(const ENUM_BRE_ACCOUNT_POSITION_MODEL model) { m_model=model; }

   virtual ENUM_BRE_ACCOUNT_POSITION_MODEL Capture(void) const
     {
      return m_model;
     }
  };

#endif
