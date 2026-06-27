#ifndef BRE_INF_STRATEGY_PROFILE_JSON_SECTIONS_MQH
#define BRE_INF_STRATEGY_PROFILE_JSON_SECTIONS_MQH

#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonBlockReader.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ExecutionZone.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitDistributionPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RiskPlan.mqh>
#include <BasketRecovery/Domain/Configuration/ExecutionProfileConfig.mqh>

class CStrategyProfileJsonSections
  {
public:
   static CExecutionZone ParseExecutionZone(const string block)
     {
      CJsonReader reader;
      reader.SetContent(block);
      ENUM_BRE_EXECUTION_ZONE_SOURCE source=CExecutionZoneSourceHelper::FromString(reader.ReadString("source",""));
      ENUM_BRE_EXECUTION_ZONE_EXPANSION_MODE expansionMode=CExecutionZoneExpansionModeHelper::FromString(reader.ReadString("expansion_mode","SYMMETRIC"));
      bool expansionDisabled=reader.ReadBool("expansion_disabled",false);
      double aboveEntryPips=reader.ReadDouble("above_entry_pips",0.0);
      double belowEntryPips=reader.ReadDouble("below_entry_pips",0.0);
      double maxDistance=reader.ReadDouble("max_recovery_distance_pips",0.0);
      bool hasMaxDistance=reader.HasKey("max_recovery_distance_pips") && maxDistance>0.0;

      if(source==BRE_EXECUTION_ZONE_SOURCE_FIXED_RANGE)
        {
         string fixedBlock=CStrategyProfileJsonBlockReader::ExtractObjectAfterKey(block,"fixed_range");
         CJsonReader fixedReader;
         fixedReader.SetContent(fixedBlock);
         return CExecutionZone::CreateFixedRange(fixedReader.ReadDouble("low",0.0),
                                                 fixedReader.ReadDouble("high",0.0),
                                                 expansionMode,
                                                 aboveEntryPips,
                                                 belowEntryPips,
                                                 expansionDisabled,
                                                 maxDistance,
                                                 hasMaxDistance);
        }

      return CExecutionZone::CreateSignalRange(expansionMode,
                                               aboveEntryPips,
                                               belowEntryPips,
                                               expansionDisabled,
                                               maxDistance,
                                               hasMaxDistance);
     }

   static CRecoveryPlan ParseRecoveryPlan(const string block)
     {
      CJsonReader reader;
      reader.SetContent(block);
      ENUM_BRE_RECOVERY_ALGORITHM algorithm=CRecoveryAlgorithmHelper::FromString(reader.ReadString("algorithm",""));
      bool allowDuringProfitTaking=reader.ReadBool("allow_during_profit_taking",true);
      bool disableAfterBreakEven=reader.ReadBool("disable_after_break_even",true);
      int initialPositionCount=reader.ReadInt("initial_position_count",3);
      double initialLotSize=reader.ReadDouble("initial_lot_size",0.01);

      if(algorithm==BRE_RECOVERY_ALGORITHM_CONSTANT)
        {
         int maxSteps=reader.ReadInt("max_steps",50);
         bool hasMaxSteps=reader.HasKey("max_steps");
         return CRecoveryPlan::CreateConstant(reader.ReadDouble("constant_distance_pips",0.2),
                                              reader.ReadDouble("constant_lot",0.01),
                                              maxSteps,
                                              hasMaxSteps,
                                              allowDuringProfitTaking,
                                              disableAfterBreakEven,
                                              initialPositionCount,
                                              initialLotSize);
        }

      if(algorithm==BRE_RECOVERY_ALGORITHM_CUSTOM)
        {
         string stepBlocks[];
         int stepCount=CStrategyProfileJsonBlockReader::ExtractObjectArrayBlocks(block,"steps",stepBlocks);
         CRecoveryStep steps[];
         ArrayResize(steps,stepCount);
         for(int i=0;i<stepCount;i++)
           {
            CJsonReader stepReader;
            stepReader.SetContent(stepBlocks[i]);
            steps[i]=CRecoveryStep::Create(stepReader.ReadInt("step_index",i+1),
                                           stepReader.ReadDouble("distance_pips",0.0),
                                           stepReader.ReadDouble("lot",0.01));
           }
         return CRecoveryPlan::CreateCustom(steps,stepCount,allowDuringProfitTaking,disableAfterBreakEven,initialPositionCount,initialLotSize);
        }

      return CRecoveryPlan::CreatePlaceholder(algorithm,allowDuringProfitTaking,disableAfterBreakEven,initialPositionCount,initialLotSize);
     }

   static CProfitDistributionPlan ParseProfitDistributionPlan(const string block)
     {
      CJsonReader reader;
      reader.SetContent(block);
      bool requireFloating=reader.ReadBool("require_floating_profit_positive",true);
      ENUM_BRE_CLOSE_MODE defaultCloseMode=CCloseModeHelper::FromString(reader.ReadString("default_close_mode","WORST_ENTRY_FIRST"));

      string levelBlocks[];
      int levelCount=CStrategyProfileJsonBlockReader::ExtractObjectArrayBlocks(block,"levels",levelBlocks);
      CProfitLevel levels[];
      ArrayResize(levels,levelCount);
      for(int i=0;i<levelCount;i++)
        {
         CJsonReader levelReader;
         levelReader.SetContent(levelBlocks[i]);
         double price=levelReader.ReadDouble("price",0.0);
         bool hasPrice=levelReader.HasKey("price");
         levels[i]=CProfitLevel::Create(levelReader.ReadString("level_id",""),
                                        levelReader.ReadInt("level_index",i+1),
                                        CProfitLevelSourceHelper::FromString(levelReader.ReadString("source","SIGNAL_TP")),
                                        price,
                                        hasPrice,
                                        levelReader.ReadDouble("close_percent",0.0),
                                        CCloseModeHelper::FromString(levelReader.ReadString("close_mode","WORST_ENTRY_FIRST")),
                                        levelReader.ReadBool("partial_close",true),
                                        levelReader.ReadBool("enable_trailing",false),
                                        levelReader.ReadBool("enabled",true));
        }
      return CProfitDistributionPlan::Create(requireFloating,defaultCloseMode,levels,levelCount);
     }

   static CBreakEvenPlan ParseBreakEvenPlan(const string block)
     {
      string ruleBlocks[];
      int ruleCount=CStrategyProfileJsonBlockReader::ExtractObjectArrayBlocks(block,"rules",ruleBlocks);
      CBreakEvenRule rules[];
      ArrayResize(rules,ruleCount);
      for(int i=0;i<ruleCount;i++)
        {
         CJsonReader ruleReader;
         ruleReader.SetContent(ruleBlocks[i]);
         string triggerBlock=CStrategyProfileJsonBlockReader::ExtractObjectAfterKey(ruleBlocks[i],"trigger");
         CJsonReader triggerReader;
         triggerReader.SetContent(triggerBlock);
         CBreakEvenTrigger trigger=CBreakEvenTrigger::Create(
            CBreakEvenTriggerTypeHelper::FromString(triggerReader.ReadString("type","")),
            triggerReader.ReadDouble("realized_profit_usd",0.0),
            triggerReader.HasKey("realized_profit_usd"),
            triggerReader.ReadDouble("floating_profit_usd",0.0),
            triggerReader.HasKey("floating_profit_usd"),
            triggerReader.ReadDouble("percent_of_target_risk",0.0),
            triggerReader.HasKey("percent_of_target_risk"),
            triggerReader.ReadString("profit_level_id",""),
            triggerReader.ReadString("basket_state",""),
            triggerReader.ReadString("event_type",""),
            triggerReader.ReadString("manual_token",""));

         string actionBlocks[];
         int actionCount=CStrategyProfileJsonBlockReader::ExtractObjectArrayBlocks(ruleBlocks[i],"actions",actionBlocks);
         CBreakEvenAction actions[];
         ArrayResize(actions,actionCount);
         for(int actionIndex=0;actionIndex<actionCount;actionIndex++)
           {
            CJsonReader actionReader;
            actionReader.SetContent(actionBlocks[actionIndex]);
            actions[actionIndex]=CBreakEvenAction::Create(
               CBreakEvenActionTypeHelper::FromString(actionReader.ReadString("type","")),
               actionReader.ReadDouble("sl_offset_pips",0.0),
               actionReader.ReadDouble("buffer_pips",0.0),
               actionReader.ReadBool("include_spread",true),
               actionReader.ReadBool("enable_trailing",false));
           }

         rules[i]=CBreakEvenRule::Create(ruleReader.ReadString("rule_id",""),
                                         ruleReader.ReadBool("enabled",true),
                                         ruleReader.ReadInt("priority",10),
                                         ruleReader.ReadBool("run_once",true),
                                         trigger,
                                         actions,
                                         actionCount);
        }
      return CBreakEvenPlan::Create(rules,ruleCount);
     }

   static CRiskPlan ParseRiskPlan(const string block)
     {
      CJsonReader reader;
      reader.SetContent(block);
      double threshold=reader.ReadDouble("risk_reduction_threshold_pct",0.95);
      bool hasThreshold=reader.HasKey("risk_reduction_threshold_pct");
      double accountCap=reader.ReadDouble("account_risk_cap_pct",0.0);
      bool hasAccountCap=reader.HasKey("account_risk_cap_pct") && accountCap>0.0;
      return CRiskPlan::Create(reader.ReadDouble("target_risk_pct",1.0),
                               reader.ReadDouble("max_risk_pct",1.2),
                               threshold,
                               hasThreshold,
                               CRiskReductionModeHelper::FromString(reader.ReadString("risk_reduction_mode","WORST_ENTRY")),
                               accountCap,
                               hasAccountCap,
                               reader.ReadInt("wait_details_timeout_minutes",30),
                               reader.ReadInt("risk_eval_debounce_ms",100));
     }

   static CExecutionProfileConfig ParseExecutionPolicy(const string block)
     {
      CJsonReader reader;
      reader.SetContent(block);
      CExecutionProfileConfig policy;
      policy.SetSlippagePoints(reader.ReadInt("slippage_points",10));
      policy.SetMaxTradeRetries(reader.ReadInt("max_trade_retries",3));
      policy.SetMagicNumberBase(reader.ReadInt("magic_number_base",202606000));
      policy.SetCommandBatchSize(reader.ReadInt("command_batch_size",10));
      policy.SetTradeRequestBatchSize(reader.ReadInt("trade_request_batch_size",5));
      policy.SetRestPollIntervalMs(reader.ReadInt("rest_poll_interval_ms",3000));
      return policy;
     }
  };

#endif
