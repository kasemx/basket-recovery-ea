#ifndef BRE_APP_PENDING_EXECUTION_REGISTRY_MQH
#define BRE_APP_PENDING_EXECUTION_REGISTRY_MQH

#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionTransitionRules.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionTransitionGate.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionCorrelationContext.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionCorrelationMatcher.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class CPendingExecutionRegistry
  {
private:
   CPendingExecutionEntry m_entries[];
   string                 m_processedKeys[];

   int               FindIndexByExecutionRequestId(const string executionRequestId) const
     {
      for(int i=0;i<ArraySize(m_entries);i++)
        {
         if(m_entries[i].ExecutionRequestId()==executionRequestId)
            return i;
        }
      return -1;
     }

   bool              HasProcessedKey(const string key) const
     {
      for(int i=0;i<ArraySize(m_processedKeys);i++)
        {
         if(m_processedKeys[i]==key)
            return true;
        }
      return false;
     }

   void              RememberProcessedKey(const string key)
     {
      if(key=="" || HasProcessedKey(key))
         return;
      int size=ArraySize(m_processedKeys);
      ArrayResize(m_processedKeys,size+1);
      m_processedKeys[size]=key;
     }

public:
   int               Count(void) const { return ArraySize(m_entries); }

   bool              TryGetByExecutionRequestId(const string executionRequestId,CPendingExecutionEntry &entry) const
     {
      int index=FindIndexByExecutionRequestId(executionRequestId);
      if(index<0)
         return false;
      entry=m_entries[index];
      return true;
     }

   bool              TryGetByIdempotencyKey(const string idempotencyKey,CPendingExecutionEntry &entry) const
     {
      for(int i=0;i<ArraySize(m_entries);i++)
        {
         if(m_entries[i].IdempotencyKey()==idempotencyKey)
           {
            entry=m_entries[i];
            return true;
           }
        }
      return false;
     }

   CVoidResult       Upsert(const CPendingExecutionEntry &entry)
     {
      if(entry.ExecutionRequestId()=="")
         return CVoidResult::Fail(-1,"executionRequestId is required");
      int index=FindIndexByExecutionRequestId(entry.ExecutionRequestId());
      if(index<0)
        {
         int size=ArraySize(m_entries);
         ArrayResize(m_entries,size+1);
         m_entries[size]=entry;
         return CVoidResult::Ok();
        }
      m_entries[index]=entry;
      return CVoidResult::Ok();
     }

   CVoidResult       Register(const CPendingExecutionEntry &entry)
     {
      if(entry.ExecutionRequestId()=="")
         return CVoidResult::Fail(-1,"executionRequestId is required");
      if(FindIndexByExecutionRequestId(entry.ExecutionRequestId())>=0)
         return CVoidResult::Fail(-1,"executionRequestId already registered");
      int size=ArraySize(m_entries);
      ArrayResize(m_entries,size+1);
      m_entries[size]=entry;
      return CVoidResult::Ok();
     }

   bool              TryUpdateEntry(const int index,CPendingExecutionEntry &entry)
     {
      if(index<0 || index>=ArraySize(m_entries))
         return false;
      m_entries[index]=entry;
      return true;
     }

   bool              TryGetEntry(const int index,CPendingExecutionEntry &entry) const
     {
      if(index<0 || index>=ArraySize(m_entries))
         return false;
      entry=m_entries[index];
      return true;
     }

   int               TryCorrelate(const CTradeTransactionCorrelationContext &context,
                                  ENUM_BRE_CORRELATION_MATCH_STRATEGY &strategyUsed)
     {
      strategyUsed=BRE_CORRELATION_MATCH_NONE;
      for(int i=0;i<ArraySize(m_entries);i++)
        {
         if(CPendingExecutionCorrelationMatcher::TryMatch(m_entries[i],context,strategyUsed))
            return i;
        }
      return -1;
     }

   bool              IsDuplicateTransaction(const string transactionKey) const
     {
      return transactionKey!="" && HasProcessedKey(transactionKey);
     }

   void              MarkTransactionProcessed(const string transactionKey)
     {
      RememberProcessedKey(transactionKey);
     }

   bool              TryTransition(const int index,
                                   const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus,
                                   CPendingExecutionEntry &updatedEntry)
     {
      if(index<0 || index>=ArraySize(m_entries))
         return false;
      if(toStatus==BRE_TRADE_EXEC_STATUS_SUBMITTED)
         return false;
      ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus=m_entries[index].Status();
      if(!CPendingExecutionTransitionRules::CanTransition(fromStatus,toStatus))
         return false;
      m_entries[index].SetStatus(toStatus);
      updatedEntry=m_entries[index];
      return true;
     }

   bool              TryTransitionByRequestId(const string executionRequestId,
                                              const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus,
                                              CPendingExecutionEntry &updatedEntry)
     {
      int index=FindIndexByExecutionRequestId(executionRequestId);
      return TryTransition(index,toStatus,updatedEntry);
     }

   bool              TryBrokerSubmitTransition(const string executionRequestId,
                                               const bool brokerSubmitAccepted,
                                               CPendingExecutionEntry &updatedEntry)
     {
      if(!brokerSubmitAccepted)
         return false;
      int index=FindIndexByExecutionRequestId(executionRequestId);
      if(index<0)
         return false;
      ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus=m_entries[index].Status();
      if(!CBrokerSubmissionTransitionGate::CanTransitionToSubmitted(fromStatus,true))
         return false;
      if(!CPendingExecutionTransitionRules::CanTransition(fromStatus,BRE_TRADE_EXEC_STATUS_SUBMITTED))
         return false;
      m_entries[index].SetStatus(BRE_TRADE_EXEC_STATUS_SUBMITTED);
      updatedEntry=m_entries[index];
      return true;
     }

   int               CollectTimeoutDue(const datetime nowUtc,int &dueIndices[])
     {
      ArrayResize(dueIndices,0);
      for(int i=0;i<ArraySize(m_entries);i++)
        {
         if(!m_entries[i].IsPendingTimeout(nowUtc))
            continue;
         int size=ArraySize(dueIndices);
         ArrayResize(dueIndices,size+1);
         dueIndices[size]=i;
        }
      return ArraySize(dueIndices);
     }

   void              Clear(void)
     {
      ArrayResize(m_entries,0);
      ArrayResize(m_processedKeys,0);
     }
  };

#endif
