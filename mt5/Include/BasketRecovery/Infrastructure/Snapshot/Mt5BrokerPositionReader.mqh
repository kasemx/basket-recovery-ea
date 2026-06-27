#ifndef BRE_INF_MT5_BROKER_POSITION_READER_MQH
#define BRE_INF_MT5_BROKER_POSITION_READER_MQH

#include <BasketRecovery/Application/Ports/IBrokerPositionReader.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/BrokerCommentParser.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CMt5BrokerPositionReader : public IBrokerPositionReader
  {
private:
   ENUM_BRE_TRADE_DIRECTION ResolveDirection(const long positionType) const
     {
      if(positionType==POSITION_TYPE_BUY)
         return BRE_DIRECTION_BUY;
      if(positionType==POSITION_TYPE_SELL)
         return BRE_DIRECTION_SELL;
      return BRE_DIRECTION_NONE;
     }

public:
   virtual CResult<int> ReadOpenPositions(CPositionSnapshotEntry &outEntries[],const int maxEntries) const
     {
      if(maxEntries<=0)
         return CResult<int>::Ok(0);

      ArrayResize(outEntries,0);
      int written=0;
      int total=PositionsTotal();
      for(int i=0;i<total && written<maxEntries;i++)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0 || !PositionSelectByTicket(ticket))
            continue;

         string comment=PositionGetString(POSITION_COMMENT);
         CBasketId basketId=CBrokerCommentParser::ExtractBasketId(comment);
         if(basketId.IsEmpty())
            continue;

         long positionType=PositionGetInteger(POSITION_TYPE);
         CPositionSnapshotEntry entry=CPositionSnapshotEntry::Create(basketId,
                                                                     ticket,
                                                                     PositionGetInteger(POSITION_MAGIC),
                                                                     PositionGetString(POSITION_SYMBOL),
                                                                     ResolveDirection(positionType),
                                                                     CBrokerCommentParser::ExtractRole(comment),
                                                                     CBrokerCommentParser::ExtractRecoveryStepIndex(comment),
                                                                     PositionGetDouble(POSITION_PRICE_OPEN),
                                                                     PositionGetDouble(POSITION_PRICE_CURRENT),
                                                                     PositionGetDouble(POSITION_SL),
                                                                     PositionGetDouble(POSITION_TP),
                                                                     PositionGetDouble(POSITION_VOLUME),
                                                                     PositionGetDouble(POSITION_PROFIT),
                                                                     PositionGetDouble(POSITION_COMMISSION),
                                                                     PositionGetDouble(POSITION_SWAP),
                                                                     (datetime)PositionGetInteger(POSITION_TIME),
                                                                     BRE_POSITION_SNAPSHOT_OPEN,
                                                                     CBrokerCommentParser::ExtractCorrelationId(comment));
         ArrayResize(outEntries,written+1);
         outEntries[written]=entry;
         written++;
        }

      return CResult<int>::Ok(written);
     }
  };

#endif
