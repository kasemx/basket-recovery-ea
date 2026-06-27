#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_POSITION_RUNTIME_VIEW_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_POSITION_RUNTIME_VIEW_MQH

#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Enums/TradeRole.mqh>

class CPositionRuntimeView
  {
private:
   ulong                     m_ticket;
   double                    m_entryPrice;
   double                    m_lot;
   double                    m_floatingProfit;
   double                    m_positionRiskUsd;
   datetime                  m_openTime;
   ENUM_BRE_TRADE_DIRECTION  m_direction;
   ENUM_BRE_TRADE_ROLE       m_tradeRole;

                     CPositionRuntimeView(void) {}

public:
   ulong                     Ticket(void) const { return m_ticket; }
   double                    EntryPrice(void) const { return m_entryPrice; }
   double                    Lot(void) const { return m_lot; }
   double                    FloatingProfit(void) const { return m_floatingProfit; }
   double                    PositionRiskUsd(void) const { return m_positionRiskUsd; }
   datetime                  OpenTime(void) const { return m_openTime; }
   ENUM_BRE_TRADE_DIRECTION  Direction(void) const { return m_direction; }
   ENUM_BRE_TRADE_ROLE       TradeRole(void) const { return m_tradeRole; }

   static CPositionRuntimeView Create(const ulong ticket,
                                      const double entryPrice,
                                      const double lot,
                                      const double floatingProfit,
                                      const double positionRiskUsd,
                                      const datetime openTime,
                                      const ENUM_BRE_TRADE_DIRECTION direction,
                                      const ENUM_BRE_TRADE_ROLE tradeRole)
     {
      CPositionRuntimeView view;
      view.m_ticket=ticket;
      view.m_entryPrice=entryPrice;
      view.m_lot=lot;
      view.m_floatingProfit=floatingProfit;
      view.m_positionRiskUsd=positionRiskUsd;
      view.m_openTime=openTime;
      view.m_direction=direction;
      view.m_tradeRole=tradeRole;
      return view;
     }
  };

#endif
