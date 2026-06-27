#ifndef BRE_APP_IBROKER_POSITION_READER_MQH
#define BRE_APP_IBROKER_POSITION_READER_MQH

#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class IBrokerPositionReader
  {
public:
   virtual          ~IBrokerPositionReader(void) {}
   virtual CResult<int> ReadOpenPositions(CPositionSnapshotEntry &outEntries[],const int maxEntries) const=0;
  };

#endif
