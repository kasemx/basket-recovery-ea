#ifndef BASKET_RECOVERY_INFRASTRUCTURE_IN_MEMORY_IDEMPOTENCY_STORE_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_IN_MEMORY_IDEMPOTENCY_STORE_MQH

#include <BasketRecovery/Application/Ports/IIdempotencyStore.mqh>
#include <BasketRecovery/Application/Ports/IIdempotencyPersistence.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CInMemoryIdempotencyStore : public IIdempotencyStore
  {
private:
   string                 m_keys[];
   int                    m_count;
   IIdempotencyPersistence *m_persistence;

   bool KeyExists(const string &idempotencyKey) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_keys[i]==idempotencyKey)
            return true;
        }
      return false;
     }

public:
                     CInMemoryIdempotencyStore(IIdempotencyPersistence *persistence=NULL)
     {
      m_count=0;
      m_persistence=persistence;
      ArrayResize(m_keys,0);
     }

   virtual          ~CInMemoryIdempotencyStore(void) {}

   virtual bool      IsProcessed(const string &idempotencyKey) const
     {
      if(idempotencyKey=="")
         return false;
      return KeyExists(idempotencyKey);
     }

   virtual CVoidResult MarkProcessed(const string &idempotencyKey)
     {
      if(idempotencyKey=="")
         return CVoidResult::Fail(BRE_ERR_IDEMPOTENCY_DUPLICATE,"Idempotency key is empty");

      if(KeyExists(idempotencyKey))
         return CVoidResult::Ok();

      ArrayResize(m_keys,m_count+1);
      m_keys[m_count]=idempotencyKey;
      m_count++;

      if(m_persistence!=NULL)
         return m_persistence.SaveProcessedKey(idempotencyKey);

      return CVoidResult::Ok();
     }

   virtual CVoidResult Clear(void)
     {
      m_count=0;
      ArrayResize(m_keys,0);
      if(m_persistence!=NULL)
         return m_persistence.ClearAll();
      return CVoidResult::Ok();
     }

   virtual CVoidResult RecoverFromPersistence(void)
     {
      if(m_persistence==NULL)
         return CVoidResult::Ok();

      string keys[];
      CVoidResult loadResult=m_persistence.LoadProcessedKeys(keys);
      if(loadResult.IsFail())
         return loadResult;

      for(int i=0;i<ArraySize(keys);i++)
        {
         if(keys[i]=="" || KeyExists(keys[i]))
            continue;
         ArrayResize(m_keys,m_count+1);
         m_keys[m_count]=keys[i];
         m_count++;
        }
      return CVoidResult::Ok();
     }

   virtual int       Count(void) const { return m_count; }
  };

#endif
