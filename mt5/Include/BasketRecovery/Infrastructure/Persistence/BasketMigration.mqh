#ifndef BASKET_RECOVERY_INFRASTRUCTURE_BASKET_MIGRATION_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_BASKET_MIGRATION_MQH

#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CBasketMigration
  {
public:
   static CResult<string> MigrateToCurrent(const string jsonContent)
     {
      CJsonReader reader;
      reader.SetContent(jsonContent);
      int version=reader.ReadSchemaVersion();
      if(version<=0)
         return CResult<string>::Fail(BRE_ERR_PERSIST_CORRUPT,"Schema version is missing");

      if(version==BRE_PERSISTENCE_SCHEMA_VERSION)
         return CResult<string>::Ok(jsonContent);

      if(version>BRE_PERSISTENCE_SCHEMA_VERSION)
         return CResult<string>::Fail(BRE_ERR_PERSIST_SCHEMA_UNSUPPORTED,"Schema version is newer than supported");

      switch(version)
        {
         case 1:
            return CResult<string>::Fail(BRE_ERR_PERSIST_MIGRATION_FAILED,"No migration path from schema version 1");
         default:
            return CResult<string>::Fail(BRE_ERR_PERSIST_MIGRATION_FAILED,"Unsupported schema version for migration");
        }
     }
  };

#endif
