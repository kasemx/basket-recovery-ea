#ifndef BASKET_RECOVERY_INFRASTRUCTURE_FILE_COMMAND_PERSISTENCE_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_FILE_COMMAND_PERSISTENCE_MQH

#include <BasketRecovery/Application/Ports/ICommandPersistence.mqh>
#include <BasketRecovery/Infrastructure/Persistence/CommandSerializer.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonWriter.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CFileCommandPersistence : public ICommandPersistence
  {
private:
   string             m_relativePath;
   CCommandSerializer m_serializer;
   CJsonWriter        m_writer;
   bool               m_recoveryMode;

public:
                     CFileCommandPersistence(const string relativePath=BRE_PERSISTENCE_PENDING_COMMANDS_FILE,const bool recoveryMode=false)
     {
      m_relativePath=relativePath;
      m_recoveryMode=recoveryMode;
     }

   void              SetRecoveryMode(const bool value) { m_recoveryMode=value; }

   virtual CVoidResult SavePendingCommands(ICommand *commands[],const int count)
     {
      string jsonContent=m_serializer.SerializePendingCommands(commands,count);
      return m_writer.WriteAtomic(m_relativePath,jsonContent);
     }

   virtual CResult<int> LoadPendingCommands(ICommand * &commands[])
     {
      ArrayResize(commands,0);
      CJsonReader reader;
      reader.SetRecoveryMode(m_recoveryMode);
      if(reader.LoadFromFile(m_relativePath).IsFail())
         return CResult<int>::Ok(0);

      return m_serializer.DeserializePendingCommands(reader.Content(),commands);
     }

   virtual CVoidResult ClearPendingCommands(void)
     {
      FileDelete(m_relativePath,FILE_COMMON);
      FileDelete(m_relativePath+".bak",FILE_COMMON);
      FileDelete(m_relativePath+".tmp",FILE_COMMON);
      return CVoidResult::Ok();
     }
  };

#endif
