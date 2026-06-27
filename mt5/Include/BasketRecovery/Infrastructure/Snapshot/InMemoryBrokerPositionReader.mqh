#ifndef BRE_INF_IN_MEMORY_BROKER_POSITION_READER_MQH
#define BRE_INF_IN_MEMORY_BROKER_POSITION_READER_MQH

#include <BasketRecovery/Application/Ports/IBrokerPositionReader.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CInMemoryBrokerPositionReader : public IBrokerPositionReader
  {
private:
   CPositionSnapshotEntry m_entries[];

public:
   void              SetEntries(const CPositionSnapshotEntry &entries[],const int count)
     {
      ArrayResize(m_entries,count);
      for(int i=0;i<count;i++)
         m_entries[i]=entries[i];
     }

   virtual CResult<int> ReadOpenPositions(CPositionSnapshotEntry &outEntries[],const int maxEntries) const
     {
      int sourceCount=ArraySize(m_entries);
      int written=MathMin(sourceCount,maxEntries);
      ArrayResize(outEntries,written);
      for(int i=0;i<written;i++)
         outEntries[i]=m_entries[i];
      return CResult<int>::Ok(written);
     }
  };

#endif
