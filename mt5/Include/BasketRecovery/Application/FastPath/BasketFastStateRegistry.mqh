#ifndef BRE_APP_BASKET_FAST_STATE_REGISTRY_MQH
#define BRE_APP_BASKET_FAST_STATE_REGISTRY_MQH

#include <BasketRecovery/Application/FastPath/BasketFastState.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>

class CBasketFastStateRegistry
  {
private:
   string            m_keys[];
   CBasketFastState  m_states[];
   int               m_count;

   int               FindIndex(const CBasketId &basketId) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_keys[i]==basketId.Value())
            return i;
        }
      return -1;
     }

public:
                     CBasketFastStateRegistry(void)
     {
      m_count=0;
     }

   CBasketFastState  GetOrCreate(const CBasketId &basketId)
     {
      int index=FindIndex(basketId);
      if(index>=0)
         return m_states[index];

      ArrayResize(m_keys,m_count+1);
      ArrayResize(m_states,m_count+1);
      m_keys[m_count]=basketId.Value();
      m_states[m_count]=CBasketFastState();
      m_count++;
      return m_states[m_count-1];
     }

   bool              TryGet(const CBasketId &basketId,CBasketFastState &outState) const
     {
      int index=FindIndex(basketId);
      if(index<0)
         return false;
      outState=m_states[index];
      return true;
     }

   void              Save(const CBasketId &basketId,const CBasketFastState &state)
     {
      int index=FindIndex(basketId);
      if(index<0)
        {
         ArrayResize(m_keys,m_count+1);
         ArrayResize(m_states,m_count+1);
         m_keys[m_count]=basketId.Value();
         m_states[m_count]=state;
         m_count++;
         return;
        }
      m_states[index]=state;
     }
  };

#endif
