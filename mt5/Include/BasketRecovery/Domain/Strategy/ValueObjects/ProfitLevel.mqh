#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_PROFIT_LEVEL_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_PROFIT_LEVEL_MQH

#include <BasketRecovery/Domain/Strategy/Enums/CloseMode.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ExecutionZoneExpansionMode.mqh>

class CProfitLevel
  {
private:
   string                      m_levelId;
   int                         m_levelIndex;
   ENUM_BRE_PROFIT_LEVEL_SOURCE m_source;
   double                      m_price;
   bool                        m_hasPrice;
   double                      m_closePercent;
   ENUM_BRE_CLOSE_MODE         m_closeMode;
   bool                        m_partialClose;
   bool                        m_enableTrailing;
   bool                        m_enabled;

public:
                     CProfitLevel(void) {}

                     CProfitLevel(const CProfitLevel &other)
     {
      m_levelId=other.m_levelId;
      m_levelIndex=other.m_levelIndex;
      m_source=other.m_source;
      m_price=other.m_price;
      m_hasPrice=other.m_hasPrice;
      m_closePercent=other.m_closePercent;
      m_closeMode=other.m_closeMode;
      m_partialClose=other.m_partialClose;
      m_enableTrailing=other.m_enableTrailing;
      m_enabled=other.m_enabled;
     }

   string                      LevelId(void) const { return m_levelId; }
   int                         LevelIndex(void) const { return m_levelIndex; }
   ENUM_BRE_PROFIT_LEVEL_SOURCE Source(void) const { return m_source; }
   bool                        HasPrice(void) const { return m_hasPrice; }
   double                      Price(void) const { return m_price; }
   double                      ClosePercent(void) const { return m_closePercent; }
   ENUM_BRE_CLOSE_MODE         CloseMode(void) const { return m_closeMode; }
   bool                        PartialClose(void) const { return m_partialClose; }
   bool                        EnableTrailing(void) const { return m_enableTrailing; }
   bool                        Enabled(void) const { return m_enabled; }

   static CProfitLevel         Create(const string levelId,
                                        const int levelIndex,
                                        const ENUM_BRE_PROFIT_LEVEL_SOURCE source,
                                        const double price,
                                        const bool hasPrice,
                                        const double closePercent,
                                        const ENUM_BRE_CLOSE_MODE closeMode,
                                        const bool partialClose,
                                        const bool enableTrailing,
                                        const bool enabled)
     {
      CProfitLevel level;
      level.m_levelId=levelId;
      level.m_levelIndex=levelIndex;
      level.m_source=source;
      level.m_price=price;
      level.m_hasPrice=hasPrice;
      level.m_closePercent=closePercent;
      level.m_closeMode=closeMode;
      level.m_partialClose=partialClose;
      level.m_enableTrailing=enableTrailing;
      level.m_enabled=enabled;
      return level;
     }
  };

#endif
