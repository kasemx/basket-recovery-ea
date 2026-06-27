#ifndef BRE_INF_IN_MEMORY_EXECUTION_REQUEST_REPOSITORY_MQH
#define BRE_INF_IN_MEMORY_EXECUTION_REQUEST_REPOSITORY_MQH

#include <BasketRecovery/Application/Execution/Ports/IExecutionRequestRepository.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CInMemoryExecutionRequestRepository : public IExecutionRequestRepository
  {
private:
   CTradeExecutionReceipt m_items[];
   int                    m_count;

   int               FindByRequestIdIndex(const string executionRequestId) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i].Request().ExecutionRequestId()==executionRequestId)
            return i;
        }
      return -1;
     }

   int               FindByIdempotencyIndex(const string idempotencyKey) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i].Request().IdempotencyKey()==idempotencyKey)
            return i;
        }
      return -1;
     }

public:
                     CInMemoryExecutionRequestRepository(void) { m_count=0; }

   virtual CVoidResult Save(const CTradeExecutionReceipt &receipt)
     {
      int index=FindByRequestIdIndex(receipt.Request().ExecutionRequestId());
      if(index<0)
        {
         ArrayResize(m_items,m_count+1);
         m_items[m_count]=receipt;
         m_count++;
         return CVoidResult::Ok();
        }
      m_items[index]=receipt;
      return CVoidResult::Ok();
     }

   virtual CResult<CTradeExecutionReceipt> FindByExecutionRequestId(const string executionRequestId) const
     {
      int index=FindByRequestIdIndex(executionRequestId);
      if(index<0)
         return CResult<CTradeExecutionReceipt>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Execution request not found");
      return CResult<CTradeExecutionReceipt>::Ok(m_items[index]);
     }

   virtual CResult<CTradeExecutionReceipt> FindByIdempotencyKey(const string idempotencyKey) const
     {
      int index=FindByIdempotencyIndex(idempotencyKey);
      if(index<0)
         return CResult<CTradeExecutionReceipt>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Execution request not found");
      return CResult<CTradeExecutionReceipt>::Ok(m_items[index]);
     }

   int               Count(void) const { return m_count; }
  };

#endif
