#ifndef BRE_DOMAIN_PROFIT_LEVEL_POSITION_SELECTOR_MQH
#define BRE_DOMAIN_PROFIT_LEVEL_POSITION_SELECTOR_MQH

#include <BasketRecovery/Domain/Strategy/Context/PositionRuntimeView.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/CloseMode.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CProfitLevelPositionSelector
  {
private:
   static void       SortByEntryWorstFirst(CPositionRuntimeView &positions[],const int count,const ENUM_BRE_TRADE_DIRECTION direction)
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

   static void       SortByEntryBestFirst(CPositionRuntimeView &positions[],const int count,const ENUM_BRE_TRADE_DIRECTION direction)
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

   static void       SortByOpenTime(CPositionRuntimeView &positions[],const int count,const bool ascending)
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

   static void       SortByLot(CPositionRuntimeView &positions[],const int count,const bool largestFirst)
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

   static void       SortByFloatingProfit(CPositionRuntimeView &positions[],const int count,const bool highestFirst)
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

public:
   static int        SelectOrdered(const ENUM_BRE_CLOSE_MODE closeMode,
                                   const ENUM_BRE_TRADE_DIRECTION direction,
                                   const CPositionRuntimeView &positions[],
                                   const int positionCount,
                                   CPositionRuntimeView &outOrdered[])
     {
      if(positionCount<=0)
        {
         ArrayResize(outOrdered,0);
         return 0;
        }

      ArrayResize(outOrdered,positionCount);
      for(int i=0;i<positionCount;i++)
         outOrdered[i]=positions[i];

      switch(closeMode)
        {
         case BRE_CLOSE_MODE_WORST_ENTRY_FIRST:
            SortByEntryWorstFirst(outOrdered,positionCount,direction);
            break;
         case BRE_CLOSE_MODE_BEST_ENTRY_FIRST:
            SortByEntryBestFirst(outOrdered,positionCount,direction);
            break;
         case BRE_CLOSE_MODE_FIFO:
            SortByOpenTime(outOrdered,positionCount,true);
            break;
         case BRE_CLOSE_MODE_LIFO:
            SortByOpenTime(outOrdered,positionCount,false);
            break;
         case BRE_CLOSE_MODE_LARGEST_LOT_FIRST:
            SortByLot(outOrdered,positionCount,true);
            break;
         case BRE_CLOSE_MODE_PROFIT_BASED:
            SortByFloatingProfit(outOrdered,positionCount,true);
            break;
         default:
            SortByEntryWorstFirst(outOrdered,positionCount,direction);
            break;
        }
      return positionCount;
     }
  };

#endif
