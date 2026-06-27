#ifndef BRE_APP_EXECUTION_RECONCILIATION_RESOLVER_MQH
#define BRE_APP_EXECUTION_RECONCILIATION_RESOLVER_MQH

#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Application/Ports/IBrokerPositionReader.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>

class CExecutionReconciliationResolver
  {
public:
   static ENUM_BRE_TRADE_EXECUTION_STATUS Resolve(const CPendingExecutionEntry &entry,
                                                  IBrokerPositionReader *positionReader,
                                                  double &matchedVolumeOut)
     {
      matchedVolumeOut=0.0;
      if(positionReader==NULL)
         return BRE_TRADE_EXEC_STATUS_UNKNOWN;

      CPositionSnapshotEntry positions[];
      CResult<int> readResult=positionReader.ReadOpenPositions(positions,64);
      if(readResult.IsFail())
         return BRE_TRADE_EXEC_STATUS_UNKNOWN;

      int count=0;
      readResult.TryGetValue(count);

      ulong ticket=entry.BrokerCorrelation().PositionTicket();
      long magic=entry.BrokerCorrelation().MagicNumber();
      string symbol=entry.Symbol();
      double matchedVolume=0.0;
      bool found=false;

      for(int i=0;i<count;i++)
        {
         if(ticket>0 && positions[i].Ticket()!=ticket)
            continue;
         if(ticket==0 && magic>0 && positions[i].Magic()!=magic)
            continue;
         if(positions[i].Symbol()!=symbol)
            continue;
         found=true;
         matchedVolume+=positions[i].Volume();
        }

      matchedVolumeOut=matchedVolume;
      if(!found)
         return BRE_TRADE_EXEC_STATUS_REJECTED;

      if(entry.RequestedVolume()>0.0 && matchedVolume+0.0000001>=entry.RequestedVolume())
         return BRE_TRADE_EXEC_STATUS_FILLED;
      if(matchedVolume>0.0)
         return BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED;
      return BRE_TRADE_EXEC_STATUS_UNKNOWN;
     }
  };

#endif
