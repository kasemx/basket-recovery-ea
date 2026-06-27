#ifndef BASKET_RECOVERY_INFRASTRUCTURE_STRATEGY_PROFILE_MIGRATOR_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_STRATEGY_PROFILE_MIGRATOR_MQH

#include <BasketRecovery/Domain/Configuration/ProfileBundle.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Domain/Strategy/Validation/StrategyProfileValidator.mqh>
#include <BasketRecovery/Shared/Constants/StrategySchema.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CStrategyProfileMigrator
  {
private:
   void              FillLinearRecoverySteps(const CRecoveryProfileConfig &recovery,CRecoveryStep &outSteps[],int &outCount) const
     {
      outCount=recovery.MaxRecoverySteps();
      if(outCount<=0)
         outCount=50;
      if(outCount>100)
         outCount=100;
      ArrayResize(outSteps,outCount);
      for(int i=0;i<outCount;i++)
        {
         double distance=recovery.RecoveryStepPips()*(i+1);
         outSteps[i]=CRecoveryStep::Create(i+1,distance,recovery.RecoveryLotSize());
        }
     }

public:
   CResult<CStrategyProfile> MigrateFromBundle(const CProfileBundle &bundle) const
     {
      if(bundle.ProfileName()=="")
         return CResult<CStrategyProfile>::Fail(BRE_ERR_STRATEGY_MIGRATION_FAILED,"Profile bundle name is empty");

      string strategyId=bundle.ProfileName();
      if(strategyId=="default")
         strategyId=BRE_STRATEGY_DEFAULT_ID;

      CExecutionZone executionZone=CExecutionZone::CreateSignalRange(BRE_ZONE_EXPANSION_SYMMETRIC,
                                                                   3.0,
                                                                   3.0,
                                                                   false,
                                                                   0.0,
                                                                   false);

      CRecoveryStep recoverySteps[];
      int recoveryStepCount=0;
      FillLinearRecoverySteps(bundle.Recovery(),recoverySteps,recoveryStepCount);
      CRecoveryPlan recoveryPlan=CRecoveryPlan::CreateCustom(recoverySteps,
                                                             recoveryStepCount,
                                                             true,
                                                             true,
                                                             bundle.Recovery().InitialPositionCount(),
                                                             bundle.Recovery().InitialLotSize());

      CProfitLevel profitLevels[3];
      profitLevels[0]=CProfitLevel::Create("L1",1,BRE_PROFIT_LEVEL_SOURCE_SIGNAL_TP,0.0,false,
                                           bundle.TakeProfit().Tp1RealizeFraction()*100.0,
                                           BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true);
      profitLevels[1]=CProfitLevel::Create("L2",2,BRE_PROFIT_LEVEL_SOURCE_SIGNAL_TP,0.0,false,
                                           bundle.TakeProfit().Tp2RealizeFraction()*100.0,
                                           BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true);
      profitLevels[2]=CProfitLevel::Create("L3",3,BRE_PROFIT_LEVEL_SOURCE_SIGNAL_TP,0.0,false,
                                           100.0,
                                           BRE_CLOSE_MODE_WORST_ENTRY_FIRST,false,false,true);
      CProfitDistributionPlan profitPlan=CProfitDistributionPlan::Create(bundle.TakeProfit().RequireFloatingProfitPositive(),
                                                                        BRE_CLOSE_MODE_WORST_ENTRY_FIRST,
                                                                        profitLevels,
                                                                        3);

      CBreakEvenTrigger beTrigger=CBreakEvenTrigger::Create(BRE_BE_TRIGGER_SPECIFIC_PROFIT_LEVEL,
                                                            0.0,false,0.0,false,0.0,false,
                                                            "L1","","","");
      CBreakEvenAction beActions[2];
      beActions[0]=CBreakEvenAction::Create(BRE_BE_ACTION_MOVE_SL_TO_AVERAGE,
                                            0.0,
                                            bundle.BreakEven().SafetyBufferPips(),
                                            bundle.BreakEven().IncludeSpread(),
                                            false);
      beActions[1]=CBreakEvenAction::Create(BRE_BE_ACTION_DISABLE_RECOVERY,0.0,0.0,false,false);
      CBreakEvenRule beRules[1];
      beRules[0]=CBreakEvenRule::Create("BE_AFTER_L1",true,10,true,beTrigger,beActions,2);
      CBreakEvenPlan breakEvenPlan=CBreakEvenPlan::Create(beRules,1);

      CRiskPlan riskPlan=CRiskPlan::Create(bundle.Risk().TargetRiskPct(),
                                           bundle.Risk().MaxRiskPct(),
                                           bundle.Risk().MaxRiskReleaseThreshold(),
                                           true,
                                           BRE_RISK_REDUCTION_MODE_WORST_ENTRY,
                                           0.0,
                                           false,
                                           bundle.Risk().WaitDetailsTimeoutMinutes(),
                                           bundle.Risk().RiskEvalDebounceMs());

      CExecutionProfileConfig executionPolicy=bundle.Execution();
      CStrategyMetadata metadata=CStrategyMetadata::Create("Legacy "+bundle.ProfileName(),
                                                           "Migrated from v1 profile bundle",
                                                           "StrategyProfileMigrator");

      CStrategyProfile profile=CStrategyProfile::Create(strategyId,
                                                        BRE_STRATEGY_SCHEMA_VERSION,
                                                        metadata,
                                                        executionZone,
                                                        recoveryPlan,
                                                        profitPlan,
                                                        breakEvenPlan,
                                                        riskPlan,
                                                        executionPolicy,
                                                        bundle.BoundAt());

      CStrategyProfileValidator validator;
      CVoidResult validation=validator.Validate(profile);
      if(validation.IsFail())
         return CResult<CStrategyProfile>::Fail(BRE_ERR_STRATEGY_MIGRATION_FAILED,validation.ErrorMessage());

      return CResult<CStrategyProfile>::Ok(profile);
     }
  };

#endif
