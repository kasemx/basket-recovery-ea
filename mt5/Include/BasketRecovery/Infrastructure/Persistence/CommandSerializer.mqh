#ifndef BASKET_RECOVERY_INFRASTRUCTURE_COMMAND_SERIALIZER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_COMMAND_SERIALIZER_MQH

#include <BasketRecovery/Application/Commands/ICommand.mqh>
#include <BasketRecovery/Application/Commands/CreateBasketCommand.mqh>
#include <BasketRecovery/Application/Commands/ActivateBasketCommand.mqh>
#include <BasketRecovery/Application/Commands/UpdateSLCommand.mqh>
#include <BasketRecovery/Application/Commands/UpdateTPCommand.mqh>
#include <BasketRecovery/Application/Commands/CloseBasketCommand.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonWriter.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CCommandSerializer
  {
private:
   CJsonWriter m_writer;

   string            SerializeCommandFields(const ICommand *command) const
     {
      if(command==NULL)
         return "";

      string fields="";
      fields+=m_writer.FieldInt("command_type",(long)command.Type())+",";
      fields+=m_writer.FieldString("command_id",command.Id().Value())+",";
      fields+=m_writer.FieldString("idempotency_key",command.IdempotencyKey())+",";
      fields+=m_writer.FieldString("basket_id",command.BasketId().Value())+",";
      fields+=m_writer.FieldString("correlation_key",command.CorrelationKey())+",";
      fields+=m_writer.FieldInt("status",(long)command.Status())+",";
      fields+=m_writer.FieldInt("priority",(long)command.Priority())+",";
      fields+=m_writer.FieldString("source",command.Source())+",";
      fields+=m_writer.FieldInt("enqueued_at",(long)command.EnqueuedAt())+",";

      CCommandBase *commandBase=(CCommandBase*)command;
      fields+=m_writer.FieldInt("retry_count",(long)commandBase.RetryCount())+",";

      switch(command.Type())
        {
         case BRE_COMMAND_CREATE_BASKET:
           {
            CCreateBasketCommand *createCommand=(CCreateBasketCommand*)command;
            fields+=m_writer.FieldString("symbol",createCommand.Symbol())+",";
            fields+=m_writer.FieldInt("direction",(long)createCommand.Direction())+",";
            fields+=m_writer.FieldString("signal_id",createCommand.SignalId().Value());
            break;
           }
         case BRE_COMMAND_ACTIVATE_BASKET:
           {
            CActivateBasketCommand *activateCommand=(CActivateBasketCommand*)command;
            fields+=m_writer.FieldString("signal_id",activateCommand.SignalId().Value())+",";
            CSignalDetails details=activateCommand.Details();
            fields+=m_writer.FieldBool("signal_has_details",details.HasDetails())+",";
            fields+=m_writer.FieldDouble("signal_stop_loss",details.StopLoss().Value())+",";
            fields+=m_writer.FieldDouble("signal_tp1",details.Tp1().Value());
            break;
           }
         case BRE_COMMAND_UPDATE_SL:
           {
            CUpdateSLCommand *updateSlCommand=(CUpdateSLCommand*)command;
            fields+=m_writer.FieldDouble("stop_loss",updateSlCommand.StopLoss().Value())+",";
            fields+=m_writer.FieldString("signal_id",updateSlCommand.SignalId().Value());
            break;
           }
         case BRE_COMMAND_UPDATE_TP:
           {
            CUpdateTPCommand *updateTpCommand=(CUpdateTPCommand*)command;
            fields+=m_writer.FieldString("signal_id",updateTpCommand.SignalId().Value())+",";
            CSignalDetails details=updateTpCommand.Details();
            fields+=m_writer.FieldBool("signal_has_details",details.HasDetails())+",";
            fields+=m_writer.FieldDouble("signal_tp1",details.Tp1().Value());
            break;
           }
         case BRE_COMMAND_CLOSE_BASKET:
           {
            CCloseBasketCommand *closeCommand=(CCloseBasketCommand*)command;
            fields+=m_writer.FieldString("close_reason",closeCommand.Reason());
            break;
           }
         default:
            fields+=m_writer.FieldString("payload","");
            break;
        }
      return fields;
     }

   ICommand*         CreateCommandFromReader(const CJsonReader &reader,const string block) const
     {
      CJsonReader blockReader;
      blockReader.SetContent(block);

      ENUM_BRE_COMMAND_TYPE commandType=(ENUM_BRE_COMMAND_TYPE)blockReader.ReadInt("command_type",BRE_COMMAND_NONE);
      ICommand *command=NULL;

      switch(commandType)
        {
         case BRE_COMMAND_CREATE_BASKET:
           {
            CCreateBasketCommand *createCommand=new CCreateBasketCommand();
            createCommand.SetSymbol(blockReader.ReadString("symbol",""));
            createCommand.SetDirection((ENUM_BRE_TRADE_DIRECTION)blockReader.ReadInt("direction",BRE_DIRECTION_NONE));
            createCommand.SetSignalId(CSignalId(blockReader.ReadString("signal_id","")));
            command=createCommand;
            break;
           }
         case BRE_COMMAND_ACTIVATE_BASKET:
           {
            CActivateBasketCommand *activateCommand=new CActivateBasketCommand();
            activateCommand.SetSignalId(CSignalId(blockReader.ReadString("signal_id","")));
            CSignalDetails details;
            details.SetHasDetails(blockReader.ReadBool("signal_has_details",false));
            details.SetStopLoss(CPrice(blockReader.ReadDouble("signal_stop_loss",0.0)));
            details.SetTp1(CPrice(blockReader.ReadDouble("signal_tp1",0.0)));
            activateCommand.SetDetails(details);
            command=activateCommand;
            break;
           }
         case BRE_COMMAND_UPDATE_SL:
           {
            CUpdateSLCommand *updateSlCommand=new CUpdateSLCommand();
            updateSlCommand.SetStopLoss(CPrice(blockReader.ReadDouble("stop_loss",0.0)));
            updateSlCommand.SetSignalId(CSignalId(blockReader.ReadString("signal_id","")));
            command=updateSlCommand;
            break;
           }
         case BRE_COMMAND_UPDATE_TP:
           {
            CUpdateTPCommand *updateTpCommand=new CUpdateTPCommand();
            updateTpCommand.SetSignalId(CSignalId(blockReader.ReadString("signal_id","")));
            CSignalDetails details;
            details.SetHasDetails(blockReader.ReadBool("signal_has_details",false));
            details.SetTp1(CPrice(blockReader.ReadDouble("signal_tp1",0.0)));
            updateTpCommand.SetDetails(details);
            command=updateTpCommand;
            break;
           }
         case BRE_COMMAND_CLOSE_BASKET:
           {
            CCloseBasketCommand *closeCommand=new CCloseBasketCommand();
            closeCommand.SetReason(blockReader.ReadString("close_reason",""));
            command=closeCommand;
            break;
           }
         default:
            return NULL;
        }

      if(command==NULL)
         return NULL;

      CCommandBase *commandBase=(CCommandBase*)command;
      commandBase.SetId(CCommandId(blockReader.ReadString("command_id","")));
      commandBase.SetType(commandType);
      commandBase.SetIdempotencyKey(blockReader.ReadString("idempotency_key",""));
      commandBase.SetBasketId(CBasketId(blockReader.ReadString("basket_id","")));
      commandBase.SetCorrelationKey(blockReader.ReadString("correlation_key",""));
      commandBase.SetStatus((ENUM_BRE_COMMAND_STATUS)blockReader.ReadInt("status",BRE_COMMAND_STATUS_PENDING));
      commandBase.SetPriority(blockReader.ReadInt("priority",10));
      commandBase.SetSource(blockReader.ReadString("source","INTERNAL"));
      commandBase.SetEnqueuedAt((datetime)blockReader.ReadLong("enqueued_at",0));
      commandBase.SetRetryCount(blockReader.ReadInt("retry_count",0));
      return command;
     }

public:
   string            SerializePendingCommands(ICommand *commands[],const int count) const
     {
      string body="\"pending_count\":"+IntegerToString(count)+",\"commands\":[";
      for(int i=0;i<count;i++)
        {
         if(i>0)
            body+=",";
         body+="{";
         body+=SerializeCommandFields(commands[i]);
         body+="}";
        }
      body+="]";
      return m_writer.BuildEnvelope(BRE_PERSISTENCE_SCHEMA_VERSION,body);
     }

   CResult<int>      DeserializePendingCommands(const string jsonContent,ICommand * &commands[]) const
     {
      ArrayResize(commands,0);
      CJsonReader reader;
      reader.SetContent(jsonContent);
      if(reader.ValidateSchemaVersion(BRE_PERSISTENCE_SCHEMA_VERSION).IsFail())
         return CResult<int>::Fail(BRE_ERR_PERSIST_SCHEMA_UNSUPPORTED,"Unsupported command schema version");

      int pendingCount=reader.ReadInt("pending_count",0);
      int arrayStart=StringFind(jsonContent,"\"commands\":[");
      if(arrayStart<0)
         return CResult<int>::Ok(0);

      arrayStart=StringFind(jsonContent,"[",arrayStart);
      int arrayEnd=StringFind(jsonContent,"]",arrayStart);
      if(arrayEnd<0)
         return CResult<int>::Fail(BRE_ERR_PERSIST_CORRUPT,"Command array is invalid");

      string body=StringSubstr(jsonContent,arrayStart+1,arrayEnd-arrayStart-1);
      if(StringLen(body)==0)
         return CResult<int>::Ok(0);

      string blocks[];
      int blockCount=0;
      int depth=0;
      int blockStart=-1;
      for(int i=0;i<StringLen(body);i++)
        {
         ushort ch=StringGetCharacter(body,i);
         if(ch=='{')
           {
            if(depth==0)
               blockStart=i;
            depth++;
           }
         else if(ch=='}')
           {
            depth--;
            if(depth==0 && blockStart>=0)
              {
               ArrayResize(blocks,blockCount+1);
               blocks[blockCount]=StringSubstr(body,blockStart,i-blockStart+1);
               blockCount++;
               blockStart=-1;
              }
           }
        }

      int loadedCount=0;
      for(int i=0;i<blockCount;i++)
        {
         ICommand *command=CreateCommandFromReader(reader,blocks[i]);
         if(command==NULL)
            continue;
         if(command.Status()!=BRE_COMMAND_STATUS_PENDING)
           {
            delete command;
            continue;
           }
         ArrayResize(commands,loadedCount+1);
         commands[loadedCount]=command;
         loadedCount++;
        }

      if(pendingCount>0 && loadedCount==0 && blockCount>0)
         return CResult<int>::Fail(BRE_ERR_PERSIST_CORRUPT,"Pending commands could not be restored");

      return CResult<int>::Ok(loadedCount);
     }
  };

#endif
