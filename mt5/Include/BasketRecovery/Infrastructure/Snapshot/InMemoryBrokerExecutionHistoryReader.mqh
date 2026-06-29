#ifndef BRE_INF_IN_MEMORY_BROKER_EXECUTION_HISTORY_READER_MQH
#define BRE_INF_IN_MEMORY_BROKER_EXECUTION_HISTORY_READER_MQH

#include <BasketRecovery/Application/Ports/IBrokerExecutionHistoryReader.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CInMemoryBrokerExecutionHistoryReader : public IBrokerExecutionHistoryReader
  {
private:
   string                              m_requestIds[];
   CBrokerExecutionHistoryCorrelation m_correlations[];
   bool                                m_queryAvailable;

public:
                     CInMemoryBrokerExecutionHistoryReader(void)
     {
      m_queryAvailable=true;
     }

   void              SetQueryAvailable(const bool value) { m_queryAvailable=value; }

   void              SetCorrelation(const string executionRequestId,
                                    const CBrokerExecutionHistoryCorrelation &correlation)
     {
      for(int i=0;i<ArraySize(m_requestIds);i++)
        {
         if(m_requestIds[i]==executionRequestId)
           {
            m_correlations[i]=correlation;
            return;
           }
        }
      int size=ArraySize(m_requestIds);
      ArrayResize(m_requestIds,size+1);
      ArrayResize(m_correlations,size+1);
      m_requestIds[size]=executionRequestId;
      m_correlations[size]=correlation;
     }

   void              Clear(void)
     {
      ArrayResize(m_requestIds,0);
      ArrayResize(m_correlations,0);
     }

   virtual CResult<bool> CorrelateExecutionHistory(const CPendingExecutionEntry &entry,
                                                   CBrokerExecutionHistoryCorrelation &outCorrelation) const
     {
      if(!m_queryAvailable)
        {
         outCorrelation=CBrokerExecutionHistoryCorrelation::Unavailable();
         return CResult<bool>::Ok(false);
        }

      for(int i=0;i<ArraySize(m_requestIds);i++)
        {
         if(m_requestIds[i]!=entry.ExecutionRequestId())
            continue;
         outCorrelation=m_correlations[i];
         outCorrelation.SetQueryAvailable(true);
         return CResult<bool>::Ok(true);
        }

      outCorrelation=CBrokerExecutionHistoryCorrelation::Unavailable("no_history_match");
      outCorrelation.SetQueryAvailable(true);
      return CResult<bool>::Ok(true);
     }
  };

#endif
