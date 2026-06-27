#ifndef BASKET_RECOVERY_INFRASTRUCTURE_COMMAND_SERIALIZER_STRATEGY_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_COMMAND_SERIALIZER_STRATEGY_MQH

#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonWriter.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>

class CCommandSerializerStrategy
  {
public:
   static string     AppendStrategyFields(const CJsonWriter &writer,const CStrategyCommandBase *command)
     {
      if(command==NULL)
         return "";
      string fields=writer.FieldInt("expected_basket_version",command.ExpectedBasketVersion())+",";
      fields+=writer.FieldString("strategy_profile_hash",command.StrategyProfileHash())+",";
      return fields;
     }

   static void       ApplyStrategyFields(CJsonReader &reader,CStrategyCommandBase *command)
     {
      if(command==NULL)
         return;
      command.SetExpectedBasketVersion(reader.ReadLong("expected_basket_version",-1));
      command.SetStrategyProfileHash(reader.ReadString("strategy_profile_hash",""));
     }

   static string     AppendPayloadFields(const CJsonWriter &writer,const ICommand *command)
     {
      if(command==NULL)
         return writer.FieldString("payload","");

      switch(command.Type())
        {
         case BRE_COMMAND_OPEN_RECOVERY_POSITION:
           {
            COpenRecoveryPositionCommand *typed=(COpenRecoveryPositionCommand*)command;
            return writer.FieldInt("step_index",typed.StepIndex())+","+
                   writer.FieldDouble("lot_size",typed.LotSize());
           }
         case BRE_COMMAND_CLOSE_POSITIONS:
           {
            CClosePositionsCommand *typed=(CClosePositionsCommand*)command;
            return writer.FieldString("level_id",typed.LevelId())+","+
                   writer.FieldDouble("close_percent",typed.ClosePercent())+","+
                   writer.FieldInt("close_mode",(long)typed.CloseMode())+","+
                   writer.FieldBool("partial_close",typed.PartialClose());
           }
         case BRE_COMMAND_MOVE_BASKET_STOP_LOSS:
           {
            CMoveBasketStopLossCommand *typed=(CMoveBasketStopLossCommand*)command;
            return writer.FieldString("rule_id",typed.RuleId())+","+
                   writer.FieldDouble("stop_loss_price",typed.StopLossPrice());
           }
         case BRE_COMMAND_REDUCE_BASKET_RISK:
           {
            CReduceBasketRiskCommand *typed=(CReduceBasketRiskCommand*)command;
            return writer.FieldDouble("close_percent",typed.ClosePercent());
           }
         case BRE_COMMAND_MARK_PROFIT_LEVEL_COMPLETED:
           {
            CMarkProfitLevelCompletedCommand *typed=(CMarkProfitLevelCompletedCommand*)command;
            return writer.FieldString("level_id",typed.LevelId())+","+
                   writer.FieldDouble("realized_profit",typed.RealizedProfit());
           }
         default:
            return writer.FieldString("payload","");
        }
     }

   static ICommand*  CreateStrategyCommand(const ENUM_BRE_COMMAND_TYPE commandType,CJsonReader &reader)
     {
      ICommand *command=NULL;
      switch(commandType)
        {
         case BRE_COMMAND_EVALUATE_STRATEGY:
            command=new CEvaluateStrategyCommand();
            break;
         case BRE_COMMAND_OPEN_RECOVERY_POSITION:
           {
            COpenRecoveryPositionCommand *typed=new COpenRecoveryPositionCommand();
            typed.SetStepIndex(reader.ReadInt("step_index",0));
            typed.SetLotSize(reader.ReadDouble("lot_size",0.0));
            command=typed;
            break;
           }
         case BRE_COMMAND_CLOSE_POSITIONS:
           {
            CClosePositionsCommand *typed=new CClosePositionsCommand();
            typed.SetLevelId(reader.ReadString("level_id",""));
            typed.SetClosePercent(reader.ReadDouble("close_percent",0.0));
            typed.SetCloseMode((ENUM_BRE_CLOSE_MODE)reader.ReadInt("close_mode",BRE_CLOSE_MODE_NONE));
            typed.SetPartialClose(reader.ReadBool("partial_close",false));
            command=typed;
            break;
           }
         case BRE_COMMAND_MOVE_BASKET_STOP_LOSS:
           {
            CMoveBasketStopLossCommand *typed=new CMoveBasketStopLossCommand();
            typed.SetRuleId(reader.ReadString("rule_id",""));
            typed.SetStopLossPrice(reader.ReadDouble("stop_loss_price",0.0));
            command=typed;
            break;
           }
         case BRE_COMMAND_DISABLE_RECOVERY:
            command=new CDisableRecoveryCommand();
            break;
         case BRE_COMMAND_REDUCE_BASKET_RISK:
           {
            CReduceBasketRiskCommand *typed=new CReduceBasketRiskCommand();
            typed.SetClosePercent(reader.ReadDouble("close_percent",0.0));
            command=typed;
            break;
           }
         case BRE_COMMAND_MARK_PROFIT_LEVEL_COMPLETED:
           {
            CMarkProfitLevelCompletedCommand *typed=new CMarkProfitLevelCompletedCommand();
            typed.SetLevelId(reader.ReadString("level_id",""));
            typed.SetRealizedProfit(reader.ReadDouble("realized_profit",0.0));
            command=typed;
            break;
           }
         default:
            return NULL;
        }
      ApplyStrategyFields(reader,(CStrategyCommandBase*)command);
      return command;
     }

   static bool       IsStrategyCommandType(const ENUM_BRE_COMMAND_TYPE commandType)
     {
      switch(commandType)
        {
         case BRE_COMMAND_EVALUATE_STRATEGY:
         case BRE_COMMAND_OPEN_RECOVERY_POSITION:
         case BRE_COMMAND_CLOSE_POSITIONS:
         case BRE_COMMAND_MOVE_BASKET_STOP_LOSS:
         case BRE_COMMAND_DISABLE_RECOVERY:
         case BRE_COMMAND_REDUCE_BASKET_RISK:
         case BRE_COMMAND_MARK_PROFIT_LEVEL_COMPLETED:
            return true;
         default:
            return false;
        }
     }
  };

#endif
