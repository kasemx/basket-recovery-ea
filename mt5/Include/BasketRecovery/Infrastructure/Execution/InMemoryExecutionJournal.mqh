#ifndef BRE_INF_IN_MEMORY_EXECUTION_JOURNAL_MQH
#define BRE_INF_IN_MEMORY_EXECUTION_JOURNAL_MQH

#include <BasketRecovery/Application/Execution/Ports/IExecutionJournal.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionRequestRepository.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CInMemoryExecutionJournal : public IExecutionJournal
  {
private:
   CInMemoryExecutionRequestRepository *m_repository;

public:
                     CInMemoryExecutionJournal(CInMemoryExecutionRequestRepository *repository)
     {
      m_repository=repository;
     }

   virtual CVoidResult RecordReceipt(const CTradeExecutionReceipt &receipt)
     {
      if(m_repository==NULL)
         return CVoidResult::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Execution repository is not configured");
      return m_repository.Save(receipt);
     }

   virtual CVoidResult AppendTransition(const string executionRequestId,
                                        const CExecutionStatusTransition &transition)
     {
      if(m_repository==NULL)
         return CVoidResult::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Execution repository is not configured");

      CResult<CTradeExecutionReceipt> loaded=m_repository.FindByExecutionRequestId(executionRequestId);
      if(loaded.IsFail())
         return CVoidResult::Fail(loaded.ErrorCode(),loaded.ErrorMessage());

      CTradeExecutionReceipt receipt;
      loaded.TryGetValue(receipt);
      receipt.AppendTransition(transition);
      receipt.SetCurrentStatus(transition.ToStatus());
      return m_repository.Save(receipt);
     }

   virtual CResult<CTradeExecutionReceipt> FindByExecutionRequestId(const string executionRequestId) const
     {
      if(m_repository==NULL)
         return CResult<CTradeExecutionReceipt>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Execution repository is not configured");
      return m_repository.FindByExecutionRequestId(executionRequestId);
     }

   virtual CResult<CTradeExecutionReceipt> FindByIdempotencyKey(const string idempotencyKey) const
     {
      if(m_repository==NULL)
         return CResult<CTradeExecutionReceipt>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Execution repository is not configured");
      return m_repository.FindByIdempotencyKey(idempotencyKey);
     }
  };

#endif
