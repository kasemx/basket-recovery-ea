#ifndef BRE_DOMAIN_POSITION_RISK_SNAPSHOT_MQH
#define BRE_DOMAIN_POSITION_RISK_SNAPSHOT_MQH

#include <BasketRecovery/Domain/Risk/Enums/RiskSafetyStatus.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CPositionRiskSnapshot
  {
private:
   ulong                         m_ticket;
   string                        m_symbol;
   ENUM_BRE_TRADE_DIRECTION      m_direction;
   double                        m_entryPrice;
   double                        m_volume;
   double                        m_effectiveStopLoss;
   double                        m_commission;
   double                        m_swap;
   double                        m_floatingProfit;
   double                        m_worstCaseLossAtSl;
   ENUM_BRE_RISK_SAFETY_STATUS   m_safetyStatus;

public:
                     CPositionRiskSnapshot(void)
     {
      m_ticket=0;
      m_direction=BRE_DIRECTION_NONE;
      m_entryPrice=0.0;
      m_volume=0.0;
      m_effectiveStopLoss=0.0;
      m_commission=0.0;
      m_swap=0.0;
      m_floatingProfit=0.0;
      m_worstCaseLossAtSl=0.0;
      m_safetyStatus=BRE_RISK_SAFETY_UNKNOWN;
     }

   ulong             Ticket(void) const { return m_ticket; }
   string            Symbol(void) const { return m_symbol; }
   ENUM_BRE_TRADE_DIRECTION Direction(void) const { return m_direction; }
   double            EntryPrice(void) const { return m_entryPrice; }
   double            Volume(void) const { return m_volume; }
   double            EffectiveStopLoss(void) const { return m_effectiveStopLoss; }
   double            Commission(void) const { return m_commission; }
   double            Swap(void) const { return m_swap; }
   double            FloatingProfit(void) const { return m_floatingProfit; }
   double            WorstCaseLossAtSl(void) const { return m_worstCaseLossAtSl; }
   ENUM_BRE_RISK_SAFETY_STATUS SafetyStatus(void) const { return m_safetyStatus; }
   bool              IsSafe(void) const { return m_safetyStatus==BRE_RISK_SAFETY_SAFE; }

   static CPositionRiskSnapshot Create(const ulong ticket,
                                       const string symbol,
                                       const ENUM_BRE_TRADE_DIRECTION direction,
                                       const double entryPrice,
                                       const double volume,
                                       const double effectiveStopLoss,
                                       const double commission,
                                       const double swap,
                                       const double floatingProfit,
                                       const double worstCaseLossAtSl,
                                       const ENUM_BRE_RISK_SAFETY_STATUS safetyStatus)
     {
      CPositionRiskSnapshot snapshot;
      snapshot.m_ticket=ticket;
      snapshot.m_symbol=symbol;
      snapshot.m_direction=direction;
      snapshot.m_entryPrice=entryPrice;
      snapshot.m_volume=volume;
      snapshot.m_effectiveStopLoss=effectiveStopLoss;
      snapshot.m_commission=commission;
      snapshot.m_swap=swap;
      snapshot.m_floatingProfit=floatingProfit;
      snapshot.m_worstCaseLossAtSl=worstCaseLossAtSl;
      snapshot.m_safetyStatus=safetyStatus;
      return snapshot;
     }

   static CPositionRiskSnapshot Unknown(const ulong ticket,const string symbol)
     {
      return Create(ticket,symbol,BRE_DIRECTION_NONE,0.0,0.0,0.0,0.0,0.0,0.0,0.0,BRE_RISK_SAFETY_UNKNOWN);
     }
  };

#endif
