#ifndef BASKET_RECOVERY_INFRASTRUCTURE_REST_COMMAND_JSON_PARSER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_REST_COMMAND_JSON_PARSER_MQH

#include <BasketRecovery/Application/Commands/ICommand.mqh>
#include <BasketRecovery/Application/Commands/CreateBasketCommand.mqh>
#include <BasketRecovery/Application/Commands/ActivateBasketCommand.mqh>
#include <BasketRecovery/Application/Commands/UpdateSLCommand.mqh>
#include <BasketRecovery/Application/Commands/UpdateTPCommand.mqh>
#include <BasketRecovery/Application/Commands/CloseBasketCommand.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CRestCommandJsonParser
  {
private:
   ENUM_BRE_COMMAND_TYPE ParseCommandType(const string typeName,const int typeCode) const
     {
      if(typeCode>0)
         return (ENUM_BRE_COMMAND_TYPE)typeCode;

      if(typeName=="CreateBasketCommand" || typeName=="CREATE_BASKET")
         return BRE_COMMAND_CREATE_BASKET;
      if(typeName=="ActivateBasketCommand" || typeName=="ACTIVATE_BASKET")
         return BRE_COMMAND_ACTIVATE_BASKET;
      if(typeName=="UpdateSLCommand" || typeName=="UPDATE_SL")
         return BRE_COMMAND_UPDATE_SL;
      if(typeName=="UpdateTPCommand" || typeName=="UPDATE_TP")
         return BRE_COMMAND_UPDATE_TP;
      if(typeName=="CloseBasketCommand" || typeName=="CLOSE_BASKET")
         return BRE_COMMAND_CLOSE_BASKET;
      return BRE_COMMAND_NONE;
     }

   ENUM_BRE_TRADE_DIRECTION ParseDirection(const string directionName,const int directionCode) const
     {
      if(directionCode>0)
         return (ENUM_BRE_TRADE_DIRECTION)directionCode;
      if(directionName=="BUY")
         return BRE_DIRECTION_BUY;
      if(directionName=="SELL")
         return BRE_DIRECTION_SELL;
      return BRE_DIRECTION_NONE;
     }

   bool              ValidateCommonFields(const CJsonReader &reader,string &errorMessage) const
     {
      if(reader.ReadString("command_id","")=="")
        {
         errorMessage="command_id is required";
         return false;
        }
      ENUM_BRE_COMMAND_TYPE commandType=ParseCommandType(reader.ReadString("command_type",""),
                                                       reader.ReadInt("command_type",0));
      if(commandType==BRE_COMMAND_NONE)
        {
         errorMessage="command_type is invalid";
         return false;
        }
      return true;
     }

   ICommand*         CreateFromBlock(const string block,int &rejectedCount,string &lastError) const
     {
      CJsonReader reader;
      reader.SetContent(block);
      string validationError="";
      if(!ValidateCommonFields(reader,validationError))
        {
         rejectedCount++;
         lastError=validationError;
         return NULL;
        }

      ENUM_BRE_COMMAND_TYPE commandType=ParseCommandType(reader.ReadString("command_type",""),
                                                         reader.ReadInt("command_type",0));
      ICommand *command=NULL;

      switch(commandType)
        {
         case BRE_COMMAND_CREATE_BASKET:
           {
            if(reader.ReadString("symbol","")=="")
              {
               rejectedCount++;
               lastError="CreateBasketCommand requires symbol";
               return NULL;
              }
            ENUM_BRE_TRADE_DIRECTION direction=ParseDirection(reader.ReadString("direction",""),
                                                              reader.ReadInt("direction",0));
            if(direction==BRE_DIRECTION_NONE)
              {
               rejectedCount++;
               lastError="CreateBasketCommand requires direction";
               return NULL;
              }
            CCreateBasketCommand *createCommand=new CCreateBasketCommand();
            createCommand.SetSymbol(reader.ReadString("symbol",""));
            createCommand.SetDirection(direction);
            createCommand.SetSignalId(CSignalId(reader.ReadString("signal_id","")));
            command=createCommand;
            break;
           }
         case BRE_COMMAND_ACTIVATE_BASKET:
           {
            CActivateBasketCommand *activateCommand=new CActivateBasketCommand();
            activateCommand.SetSignalId(CSignalId(reader.ReadString("signal_id","")));
            CSignalDetails details;
            details.SetHasDetails(reader.ReadBool("signal_has_details",false));
            details.SetStopLoss(CPrice(reader.ReadDouble("signal_stop_loss",0.0)));
            details.SetTp1(CPrice(reader.ReadDouble("signal_tp1",0.0)));
            details.SetTp2(CPrice(reader.ReadDouble("signal_tp2",0.0)));
            details.SetTp3(CPrice(reader.ReadDouble("signal_tp3",0.0)));
            details.SetTp4(CPrice(reader.ReadDouble("signal_tp4",0.0)));
            details.SetTpOpen(reader.ReadBool("signal_tp_open",false));
            activateCommand.SetDetails(details);
            command=activateCommand;
            break;
           }
         case BRE_COMMAND_UPDATE_SL:
           {
            CUpdateSLCommand *updateSlCommand=new CUpdateSLCommand();
            updateSlCommand.SetStopLoss(CPrice(reader.ReadDouble("stop_loss",0.0)));
            updateSlCommand.SetSignalId(CSignalId(reader.ReadString("signal_id","")));
            command=updateSlCommand;
            break;
           }
         case BRE_COMMAND_UPDATE_TP:
           {
            CUpdateTPCommand *updateTpCommand=new CUpdateTPCommand();
            updateTpCommand.SetSignalId(CSignalId(reader.ReadString("signal_id","")));
            CSignalDetails details;
            details.SetHasDetails(reader.ReadBool("signal_has_details",false));
            details.SetTp1(CPrice(reader.ReadDouble("signal_tp1",0.0)));
            updateTpCommand.SetDetails(details);
            command=updateTpCommand;
            break;
           }
         case BRE_COMMAND_CLOSE_BASKET:
           {
            CCloseBasketCommand *closeCommand=new CCloseBasketCommand();
            closeCommand.SetReason(reader.ReadString("close_reason",""));
            command=closeCommand;
            break;
           }
         default:
            rejectedCount++;
            lastError="Unsupported command_type";
            return NULL;
        }

      if(command==NULL)
         return NULL;

      CCommandBase *commandBase=(CCommandBase*)command;
      commandBase.SetId(CCommandId(reader.ReadString("command_id","")));
      commandBase.SetType(commandType);
      commandBase.SetIdempotencyKey(reader.ReadString("idempotency_key",""));
      commandBase.SetBasketId(CBasketId(reader.ReadString("basket_id","")));
      commandBase.SetCorrelationKey(reader.ReadString("correlation_key",""));
      commandBase.SetStatus(BRE_COMMAND_STATUS_PENDING);
      commandBase.SetPriority(reader.ReadInt("priority",commandBase.Priority()));
      commandBase.SetSource(reader.ReadString("source","REST"));
      commandBase.SetEnqueuedAt((datetime)reader.ReadLong("enqueued_at",TimeGMT()));
      commandBase.SetRetryCount(reader.ReadInt("retry_count",0));
      return command;
     }

   int               ExtractCommandBlocks(const string jsonContent,string &blocks[]) const
     {
      int arrayStart=StringFind(jsonContent,"\"commands\":[");
      if(arrayStart<0)
         return 0;
      arrayStart=StringFind(jsonContent,"[",arrayStart);
      int arrayEnd=StringFind(jsonContent,"]",arrayStart);
      if(arrayStart<0 || arrayEnd<0)
         return 0;

      string body=StringSubstr(jsonContent,arrayStart+1,arrayEnd-arrayStart-1);
      if(StringLen(body)==0)
         return 0;

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
      return blockCount;
     }

public:
   CResult<int>      ParsePendingResponse(const string jsonContent,
                                          ICommand * &commands[],
                                          int &rejectedCount,
                                          string &cursor) const
     {
      ArrayResize(commands,0);
      rejectedCount=0;
      cursor="";

      if(StringLen(jsonContent)==0)
         return CResult<int>::Fail(BRE_ERR_REST_PARSE_FAILED,"Pending response body is empty");

      CJsonReader envelopeReader;
      envelopeReader.SetContent(jsonContent);
      if(!envelopeReader.HasKey("commands"))
         return CResult<int>::Fail(BRE_ERR_REST_PARSE_FAILED,"Pending response is missing commands array");

      cursor=envelopeReader.ReadString("cursor","");

      string blocks[];
      int blockCount=ExtractCommandBlocks(jsonContent,blocks);
      int loadedCount=0;
      string lastError="";

      for(int i=0;i<blockCount;i++)
        {
         ICommand *command=CreateFromBlock(blocks[i],rejectedCount,lastError);
         if(command==NULL)
            continue;
         ArrayResize(commands,loadedCount+1);
         commands[loadedCount]=command;
         loadedCount++;
        }

      if(blockCount>0 && loadedCount==0)
         return CResult<int>::Fail(BRE_ERR_REST_VALIDATION_FAILED,
                                   lastError=="" ? "All pending commands were rejected" : lastError);

      return CResult<int>::Ok(loadedCount);
     }
  };

#endif
