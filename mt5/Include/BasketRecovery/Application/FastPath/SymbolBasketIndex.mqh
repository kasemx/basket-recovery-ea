#ifndef BRE_APP_SYMBOL_BASKET_INDEX_MQH
#define BRE_APP_SYMBOL_BASKET_INDEX_MQH

#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>

class CSymbolBasketIndex
  {
private:
   string            m_symbols[];
   string            m_basketIds[];
   int               m_count;
   bool              m_isDirty;

   int               FindSymbolStart(const string symbol) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_symbols[i]==symbol)
            return i;
        }
      return -1;
     }

public:
                     CSymbolBasketIndex(void)
     {
      m_count=0;
      m_isDirty=true;
     }

   void              MarkDirty(void) { m_isDirty=true; }

   bool              IsDirty(void) const { return m_isDirty; }

   void              Rebuild(IBasketRepository *repository)
     {
      m_count=0;
      ArrayResize(m_symbols,0);
      ArrayResize(m_basketIds,0);
      if(repository==NULL)
        {
         m_isDirty=false;
         return;
        }

      CBasketAggregate baskets[];
      int basketCount=repository.LoadAll(baskets);
      for(int i=0;i<basketCount;i++)
        {
         if(baskets[i].LifecycleState()!=BRE_STATE_ACTIVE)
            continue;
         if(baskets[i].Symbol()=="")
            continue;

         ArrayResize(m_symbols,m_count+1);
         ArrayResize(m_basketIds,m_count+1);
         m_symbols[m_count]=baskets[i].Symbol();
         m_basketIds[m_count]=baskets[i].Id().Value();
         m_count++;
        }
      m_isDirty=false;
     }

   int               FindActiveBasketIds(const string symbol,
                                         CBasketId &outBasketIds[],
                                         const int maxCount) const
     {
      int written=0;
      for(int i=0;i<m_count && written<maxCount;i++)
        {
         if(m_symbols[i]!=symbol)
            continue;
         ArrayResize(outBasketIds,written+1);
         outBasketIds[written]=CBasketId(m_basketIds[i]);
         written++;
        }
      return written;
     }

   int               TotalActiveBasketCount(void) const { return m_count; }
  };

#endif
