#ifndef BASKET_RECOVERY_DOMAIN_POSITION_ENTRY_MQH
#define BASKET_RECOVERY_DOMAIN_POSITION_ENTRY_MQH

#include <BasketRecovery/Shared/Types/Price.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CPositionEntry
  {
private:
   ulong                     m_ticket;
   string                    m_symbol;
   ENUM_BRE_TRADE_DIRECTION  m_direction;
   CPrice                    m_entryPrice;
   double                    m_lot;
   CPrice                    m_stopLoss;
   CPrice                    m_takeProfit;
   double                    m_floatingProfit;
   datetime                  m_openTime;
   bool                      m_isClosed;

public:
                     CPositionEntry(void)
     {
      m_ticket=0;
      m_symbol="";
      m_direction=BRE_DIRECTION_NONE;
      m_lot=0.0;
      m_floatingProfit=0.0;
      m_openTime=0;
      m_isClosed=false;
     }

   ulong                     Ticket(void) const { return m_ticket; }
   string                    Symbol(void) const { return m_symbol; }
   ENUM_BRE_TRADE_DIRECTION  Direction(void) const { return m_direction; }
   CPrice                    EntryPrice(void) const { return m_entryPrice; }
   double                    Lot(void) const { return m_lot; }
   CPrice                    StopLoss(void) const { return m_stopLoss; }
   CPrice                    TakeProfit(void) const { return m_takeProfit; }
   double                    FloatingProfit(void) const { return m_floatingProfit; }
   datetime                  OpenTime(void) const { return m_openTime; }
   bool                      IsClosed(void) const { return m_isClosed; }

   void                      SetTicket(const ulong value) { m_ticket=value; }
   void                      SetSymbol(const string value) { m_symbol=value; }
   void                      SetDirection(const ENUM_BRE_TRADE_DIRECTION value) { m_direction=value; }
   void                      SetEntryPrice(const CPrice &value) { m_entryPrice=value; }
   void                      SetLot(const double value) { m_lot=value; }
   void                      SetStopLoss(const CPrice &value) { m_stopLoss=value; }
   void                      SetTakeProfit(const CPrice &value) { m_takeProfit=value; }
   void                      SetFloatingProfit(const double value) { m_floatingProfit=value; }
   void                      SetOpenTime(const datetime value) { m_openTime=value; }
   void                      SetIsClosed(const bool value) { m_isClosed=value; }
  };

#endif
