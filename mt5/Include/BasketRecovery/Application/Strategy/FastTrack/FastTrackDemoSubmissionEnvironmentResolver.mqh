#ifndef BRE_APP_FAST_TRACK_DEMO_SUBMISSION_ENVIRONMENT_RESOLVER_MQH
#define BRE_APP_FAST_TRACK_DEMO_SUBMISSION_ENVIRONMENT_RESOLVER_MQH

#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackDemoSubmissionTypes.mqh>

class CFastTrackDemoSubmissionEnvironmentResolver
  {
private:
   static int        CountSymbolExposure(const string symbol,const bool countPositions,const bool countPending)
     {
      int count=0;
      if(countPositions)
        {
         for(int i=PositionsTotal()-1;i>=0;i--)
           {
            if(!PositionSelectByTicket(PositionGetTicket(i)))
               continue;
            if(PositionGetString(POSITION_SYMBOL)==symbol)
               count++;
           }
        }
      if(countPending)
        {
         for(int i=OrdersTotal()-1;i>=0;i--)
           {
            if(!OrderSelect(OrderGetTicket(i)))
               continue;
            if(OrderGetString(ORDER_SYMBOL)==symbol)
               count++;
           }
        }
      return count;
     }

public:
   static SFastTrackDemoSubmissionEnvironment ResolveRuntime(const string symbol)
     {
      SFastTrackDemoSubmissionEnvironment environment;
      environment.Reset();

      const ENUM_ACCOUNT_TRADE_MODE tradeMode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
      environment.account_is_demo=(tradeMode==ACCOUNT_TRADE_MODE_DEMO);
      environment.account_equity_usd=AccountInfoDouble(ACCOUNT_EQUITY);

      SymbolSelect(symbol,true);
      environment.symbol_bid=SymbolInfoDouble(symbol,SYMBOL_BID);
      environment.symbol_ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
      environment.symbol_point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      environment.symbol_tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      environment.symbol_tick_value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
      environment.symbol_stops_level=(int)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
      environment.symbol_freeze_level=(int)SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL);
      environment.symbol_min_lot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      environment.symbol_volume_step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      environment.open_positions_for_symbol=CountSymbolExposure(symbol,true,false);
      environment.pending_orders_for_symbol=CountSymbolExposure(symbol,false,true);
      return environment;
     }
  };

#endif
