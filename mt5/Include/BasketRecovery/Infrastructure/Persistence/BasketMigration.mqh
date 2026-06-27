#ifndef BASKET_RECOVERY_INFRASTRUCTURE_BASKET_MIGRATION_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_BASKET_MIGRATION_MQH

#include <BasketRecovery/Infrastructure/Persistence/BasketSerializer.mqh>
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

      CBasketSerializer serializer;
      CBasketPersistenceDto dto;
      if(!serializer.FromReader(reader,dto,version))
         return CResult<string>::Fail(BRE_ERR_PERSIST_MIGRATION_FAILED,"Failed to read legacy basket payload");

      if(version<=BRE_PERSISTENCE_SCHEMA_VERSION_V2 && !dto.hasStrategySnapshot)
         dto.strategyMigrationRequired=true;

      CBasketAggregate aggregate;
      if(!aggregate.RestoreFromDto(dto))
         return CResult<string>::Fail(BRE_ERR_PERSIST_MIGRATION_FAILED,"Failed to restore basket during migration");

      string migratedJson=serializer.Serialize(aggregate);
      return CResult<string>::Ok(migratedJson);
     }
  };

#endif
