#ifndef BASKET_RECOVERY_INFRASTRUCTURE_STRATEGY_PROFILE_JSON_PARSER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_STRATEGY_PROFILE_JSON_PARSER_MQH

#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonBlockReader.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonSections.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Domain/Strategy/Validation/StrategyProfileValidator.mqh>
#include <BasketRecovery/Shared/Constants/StrategySchema.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CStrategyProfileJsonParser
  {
public:
   CResult<CStrategyProfile> Parse(const string content,const CUtcTime &boundAt) const
     {
      if(content=="")
         return CResult<CStrategyProfile>::Fail(BRE_ERR_STRATEGY_SCHEMA_INVALID,"Strategy JSON content is empty");

      CJsonReader reader;
      reader.SetContent(content);
      int schemaVersion=reader.ReadInt("schema_version",0);
      if(schemaVersion!=BRE_STRATEGY_SCHEMA_VERSION)
         return CResult<CStrategyProfile>::Fail(BRE_ERR_STRATEGY_SCHEMA_UNSUPPORTED,"Unsupported strategy schema version");

      string strategyId=reader.ReadString("strategy_id","");
      if(strategyId=="")
         return CResult<CStrategyProfile>::Fail(BRE_ERR_STRATEGY_SCHEMA_INVALID,"strategy_id is required");

      string metadataBlock=CStrategyProfileJsonBlockReader::ExtractObjectAfterKey(content,"metadata");
      if(metadataBlock=="")
         return CResult<CStrategyProfile>::Fail(BRE_ERR_STRATEGY_SCHEMA_INVALID,"metadata is required");

      CJsonReader metadataReader;
      metadataReader.SetContent(metadataBlock);
      string strategyName=metadataReader.ReadString("strategy_name","");
      if(strategyName=="")
         strategyName=reader.ReadString("strategy_name",strategyId);

      CStrategyMetadata metadata=CStrategyMetadata::Create(strategyName,
                                                         metadataReader.ReadString("description",""),
                                                         metadataReader.ReadString("author",""));

      string executionZoneBlock=CStrategyProfileJsonBlockReader::ExtractObjectAfterKey(content,"execution_zone");
      string recoveryPlanBlock=CStrategyProfileJsonBlockReader::ExtractObjectAfterKey(content,"recovery_plan");
      string profitPlanBlock=CStrategyProfileJsonBlockReader::ExtractObjectAfterKey(content,"profit_distribution_plan");
      string breakEvenBlock=CStrategyProfileJsonBlockReader::ExtractObjectAfterKey(content,"break_even_plan");
      string riskPlanBlock=CStrategyProfileJsonBlockReader::ExtractObjectAfterKey(content,"risk_plan");
      string executionPolicyBlock=CStrategyProfileJsonBlockReader::ExtractObjectAfterKey(content,"execution_policy");

      if(executionZoneBlock=="" || recoveryPlanBlock=="" || profitPlanBlock=="" ||
         breakEvenBlock=="" || riskPlanBlock=="" || executionPolicyBlock=="")
         return CResult<CStrategyProfile>::Fail(BRE_ERR_STRATEGY_SCHEMA_INVALID,"Strategy profile is missing required sections");

      CStrategyProfile profile=CStrategyProfile::Create(strategyId,
                                                        schemaVersion,
                                                        metadata,
                                                        CStrategyProfileJsonSections::ParseExecutionZone(executionZoneBlock),
                                                        CStrategyProfileJsonSections::ParseRecoveryPlan(recoveryPlanBlock),
                                                        CStrategyProfileJsonSections::ParseProfitDistributionPlan(profitPlanBlock),
                                                        CStrategyProfileJsonSections::ParseBreakEvenPlan(breakEvenBlock),
                                                        CStrategyProfileJsonSections::ParseRiskPlan(riskPlanBlock),
                                                        CStrategyProfileJsonSections::ParseExecutionPolicy(executionPolicyBlock),
                                                        boundAt);

      CStrategyProfileValidator validator;
      CVoidResult validation=validator.Validate(profile);
      if(validation.IsFail())
         return CResult<CStrategyProfile>::Fail(validation.ErrorCode(),validation.ErrorMessage());

      return CResult<CStrategyProfile>::Ok(profile);
     }
  };

#endif
