#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_BREAK_EVEN_ACTION_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_BREAK_EVEN_ACTION_MQH

#include <BasketRecovery/Domain/Strategy/Enums/BreakEvenActionType.mqh>

class CBreakEvenAction
  {
private:
   ENUM_BRE_BREAK_EVEN_ACTION_TYPE m_type;
   double                          m_slOffsetPips;
   double                          m_bufferPips;
   bool                            m_includeSpread;
   bool                            m_enableTrailing;

                     CBreakEvenAction(void) {}

public:
   ENUM_BRE_BREAK_EVEN_ACTION_TYPE Type(void) const { return m_type; }
   double                          SlOffsetPips(void) const { return m_slOffsetPips; }
   double                          BufferPips(void) const { return m_bufferPips; }
   bool                            IncludeSpread(void) const { return m_includeSpread; }
   bool                            EnableTrailing(void) const { return m_enableTrailing; }

   static CBreakEvenAction         Create(const ENUM_BRE_BREAK_EVEN_ACTION_TYPE type,
                                          const double slOffsetPips,
                                          const double bufferPips,
                                          const bool includeSpread,
                                          const bool enableTrailing)
     {
      CBreakEvenAction action;
      action.m_type=type;
      action.m_slOffsetPips=slOffsetPips;
      action.m_bufferPips=bufferPips;
      action.m_includeSpread=includeSpread;
      action.m_enableTrailing=enableTrailing;
      return action;
     }
  };

#endif
