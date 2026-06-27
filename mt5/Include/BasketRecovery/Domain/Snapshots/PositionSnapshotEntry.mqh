#ifndef BRE_DOMAIN_POSITION_SNAPSHOT_ENTRY_MQH
#define BRE_DOMAIN_POSITION_SNAPSHOT_ENTRY_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Enums/TradeRole.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotStatus.mqh>

class CPositionSnapshotEntry
  {
private:
   CBasketId                     m_basketId;
   ulong                         m_ticket;
   long                          m_magic;
   string                        m_symbol;
   ENUM_BRE_TRADE_DIRECTION      m_direction;
   ENUM_BRE_TRADE_ROLE           m_role;
   int                           m_recoveryStepIndex;
   double                        m_entryPrice;
   double                        m_currentPrice;
   double                        m_stopLoss;
   double                        m_takeProfit;
   double                        m_volume;
   double                        m_floatingProfit;
   double                        m_commission;
   double                        m_swap;
   datetime                      m_openTimeUtc;
   ENUM_BRE_POSITION_SNAPSHOT_STATUS m_status;
   string                        m_correlationId;

public:
                     CPositionSnapshotEntry(void)
     {
      m_ticket=0;
      m_magic=0;
      m_direction=BRE_DIRECTION_NONE;
      m_role=BRE_TRADE_ROLE_INITIAL;
      m_recoveryStepIndex=0;
      m_entryPrice=0.0;
      m_currentPrice=0.0;
      m_stopLoss=0.0;
      m_takeProfit=0.0;
      m_volume=0.0;
      m_floatingProfit=0.0;
      m_commission=0.0;
      m_swap=0.0;
      m_openTimeUtc=0;
      m_status=BRE_POSITION_SNAPSHOT_OPEN;
     }

                     CPositionSnapshotEntry(const CPositionSnapshotEntry &other)
     {
      m_basketId=other.m_basketId;
      m_ticket=other.m_ticket;
      m_magic=other.m_magic;
      m_symbol=other.m_symbol;
      m_direction=other.m_direction;
      m_role=other.m_role;
      m_recoveryStepIndex=other.m_recoveryStepIndex;
      m_entryPrice=other.m_entryPrice;
      m_currentPrice=other.m_currentPrice;
      m_stopLoss=other.m_stopLoss;
      m_takeProfit=other.m_takeProfit;
      m_volume=other.m_volume;
      m_floatingProfit=other.m_floatingProfit;
      m_commission=other.m_commission;
      m_swap=other.m_swap;
      m_openTimeUtc=other.m_openTimeUtc;
      m_status=other.m_status;
      m_correlationId=other.m_correlationId;
     }

   CBasketId                     BasketId(void) const { return m_basketId; }
   ulong                         Ticket(void) const { return m_ticket; }
   long                          Magic(void) const { return m_magic; }
   string                        Symbol(void) const { return m_symbol; }
   ENUM_BRE_TRADE_DIRECTION      Direction(void) const { return m_direction; }
   ENUM_BRE_TRADE_ROLE           Role(void) const { return m_role; }
   int                           RecoveryStepIndex(void) const { return m_recoveryStepIndex; }
   double                        EntryPrice(void) const { return m_entryPrice; }
   double                        CurrentPrice(void) const { return m_currentPrice; }
   double                        StopLoss(void) const { return m_stopLoss; }
   double                        TakeProfit(void) const { return m_takeProfit; }
   double                        Volume(void) const { return m_volume; }
   double                        FloatingProfit(void) const { return m_floatingProfit; }
   double                        Commission(void) const { return m_commission; }
   double                        Swap(void) const { return m_swap; }
   datetime                      OpenTimeUtc(void) const { return m_openTimeUtc; }
   ENUM_BRE_POSITION_SNAPSHOT_STATUS Status(void) const { return m_status; }
   string                        CorrelationId(void) const { return m_correlationId; }

   static CPositionSnapshotEntry Create(const CBasketId &basketId,
                                        const ulong ticket,
                                        const long magic,
                                        const string symbol,
                                        const ENUM_BRE_TRADE_DIRECTION direction,
                                        const ENUM_BRE_TRADE_ROLE role,
                                        const int recoveryStepIndex,
                                        const double entryPrice,
                                        const double currentPrice,
                                        const double stopLoss,
                                        const double takeProfit,
                                        const double volume,
                                        const double floatingProfit,
                                        const double commission,
                                        const double swap,
                                        const datetime openTimeUtc,
                                        const ENUM_BRE_POSITION_SNAPSHOT_STATUS status,
                                        const string correlationId)
     {
      CPositionSnapshotEntry entry;
      entry.m_basketId=basketId;
      entry.m_ticket=ticket;
      entry.m_magic=magic;
      entry.m_symbol=symbol;
      entry.m_direction=direction;
      entry.m_role=role;
      entry.m_recoveryStepIndex=recoveryStepIndex;
      entry.m_entryPrice=entryPrice;
      entry.m_currentPrice=currentPrice;
      entry.m_stopLoss=stopLoss;
      entry.m_takeProfit=takeProfit;
      entry.m_volume=volume;
      entry.m_floatingProfit=floatingProfit;
      entry.m_commission=commission;
      entry.m_swap=swap;
      entry.m_openTimeUtc=openTimeUtc;
      entry.m_status=status;
      entry.m_correlationId=correlationId;
      return entry;
     }
  };

#endif
