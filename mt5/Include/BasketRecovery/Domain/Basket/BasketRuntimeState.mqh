#ifndef BASKET_RECOVERY_DOMAIN_BASKET_RUNTIME_STATE_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_RUNTIME_STATE_MQH

#include <BasketRecovery/Domain/Basket/BasketStrategyBinding.mqh>
#include <BasketRecovery/Domain/Basket/BasketProfitLevelProgress.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class CBasketRuntimeState
  {
private:
   CBasketStrategyBinding       m_strategyBinding;
   CBasketProfitLevelProgress   m_profitLevels[];
   int                          m_profitLevelCount;
   string                       m_executedBreakEvenRuleIds[];
   int                          m_executedBreakEvenRuleCount;
   bool                         m_strategyMigrationRequired;

   int               FindProfitLevelIndex(const string levelId) const
     {
      for(int i=0;i<m_profitLevelCount;i++)
        {
         if(m_profitLevels[i].LevelId()==levelId)
            return i;
        }
      return -1;
     }

public:
                     CBasketRuntimeState(void)
     {
      m_profitLevelCount=0;
      m_executedBreakEvenRuleCount=0;
      m_strategyMigrationRequired=false;
      ArrayResize(m_profitLevels,0);
      ArrayResize(m_executedBreakEvenRuleIds,0);
     }

                     CBasketRuntimeState(const CBasketRuntimeState &other)
     {
      m_strategyBinding=other.m_strategyBinding;
      m_profitLevelCount=other.m_profitLevelCount;
      m_executedBreakEvenRuleCount=other.m_executedBreakEvenRuleCount;
      m_strategyMigrationRequired=other.m_strategyMigrationRequired;
      ArrayResize(m_profitLevels,m_profitLevelCount);
      for(int i=0;i<m_profitLevelCount;i++)
         m_profitLevels[i]=other.m_profitLevels[i];
      ArrayResize(m_executedBreakEvenRuleIds,m_executedBreakEvenRuleCount);
      for(int i=0;i<m_executedBreakEvenRuleCount;i++)
         m_executedBreakEvenRuleIds[i]=other.m_executedBreakEvenRuleIds[i];
     }

   bool              HasStrategyProfile(void) const { return m_strategyBinding.IsBound(); }
   bool              StrategyMigrationRequired(void) const { return m_strategyMigrationRequired; }
   CBasketStrategyBinding StrategyBinding(void) const { return m_strategyBinding; }
   int               ProfitLevelCount(void) const { return m_profitLevelCount; }

   bool              ProfitLevelAt(const int index,CBasketProfitLevelProgress &outProgress) const
     {
      if(index<0 || index>=m_profitLevelCount)
         return false;
      outProgress=m_profitLevels[index];
      return true;
     }

   bool              FindProfitLevel(const string levelId,CBasketProfitLevelProgress &outProgress) const
     {
      int index=FindProfitLevelIndex(levelId);
      if(index<0)
         return false;
      outProgress=m_profitLevels[index];
      return true;
     }

   bool              HasExecutedBreakEvenRule(const string ruleId) const
     {
      for(int i=0;i<m_executedBreakEvenRuleCount;i++)
        {
         if(m_executedBreakEvenRuleIds[i]==ruleId)
            return true;
        }
      return false;
     }

   void              SetStrategyMigrationRequired(const bool value) { m_strategyMigrationRequired=value; }

   CVoidResult       BindStrategyProfile(const CStrategyProfileSnapshot &snapshot)
     {
      return m_strategyBinding.Bind(snapshot);
     }

   void              RestoreStrategyBinding(const CStrategyProfileSnapshot &snapshot,
                                              const bool migrationRequired)
     {
      m_strategyBinding.Restore(snapshot);
      m_strategyMigrationRequired=migrationRequired;
     }

   void              RestoreProfitLevels(const CBasketProfitLevelProgress &levels[],const int count)
     {
      m_profitLevelCount=count;
      ArrayResize(m_profitLevels,count);
      for(int i=0;i<count;i++)
         m_profitLevels[i]=levels[i];
     }

   void              RestoreExecutedBreakEvenRules(const string ruleIds[],const int count)
     {
      m_executedBreakEvenRuleCount=count;
      ArrayResize(m_executedBreakEvenRuleIds,count);
      for(int i=0;i<count;i++)
         m_executedBreakEvenRuleIds[i]=ruleIds[i];
     }

   CVoidResult       MarkProfitLevelReached(const string levelId,
                                            const CUtcTime reachedAtUtc,
                                            const CCommandId &commandId,
                                            const CEventId &eventId)
     {
      int index=FindProfitLevelIndex(levelId);
      if(index>=0 && m_profitLevels[index].Reached())
         return CVoidResult::Fail(BRE_ERR_PROFIT_LEVEL_ALREADY_REACHED,"Profit level already reached");

      CBasketProfitLevelProgress progress=CBasketProfitLevelProgress::CreateReached(levelId,reachedAtUtc,commandId,eventId);
      if(index>=0)
         m_profitLevels[index]=progress;
      else
        {
         ArrayResize(m_profitLevels,m_profitLevelCount+1);
         m_profitLevels[m_profitLevelCount]=progress;
         m_profitLevelCount++;
        }
      return CVoidResult::Ok();
     }

   CVoidResult       MarkBreakEvenRuleExecuted(const string ruleId)
     {
      if(HasExecutedBreakEvenRule(ruleId))
         return CVoidResult::Fail(BRE_ERR_BREAK_EVEN_ALREADY_EXECUTED,"Break-even rule already executed");
      ArrayResize(m_executedBreakEvenRuleIds,m_executedBreakEvenRuleCount+1);
      m_executedBreakEvenRuleIds[m_executedBreakEvenRuleCount]=ruleId;
      m_executedBreakEvenRuleCount++;
      return CVoidResult::Ok();
     }

   void              CopyProfitLevelsTo(CBasketProfitLevelProgress &outLevels[],int &outCount) const
     {
      outCount=m_profitLevelCount;
      ArrayResize(outLevels,outCount);
      for(int i=0;i<outCount;i++)
         outLevels[i]=m_profitLevels[i];
     }

   void              CopyExecutedBreakEvenRulesTo(string &outRuleIds[],int &outCount) const
     {
      outCount=m_executedBreakEvenRuleCount;
      ArrayResize(outRuleIds,outCount);
      for(int i=0;i<outCount;i++)
         outRuleIds[i]=m_executedBreakEvenRuleIds[i];
     }
  };

#endif
