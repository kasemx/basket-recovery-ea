#ifndef BRE_DOMAIN_BREAK_EVEN_STOP_PRICE_VALIDATOR_MQH
#define BRE_DOMAIN_BREAK_EVEN_STOP_PRICE_VALIDATOR_MQH

#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/BreakEvenReason.mqh>

class CBreakEvenStopPriceValidation
  {
private:
   bool                       m_valid;
   ENUM_BRE_BREAK_EVEN_REASON m_reason;

public:
                     CBreakEvenStopPriceValidation(void)
     {
      m_valid=false;
      m_reason=BRE_BREAK_EVEN_REASON_NONE;
     }

   bool              Valid(void) const { return m_valid; }
   ENUM_BRE_BREAK_EVEN_REASON Reason(void) const { return m_reason; }

   static CBreakEvenStopPriceValidation Ok(void)
     {
      CBreakEvenStopPriceValidation result;
      result.m_valid=true;
      result.m_reason=BRE_BREAK_EVEN_REASON_NONE;
      return result;
     }

   static CBreakEvenStopPriceValidation Fail(const ENUM_BRE_BREAK_EVEN_REASON reason)
     {
      CBreakEvenStopPriceValidation result;
      result.m_valid=false;
      result.m_reason=reason;
      return result;
     }
  };

class CBreakEvenStopPriceValidator
  {
public:
   static CBreakEvenStopPriceValidation Validate(const ENUM_BRE_TRADE_DIRECTION direction,
                                                 const double executablePrice,
                                                 const double proposedStopLoss,
                                                 const double point,
                                                 const CSymbolTradingConstraints &constraints)
     {
      if(proposedStopLoss<=0.0 || executablePrice<=0.0 || point<=0.0)
         return CBreakEvenStopPriceValidation::Fail(BRE_BREAK_EVEN_REASON_STOP_LEVEL_VIOLATION);

      int stopsLevel=constraints.StopsLevel();
      int freezeLevel=constraints.FreezeLevel();
      double minStopDistance=stopsLevel>0 ? stopsLevel*point : 0.0;
      double minFreezeDistance=freezeLevel>0 ? freezeLevel*point : 0.0;

      if(direction==BRE_DIRECTION_BUY)
        {
         if(proposedStopLoss>=executablePrice)
            return CBreakEvenStopPriceValidation::Fail(BRE_BREAK_EVEN_REASON_STOP_LEVEL_VIOLATION);
         if(minStopDistance>0.0 && (executablePrice-proposedStopLoss)<minStopDistance)
            return CBreakEvenStopPriceValidation::Fail(BRE_BREAK_EVEN_REASON_STOP_LEVEL_VIOLATION);
         if(minFreezeDistance>0.0 && (executablePrice-proposedStopLoss)<minFreezeDistance)
            return CBreakEvenStopPriceValidation::Fail(BRE_BREAK_EVEN_REASON_FREEZE_LEVEL_VIOLATION);
        }
      else if(direction==BRE_DIRECTION_SELL)
        {
         if(proposedStopLoss<=executablePrice)
            return CBreakEvenStopPriceValidation::Fail(BRE_BREAK_EVEN_REASON_STOP_LEVEL_VIOLATION);
         if(minStopDistance>0.0 && (proposedStopLoss-executablePrice)<minStopDistance)
            return CBreakEvenStopPriceValidation::Fail(BRE_BREAK_EVEN_REASON_STOP_LEVEL_VIOLATION);
         if(minFreezeDistance>0.0 && (proposedStopLoss-executablePrice)<minFreezeDistance)
            return CBreakEvenStopPriceValidation::Fail(BRE_BREAK_EVEN_REASON_FREEZE_LEVEL_VIOLATION);
        }
      else
         return CBreakEvenStopPriceValidation::Fail(BRE_BREAK_EVEN_REASON_STOP_LEVEL_VIOLATION);

      return CBreakEvenStopPriceValidation::Ok();
     }
  };

#endif
