#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_PROFIT_DISTRIBUTION_PLAN_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_PROFIT_DISTRIBUTION_PLAN_MQH

#include <BasketRecovery/Domain/Strategy/Enums/CloseMode.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevel.mqh>

class CProfitDistributionPlan
  {
private:
   bool           m_requireFloatingProfitPositive;
   ENUM_BRE_CLOSE_MODE m_defaultCloseMode;
   CProfitLevel   m_levels[];

public:
                     CProfitDistributionPlan(void) {}

                     CProfitDistributionPlan(const CProfitDistributionPlan &other)
     {
      m_requireFloatingProfitPositive=other.m_requireFloatingProfitPositive;
      m_defaultCloseMode=other.m_defaultCloseMode;
      int levelCount=ArraySize(other.m_levels);
      ArrayResize(m_levels,levelCount);
      for(int i=0;i<levelCount;i++)
         m_levels[i]=other.m_levels[i];
     }

   bool           RequireFloatingProfitPositive(void) const { return m_requireFloatingProfitPositive; }
   ENUM_BRE_CLOSE_MODE DefaultCloseMode(void) const { return m_defaultCloseMode; }
   int            LevelCount(void) const { return ArraySize(m_levels); }

   CProfitLevel   LevelAt(const int index) const
     {
      if(index<0 || index>=ArraySize(m_levels))
         return CProfitLevel::Create("",0,BRE_PROFIT_LEVEL_SOURCE_NONE,0.0,false,0.0,BRE_CLOSE_MODE_NONE,false,false,false);
      return m_levels[index];
     }

   void           CopyLevelsTo(CProfitLevel &outLevels[]) const
     {
      int count=ArraySize(m_levels);
      ArrayResize(outLevels,count);
      for(int i=0;i<count;i++)
         outLevels[i]=m_levels[i];
     }

   static CProfitDistributionPlan Create(const bool requireFloatingProfitPositive,
                                         const ENUM_BRE_CLOSE_MODE defaultCloseMode,
                                         const CProfitLevel &levels[],
                                         const int levelCount)
     {
      CProfitDistributionPlan plan;
      plan.m_requireFloatingProfitPositive=requireFloatingProfitPositive;
      plan.m_defaultCloseMode=defaultCloseMode;
      ArrayResize(plan.m_levels,levelCount);
      for(int i=0;i<levelCount;i++)
         plan.m_levels[i]=levels[i];
      return plan;
     }
  };

#endif
