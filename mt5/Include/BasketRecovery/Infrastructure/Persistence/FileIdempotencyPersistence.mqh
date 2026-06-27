#ifndef BASKET_RECOVERY_INFRASTRUCTURE_FILE_IDEMPOTENCY_PERSISTENCE_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_FILE_IDEMPOTENCY_PERSISTENCE_MQH

#include <BasketRecovery/Application/Ports/IIdempotencyPersistence.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonWriter.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CFileIdempotencyPersistence : public IIdempotencyPersistence
  {
private:
   string      m_relativePath;
   CJsonWriter m_writer;
   bool        m_recoveryMode;

   bool          KeyExists(const string &idempotencyKey,const string &keys[],const int count) const
     {
      for(int i=0;i<count;i++)
        {
         if(keys[i]==idempotencyKey)
            return true;
        }
      return false;
     }

public:
                     CFileIdempotencyPersistence(const string relativePath=BRE_PERSISTENCE_IDEMPOTENCY_FILE,const bool recoveryMode=false)
     {
      m_relativePath=relativePath;
      m_recoveryMode=recoveryMode;
     }

   void              SetRecoveryMode(const bool value) { m_recoveryMode=value; }

   virtual CVoidResult SaveProcessedKey(const string &idempotencyKey)
     {
      if(idempotencyKey=="")
         return CVoidResult::Fail(BRE_ERR_IDEMPOTENCY_DUPLICATE,"Idempotency key is empty");

      string keys[];
      LoadProcessedKeys(keys);
      if(KeyExists(idempotencyKey,keys,ArraySize(keys)))
         return CVoidResult::Ok();

      int count=ArraySize(keys);
      ArrayResize(keys,count+1);
      keys[count]=idempotencyKey;

      string body=m_writer.StringArrayField("processed_keys",keys,count+1);
      string json=m_writer.BuildEnvelope(BRE_PERSISTENCE_SCHEMA_VERSION,body);
      return m_writer.WriteAtomic(m_relativePath,json);
     }

   virtual CVoidResult LoadProcessedKeys(string &keys[]) const
     {
      ArrayResize(keys,0);
      CJsonReader reader;
      reader.SetRecoveryMode(m_recoveryMode);
      if(reader.LoadFromFile(m_relativePath).IsFail())
         return CVoidResult::Ok();

      reader.ReadStringArray("processed_keys",keys);
      return CVoidResult::Ok();
     }

   virtual CVoidResult ClearAll(void)
     {
      FileDelete(m_relativePath,FILE_COMMON);
      FileDelete(m_relativePath+".bak",FILE_COMMON);
      FileDelete(m_relativePath+".tmp",FILE_COMMON);
      return CVoidResult::Ok();
     }
  };

#endif
