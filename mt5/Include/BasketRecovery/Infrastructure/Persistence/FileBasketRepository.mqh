#ifndef BASKET_RECOVERY_INFRASTRUCTURE_FILE_BASKET_REPOSITORY_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_FILE_BASKET_REPOSITORY_MQH

#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketSerializer.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketMigration.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonWriter.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CFileBasketRepository : public IBasketRepository
  {
private:
   string            m_basketSubdir;
   CBasketSerializer m_serializer;
   CJsonWriter       m_writer;
   bool              m_recoveryMode;

   string            BuildRelativePath(const CBasketId &basketId) const
     {
      return m_basketSubdir+"/"+basketId.Value()+".json";
     }

   string            ReadFileContent(const string relativePath) const
     {
      CJsonReader reader;
      reader.SetRecoveryMode(m_recoveryMode);
      if(reader.LoadFromFile(relativePath).IsFail())
         return "";
      return reader.Content();
     }

public:
                     CFileBasketRepository(const string basketSubdir=BRE_PERSISTENCE_BASKET_SUBDIR,const bool recoveryMode=false)
     {
      m_basketSubdir=basketSubdir;
      m_recoveryMode=recoveryMode;
     }

   void              SetRecoveryMode(const bool value) { m_recoveryMode=value; }

   virtual CResult<CBasketAggregate> Load(const CBasketId &basketId) const
     {
      if(basketId.IsEmpty())
         return CResult<CBasketAggregate>::Fail(BRE_ERR_BASKET_NOT_FOUND,"Basket id is empty");

      string relativePath=BuildRelativePath(basketId);
      if(!FileIsExist(relativePath,FILE_COMMON) && !FileIsExist(relativePath+".bak",FILE_COMMON))
         return CResult<CBasketAggregate>::Fail(BRE_ERR_BASKET_NOT_FOUND,"Basket file is missing");

      string content=ReadFileContent(relativePath);
      if(content=="")
         return CResult<CBasketAggregate>::Fail(BRE_ERR_PERSIST_READ_FAILED,"Basket file could not be read");

      CResult<string> migrated=CBasketMigration::MigrateToCurrent(content);
      if(migrated.IsFail())
         return CResult<CBasketAggregate>::Fail(migrated.ErrorCode(),migrated.ErrorMessage());

      string migratedContent;
      if(!migrated.TryGetValue(migratedContent))
         return CResult<CBasketAggregate>::Fail(BRE_ERR_PERSIST_MIGRATION_FAILED,"Migration result is empty");

      return m_serializer.Deserialize(migratedContent,m_recoveryMode);
     }

   virtual CVoidResult Save(const CBasketAggregate &aggregate)
     {
      if(aggregate.Id().IsEmpty())
         return CVoidResult::Fail(BRE_ERR_BASKET_INVALID,"Basket id is empty");

      string jsonContent=m_serializer.Serialize(aggregate);
      string relativePath=BuildRelativePath(aggregate.Id());
      return m_writer.WriteAtomic(relativePath,jsonContent);
     }

   virtual bool      Exists(const CBasketId &basketId) const
     {
      if(basketId.IsEmpty())
         return false;
      string relativePath=BuildRelativePath(basketId);
      return FileIsExist(relativePath,FILE_COMMON);
     }

   virtual CVoidResult Delete(const CBasketId &basketId)
     {
      if(basketId.IsEmpty())
         return CVoidResult::Ok();

      string relativePath=BuildRelativePath(basketId);
      FileDelete(relativePath,FILE_COMMON);
      FileDelete(relativePath+".bak",FILE_COMMON);
      FileDelete(relativePath+".tmp",FILE_COMMON);
      return CVoidResult::Ok();
     }

   virtual int       Count(void) const
     {
      string basketIds[];
      LoadAllBasketIds(basketIds);
      return ArraySize(basketIds);
     }

   int               LoadAllBasketIds(string &basketIds[]) const
     {
      ArrayResize(basketIds,0);
      string searchPath=m_basketSubdir+"/*.json";
      string fileName;
      long handle=FileFindFirst(searchPath,fileName,FILE_COMMON);
      if(handle==INVALID_HANDLE)
         return 0;

      int count=0;
      do
        {
         if(StringFind(fileName,".json.bak")>=0 || StringFind(fileName,".json.tmp")>=0)
            continue;

         int extensionIndex=StringFind(fileName,".json");
         if(extensionIndex<0)
            continue;

         string basketId=StringSubstr(fileName,0,extensionIndex);
         ArrayResize(basketIds,count+1);
         basketIds[count]=basketId;
         count++;
        }
      while(FileFindNext(handle,fileName));

      FileFindClose(handle);
      return count;
     }

   int               LoadAll(CBasketAggregate &aggregates[]) const
     {
      string basketIds[];
      int idCount=LoadAllBasketIds(basketIds);
      ArrayResize(aggregates,0);
      int loadedCount=0;

      for(int i=0;i<idCount;i++)
        {
         CResult<CBasketAggregate> loaded=Load(CBasketId(basketIds[i]));
         if(loaded.IsFail())
            continue;

         CBasketAggregate aggregate;
         if(!loaded.TryGetValue(aggregate))
            continue;

         ArrayResize(aggregates,loadedCount+1);
         aggregates[loadedCount]=aggregate;
         loadedCount++;
        }
      return loadedCount;
     }
  };

#endif
