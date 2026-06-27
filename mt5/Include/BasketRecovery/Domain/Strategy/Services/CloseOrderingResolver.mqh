#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_CLOSE_ORDERING_RESOLVER_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_CLOSE_ORDERING_RESOLVER_MQH

#include <BasketRecovery/Domain/Strategy/Context/PositionRuntimeView.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/CloseMode.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CCloseOrderingResolver
  {
private:
   void              CopyTickets(const CPositionRuntimeView &positions[],const int count,ulong &outTickets[]) const
     {
      ArrayResize(outTickets,count);
      for(int i=0;i<count;i++)
         outTickets[i]=positions[i].Ticket();
     }

   void              SortByEntryWorstFirst(CPositionRuntimeView &positions[],const int count,const ENUM_BRE_TRADE_DIRECTION direction) const
     {
      for(int i=0;i<count-1;i++)
        {
         for(int j=i+1;j<count;j++)
           {
            bool swap=false;
            if(direction==BRE_DIRECTION_SELL)
               swap=positions[j].EntryPrice()>positions[i].EntryPrice();
            else if(direction==BRE_DIRECTION_BUY)
               swap=positions[j].EntryPrice()<positions[i].EntryPrice();
            if(swap)
              {
               CPositionRuntimeView temp=positions[i];
               positions[i]=positions[j];
               positions[j]=temp;
              }
           }
        }
     }

   void              SortByEntryBestFirst(CPositionRuntimeView &positions[],const int count,const ENUM_BRE_TRADE_DIRECTION direction) const
     {
      for(int i=0;i<count-1;i++)
        {
         for(int j=i+1;j<count;j++)
           {
            bool swap=false;
            if(direction==BRE_DIRECTION_SELL)
               swap=positions[j].EntryPrice()<positions[i].EntryPrice();
            else if(direction==BRE_DIRECTION_BUY)
               swap=positions[j].EntryPrice()>positions[i].EntryPrice();
            if(swap)
              {
               CPositionRuntimeView temp=positions[i];
               positions[i]=positions[j];
               positions[j]=temp;
              }
           }
        }
     }

   void              SortByOpenTime(CPositionRuntimeView &positions[],const int count,const bool ascending) const
     {
      for(int i=0;i<count-1;i++)
        {
         for(int j=i+1;j<count;j++)
           {
            bool swap=ascending ? positions[j].OpenTime()<positions[i].OpenTime()
                                : positions[j].OpenTime()>positions[i].OpenTime();
            if(swap)
              {
               CPositionRuntimeView temp=positions[i];
               positions[i]=positions[j];
               positions[j]=temp;
              }
           }
        }
     }

   void              SortByLot(CPositionRuntimeView &positions[],const int count,const bool largestFirst) const
     {
      for(int i=0;i<count-1;i++)
        {
         for(int j=i+1;j<count;j++)
           {
            bool swap=largestFirst ? positions[j].Lot()>positions[i].Lot()
                                   : positions[j].Lot()<positions[i].Lot();
            if(swap)
              {
               CPositionRuntimeView temp=positions[i];
               positions[i]=positions[j];
               positions[j]=temp;
              }
           }
        }
     }

   void              SortByFloatingProfit(CPositionRuntimeView &positions[],const int count,const bool highestFirst) const
     {
      for(int i=0;i<count-1;i++)
        {
         for(int j=i+1;j<count;j++)
           {
            bool swap=highestFirst ? positions[j].FloatingProfit()>positions[i].FloatingProfit()
                                   : positions[j].FloatingProfit()<positions[i].FloatingProfit();
            if(swap)
              {
               CPositionRuntimeView temp=positions[i];
               positions[i]=positions[j];
               positions[j]=temp;
              }
           }
        }
     }

   void              SortByRisk(CPositionRuntimeView &positions[],const int count,const bool highestFirst) const
     {
      for(int i=0;i<count-1;i++)
        {
         for(int j=i+1;j<count;j++)
           {
            bool swap=highestFirst ? positions[j].PositionRiskUsd()>positions[i].PositionRiskUsd()
                                   : positions[j].PositionRiskUsd()<positions[i].PositionRiskUsd();
            if(swap)
              {
               CPositionRuntimeView temp=positions[i];
               positions[i]=positions[j];
               positions[j]=temp;
              }
           }
        }
     }

public:
   int               ResolveTickets(const ENUM_BRE_CLOSE_MODE closeMode,
                                    const ENUM_BRE_TRADE_DIRECTION basketDirection,
                                    const CPositionRuntimeView &positions[],
                                    const int positionCount,
                                    const double closePercent,
                                    ulong &outTickets[]) const
     {
      if(positionCount<=0)
        {
         ArrayResize(outTickets,0);
         return 0;
        }

      CPositionRuntimeView sorted[];
      ArrayResize(sorted,positionCount);
      for(int i=0;i<positionCount;i++)
         sorted[i]=positions[i];

      switch(closeMode)
        {
         case BRE_CLOSE_MODE_WORST_ENTRY_FIRST:
            SortByEntryWorstFirst(sorted,positionCount,basketDirection);
            break;
         case BRE_CLOSE_MODE_BEST_ENTRY_FIRST:
            SortByEntryBestFirst(sorted,positionCount,basketDirection);
            break;
         case BRE_CLOSE_MODE_FIFO:
            SortByOpenTime(sorted,positionCount,true);
            break;
         case BRE_CLOSE_MODE_LIFO:
            SortByOpenTime(sorted,positionCount,false);
            break;
         case BRE_CLOSE_MODE_LARGEST_LOT_FIRST:
            SortByLot(sorted,positionCount,true);
            break;
         case BRE_CLOSE_MODE_SMALLEST_LOT_FIRST:
            SortByLot(sorted,positionCount,false);
            break;
         case BRE_CLOSE_MODE_PROFIT_BASED:
            SortByFloatingProfit(sorted,positionCount,false);
            break;
         case BRE_CLOSE_MODE_RISK_BASED:
            SortByRisk(sorted,positionCount,true);
            break;
         default:
            SortByEntryWorstFirst(sorted,positionCount,basketDirection);
            break;
        }

      int closeCount=positionCount;
      if(closePercent<100.0)
        {
         closeCount=(int)MathCeil(positionCount*closePercent/100.0);
         if(closeCount<=0)
            closeCount=1;
         if(closeCount>positionCount)
            closeCount=positionCount;
        }

      ArrayResize(outTickets,closeCount);
      for(int i=0;i<closeCount;i++)
         outTickets[i]=sorted[i].Ticket();
      return closeCount;
     }
  };

#endif
