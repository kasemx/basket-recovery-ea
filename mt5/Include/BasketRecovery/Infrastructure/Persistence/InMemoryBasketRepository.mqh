#ifndef BASKET_RECOVERY_INFRASTRUCTURE_IN_MEMORY_BASKET_REPOSITORY_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_IN_MEMORY_BASKET_REPOSITORY_MQH

#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CInMemoryBasketRepository : public IBasketRepository
  {
private:
   CBasketAggregate *m_items[];
   string            m_keys[];
   int               m_count;

   int FindIndex(const CBasketId &basketId) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_keys[i]==basketId.Value())
            return i;
        }
      return -1;
     }

public:
                     CInMemoryBasketRepository(void)
     {
      m_count=0;
      ArrayResize(m_items,0);
      ArrayResize(m_keys,0);
     }

   virtual          ~CInMemoryBasketRepository(void)
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL)
           {
            delete m_items[i];
            m_items[i]=NULL;
           }
        }
     }

   virtual CResult<CBasketAggregate> Load(const CBasketId &basketId) const
     {
      if(basketId.IsEmpty())
         return CResult<CBasketAggregate>::Fail(BRE_ERR_BASKET_NOT_FOUND,"Basket id is empty");

      int index=FindIndex(basketId);
      if(index<0)
         return CResult<CBasketAggregate>::Fail(BRE_ERR_BASKET_NOT_FOUND,"Basket not found");

      return CResult<CBasketAggregate>::Ok(*m_items[index]);
     }

   virtual CVoidResult Save(const CBasketAggregate &aggregate)
     {
      if(aggregate.Id().IsEmpty())
         return CVoidResult::Fail(BRE_ERR_BASKET_INVALID,"Basket id is empty");

      int index=FindIndex(aggregate.Id());
      if(index<0)
        {
         CBasketAggregate *stored=new CBasketAggregate(aggregate);
         ArrayResize(m_items,m_count+1);
         ArrayResize(m_keys,m_count+1);
         m_items[m_count]=stored;
         m_keys[m_count]=aggregate.Id().Value();
         m_count++;
         return CVoidResult::Ok();
        }

      delete m_items[index];
      m_items[index]=new CBasketAggregate(aggregate);
      return CVoidResult::Ok();
     }

   virtual bool      Exists(const CBasketId &basketId) const
     {
      return FindIndex(basketId)>=0;
     }

   virtual CVoidResult Delete(const CBasketId &basketId)
     {
      int index=FindIndex(basketId);
      if(index<0)
         return CVoidResult::Ok();

      if(m_items[index]!=NULL)
        {
         delete m_items[index];
         m_items[index]=NULL;
        }

      for(int i=index;i<m_count-1;i++)
        {
         m_items[i]=m_items[i+1];
         m_keys[i]=m_keys[i+1];
        }

      m_count--;
      ArrayResize(m_items,m_count);
      ArrayResize(m_keys,m_count);
      return CVoidResult::Ok();
     }

   virtual int       Count(void) const { return m_count; }

   virtual int       LoadAll(CBasketAggregate &aggregates[]) const
     {
      ArrayResize(aggregates,m_count);
      for(int i=0;i<m_count;i++)
         aggregates[i]=*m_items[i];
      return m_count;
     }
  };

#endif
