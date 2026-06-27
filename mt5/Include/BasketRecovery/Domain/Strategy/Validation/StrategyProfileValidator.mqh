#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_PROFILE_VALIDATOR_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_PROFILE_VALIDATOR_MQH

#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Shared/Constants/StrategySchema.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class CStrategyProfileValidator
  {
private:
   bool              HasProfitLevelId(const CStrategyProfile &profile,const string levelId) const
     {
      CProfitDistributionPlan plan=profile.ProfitDistributionPlan();
      for(int i=0;i<plan.LevelCount();i++)
        {
         if(plan.LevelAt(i).LevelId()==levelId)
            return true;
        }
      return false;
     }

   CVoidResult       ValidateExecutionZone(const CExecutionZone &zone) const
     {
      if(zone.Source()==BRE_EXECUTION_ZONE_SOURCE_NONE)
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Execution zone source is required");

      if(zone.Source()==BRE_EXECUTION_ZONE_SOURCE_FIXED_RANGE)
        {
         if(!zone.HasFixedRange())
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Fixed range requires low/high prices");
         if(zone.FixedRangeLow()>=zone.FixedRangeHigh())
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Fixed range low must be less than high");
        }

      if(zone.ExpansionMode()==BRE_ZONE_EXPANSION_ASYMMETRIC)
        {
         if(zone.AboveEntryPips()<0.0 || zone.BelowEntryPips()<0.0)
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Asymmetric expansion requires above and below pips");
        }

      if(zone.HasMaxRecoveryDistance() && zone.MaxRecoveryDistancePips()<=0.0)
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Max recovery distance must be positive");

      return CVoidResult::Ok();
     }

   CVoidResult       ValidateRecoveryPlan(const CRecoveryPlan &plan) const
     {
      if(plan.Algorithm()==BRE_RECOVERY_ALGORITHM_NONE)
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Recovery algorithm is required");

      if(plan.InitialPositionCount()<=0)
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Initial position count must be positive");

      if(plan.InitialLotSize()<=0.0)
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Initial lot size must be positive");

      if(plan.Algorithm()==BRE_RECOVERY_ALGORITHM_CONSTANT)
        {
         if(plan.ConstantDistancePips()<=0.0)
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Constant recovery distance must be positive");
         if(plan.ConstantLot()<=0.0)
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Constant recovery lot must be positive");
         if(plan.HasMaxSteps() && plan.MaxSteps()<=0)
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Constant recovery max steps must be positive");
         return CVoidResult::Ok();
        }

      if(plan.Algorithm()==BRE_RECOVERY_ALGORITHM_CUSTOM)
        {
         if(plan.StepCount()<=0)
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Custom recovery requires at least one step");

         int previousIndex=-1;
         double previousDistance=-1.0;
         for(int i=0;i<plan.StepCount();i++)
           {
            CRecoveryStep step=plan.StepAt(i);
            if(step.StepIndex()<=0)
               return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Recovery step index must be positive");
            if(previousIndex>=0 && step.StepIndex()<=previousIndex)
               return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Recovery step indices must be strictly increasing");
            if(step.DistancePips()<0.0)
               return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Recovery distance must be non-negative");
            if(previousDistance>=0.0 && step.DistancePips()<previousDistance)
               return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Recovery distances must be monotonic non-decreasing");
            if(step.Lot()<=0.0)
               return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Recovery lot must be positive");
            previousIndex=step.StepIndex();
            previousDistance=step.DistancePips();
           }
         return CVoidResult::Ok();
        }

      if(plan.Algorithm()==BRE_RECOVERY_ALGORITHM_ATR || plan.Algorithm()==BRE_RECOVERY_ALGORITHM_VOLATILITY)
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Recovery algorithm is not available in this sprint");

      return CVoidResult::Ok();
     }

   CVoidResult       ValidateProfitDistributionPlan(const CProfitDistributionPlan &plan) const
     {
      string seenIds[];
      int enabledCount=0;
      for(int i=0;i<plan.LevelCount();i++)
        {
         CProfitLevel level=plan.LevelAt(i);
         if(level.LevelId()=="")
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Profit level id is required");

         for(int j=0;j<ArraySize(seenIds);j++)
           {
            if(seenIds[j]==level.LevelId())
               return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Duplicate profit level id: "+level.LevelId());
           }
         int nextIndex=ArraySize(seenIds);
         ArrayResize(seenIds,nextIndex+1);
         seenIds[nextIndex]=level.LevelId();

         if(!level.Enabled())
            continue;

         enabledCount++;
         if(level.ClosePercent()<0.0 || level.ClosePercent()>100.0)
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Profit level close percent must be between 0 and 100");
         if(level.Source()==BRE_PROFIT_LEVEL_SOURCE_FIXED_PRICE && !level.HasPrice())
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Fixed price profit level requires price");
         if(level.CloseMode()==BRE_CLOSE_MODE_NONE)
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Profit level close mode is required");
        }

      if(enabledCount==0)
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"At least one enabled profit level is required");

      return CVoidResult::Ok();
     }

   CVoidResult       ValidateBreakEvenPlan(const CBreakEvenPlan &plan,const CStrategyProfile &profile) const
     {
      string seenRuleIds[];
      for(int i=0;i<plan.RuleCount();i++)
        {
         CBreakEvenRule rule=plan.RuleAt(i);
         if(rule.RuleId()=="")
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Break-even rule id is required");

         for(int j=0;j<ArraySize(seenRuleIds);j++)
           {
            if(seenRuleIds[j]==rule.RuleId())
               return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Duplicate break-even rule id: "+rule.RuleId());
           }
         int nextRuleIndex=ArraySize(seenRuleIds);
         ArrayResize(seenRuleIds,nextRuleIndex+1);
         seenRuleIds[nextRuleIndex]=rule.RuleId();

         if(!rule.Enabled())
            continue;

         if(rule.Trigger().Type()==BRE_BE_TRIGGER_NONE)
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Break-even trigger type is required");
         if(rule.ActionCount()<=0)
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Break-even rule requires at least one action");

         if(rule.Trigger().Type()==BRE_BE_TRIGGER_SPECIFIC_PROFIT_LEVEL)
           {
            if(rule.Trigger().ProfitLevelId()=="")
               return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Break-even profit level trigger requires profitLevelId");
            if(!HasProfitLevelId(profile,rule.Trigger().ProfitLevelId()))
               return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Break-even references missing profit level: "+rule.Trigger().ProfitLevelId());
           }

         for(int actionIndex=0;actionIndex<rule.ActionCount();actionIndex++)
           {
            CBreakEvenAction action=rule.ActionAt(actionIndex);
            if(action.Type()==BRE_BE_ACTION_NONE)
               return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Break-even action type is required");
           }
        }
      return CVoidResult::Ok();
     }

   CVoidResult       ValidateRiskPlan(const CRiskPlan &plan) const
     {
      if(plan.TargetRiskPct()<=0.0)
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Target risk must be positive");
      if(plan.MaxRiskPct()<plan.TargetRiskPct())
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Max risk must be greater than or equal to target risk");
      if(plan.RiskReductionMode()==BRE_RISK_REDUCTION_MODE_NONE)
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Risk reduction mode is required");
      if(plan.HasRiskReductionThreshold())
        {
         if(plan.RiskReductionThresholdPct()<0.0 || plan.RiskReductionThresholdPct()>1.0)
            return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Risk reduction threshold must be between 0 and 1");
        }
      return CVoidResult::Ok();
     }

public:
   CVoidResult       Validate(const CStrategyProfile &profile) const
     {
      if(profile.StrategyId()=="")
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Strategy id is required");

      if(profile.SchemaVersion()!=BRE_STRATEGY_SCHEMA_VERSION)
         return CVoidResult::Fail(BRE_ERR_STRATEGY_SCHEMA_UNSUPPORTED,"Unsupported strategy schema version");

      if(profile.Metadata().StrategyName()=="")
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Strategy name is required");

      CVoidResult zoneResult=ValidateExecutionZone(profile.ExecutionZone());
      if(zoneResult.IsFail())
         return zoneResult;

      CVoidResult recoveryResult=ValidateRecoveryPlan(profile.RecoveryPlan());
      if(recoveryResult.IsFail())
         return recoveryResult;

      CVoidResult profitResult=ValidateProfitDistributionPlan(profile.ProfitDistributionPlan());
      if(profitResult.IsFail())
         return profitResult;

      CVoidResult breakEvenResult=ValidateBreakEvenPlan(profile.BreakEvenPlan(),profile);
      if(breakEvenResult.IsFail())
         return breakEvenResult;

      CVoidResult riskResult=ValidateRiskPlan(profile.RiskPlan());
      if(riskResult.IsFail())
         return riskResult;

      if(profile.ExecutionPolicy().MagicNumberBase()<=0)
         return CVoidResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Execution policy magic number must be positive");

      return CVoidResult::Ok();
     }
  };

#endif
