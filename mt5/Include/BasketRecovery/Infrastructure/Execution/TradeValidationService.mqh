#ifndef BASKET_RECOVERY_INFRASTRUCTURE_TRADE_VALIDATION_SERVICE_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_TRADE_VALIDATION_SERVICE_MQH

#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CTradeValidationService
  {
private:
   double NormalizeVolume(const string symbol,const double volume) const
     {
      double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      double lotStep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      if(lotStep<=0.0)
         return volume;
      double steps=MathFloor(volume/lotStep);
      return steps*lotStep;
     }

public:
   CVoidResult       ValidateSymbolSelected(const string symbol) const
     {
      if(symbol=="")
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Symbol is empty");
      if(!SymbolInfoInteger(symbol,SYMBOL_SELECT))
        {
         if(!SymbolSelect(symbol,true))
            return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Symbol could not be selected");
        }
      return CVoidResult::Ok();
     }

   CVoidResult       ValidateVolume(const string symbol,const double volume) const
     {
      if(volume<=0.0)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Volume must be positive");

      double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      double maxLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      double lotStep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);

      if(volume<minLot)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Volume below minimum lot");
      if(volume>maxLot)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Volume above maximum lot");
      if(lotStep>0.0)
        {
         double normalized=NormalizeVolume(symbol,volume);
         if(MathAbs(normalized-volume)>lotStep/2.0)
            return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Volume does not match lot step");
        }
      return CVoidResult::Ok();
     }

   CVoidResult       ValidateStopsLevel(const string symbol,const double price,const double stopLoss,const double takeProfit) const
     {
      int stopsLevel=(int)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      if(point<=0.0)
         return CVoidResult::Ok();

      double minDistance=stopsLevel*point;
      if(stopLoss>0.0 && MathAbs(price-stopLoss)<minDistance)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Stop loss violates stops level");
      if(takeProfit>0.0 && MathAbs(price-takeProfit)<minDistance)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Take profit violates stops level");
      return CVoidResult::Ok();
     }

   CVoidResult       ValidateFreezeLevel(const string symbol,const double price,const double stopLoss,const double takeProfit) const
     {
      int freezeLevel=(int)SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL);
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      if(point<=0.0 || freezeLevel<=0)
         return CVoidResult::Ok();

      double minDistance=freezeLevel*point;
      double bid=SymbolInfoDouble(symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
      if(stopLoss>0.0 && (MathAbs(bid-stopLoss)<minDistance || MathAbs(ask-stopLoss)<minDistance))
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Stop loss violates freeze level");
      if(takeProfit>0.0 && (MathAbs(bid-takeProfit)<minDistance || MathAbs(ask-takeProfit)<minDistance))
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Take profit violates freeze level");
      return CVoidResult::Ok();
     }

   CVoidResult       ValidateTradingHours(const string symbol) const
     {
      datetime now=TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(now,dt);
      ENUM_SYMBOL_TRADE_MODE tradeMode=(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
      if(tradeMode==SYMBOL_TRADE_MODE_DISABLED)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Symbol trading is disabled");
      return CVoidResult::Ok();
     }

   CVoidResult       ValidateMarketOpen(const string symbol) const
     {
      double bid=SymbolInfoDouble(symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
      if(bid<=0.0 || ask<=0.0)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Market is not open or quotes unavailable");
      return CVoidResult::Ok();
     }

   CVoidResult       ValidateMargin(const string symbol,
                                    const ENUM_ORDER_TYPE orderType,
                                    const double volume,
                                    const double price) const
     {
      double requiredMargin=0.0;
      if(!OrderCalcMargin(orderType,symbol,volume,price,requiredMargin))
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Margin calculation failed");

      double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(requiredMargin>freeMargin)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Insufficient margin");
      return CVoidResult::Ok();
     }

   CVoidResult       ValidateOpenRequest(const string symbol,
                                         const ENUM_BRE_TRADE_DIRECTION direction,
                                         const double volume,
                                         const double stopLoss,
                                         const double takeProfit) const
     {
      CVoidResult symbolResult=ValidateSymbolSelected(symbol);
      if(symbolResult.IsFail())
         return symbolResult;

      CVoidResult volumeResult=ValidateVolume(symbol,volume);
      if(volumeResult.IsFail())
         return volumeResult;

      CVoidResult hoursResult=ValidateTradingHours(symbol);
      if(hoursResult.IsFail())
         return hoursResult;

      CVoidResult marketResult=ValidateMarketOpen(symbol);
      if(marketResult.IsFail())
         return marketResult;

      double price=(direction==BRE_DIRECTION_BUY) ?
                   SymbolInfoDouble(symbol,SYMBOL_ASK) :
                   SymbolInfoDouble(symbol,SYMBOL_BID);

      CVoidResult stopsResult=ValidateStopsLevel(symbol,price,stopLoss,takeProfit);
      if(stopsResult.IsFail())
         return stopsResult;

      CVoidResult freezeResult=ValidateFreezeLevel(symbol,price,stopLoss,takeProfit);
      if(freezeResult.IsFail())
         return freezeResult;

      ENUM_ORDER_TYPE orderType=(direction==BRE_DIRECTION_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      return ValidateMargin(symbol,orderType,volume,price);
     }
  };

#endif
