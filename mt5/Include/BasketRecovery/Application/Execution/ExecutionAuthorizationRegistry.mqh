#ifndef BRE_APP_EXECUTION_AUTHORIZATION_REGISTRY_MQH
#define BRE_APP_EXECUTION_AUTHORIZATION_REGISTRY_MQH

#include <BasketRecovery/Domain/Execution/ManualDemoExecutionAuthorization.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationStatus.mqh>
#include <BasketRecovery/Application/Execution/Ports/IExecutionAuthorizationStore.mqh>

class CExecutionAuthorizationRegistry
  {
private:
   CManualDemoExecutionAuthorization m_records[];
   IExecutionAuthorizationStore     *m_store;
   int                               m_sessionAuthorizedCount;
   int                               m_sessionSubmissionCount;
   string                            m_sessionLockedSymbol;

   int               FindIndexByTokenHash(const string tokenHash) const
     {
      for(int i=0;i<ArraySize(m_records);i++)
        {
         if(m_records[i].TokenHash()==tokenHash)
            return i;
        }
      return -1;
     }

public:
                     CExecutionAuthorizationRegistry(IExecutionAuthorizationStore *store=NULL)
     {
      m_store=store;
      m_sessionAuthorizedCount=0;
      m_sessionSubmissionCount=0;
      m_sessionLockedSymbol="";
     }

   int               SessionSubmissionCount(void) const { return m_sessionSubmissionCount; }
   string            SessionLockedSymbol(void) const { return m_sessionLockedSymbol; }

   int               SessionAuthorizedCount(void) const { return m_sessionAuthorizedCount; }

   bool              IsTokenConsumed(const string tokenHash) const
     {
      int index=FindIndexByTokenHash(tokenHash);
      if(index<0)
         return false;
      return m_records[index].Consumed();
     }

   bool              TryGetByTokenHash(const string tokenHash,CManualDemoExecutionAuthorization &record) const
     {
      int index=FindIndexByTokenHash(tokenHash);
      if(index<0)
         return false;
      record=m_records[index];
      return true;
     }

   CVoidResult       Upsert(const CManualDemoExecutionAuthorization &record)
     {
      int index=FindIndexByTokenHash(record.TokenHash());
      if(index<0)
        {
         int size=ArraySize(m_records);
         ArrayResize(m_records,size+1);
         m_records[size]=record;
        }
      else
        {
         m_records[index]=record;
        }
      if(m_store!=NULL)
         return m_store.Save(record);
      return CVoidResult::Ok();
     }

   bool              HasSessionCapacity(const int maxAuthorizedRequestsPerSession) const
     {
      if(maxAuthorizedRequestsPerSession<=0)
         return false;
      return m_sessionAuthorizedCount<maxAuthorizedRequestsPerSession;
     }

   void              IncrementSessionAuthorizedCount(void) { m_sessionAuthorizedCount++; }

   void              IncrementSessionSubmissionCount(void) { m_sessionSubmissionCount++; }

   bool              HasSubmissionSessionCapacity(const int maxSubmissionsPerSession) const
     {
      if(maxSubmissionsPerSession<=0)
         return false;
      return m_sessionSubmissionCount<maxSubmissionsPerSession;
     }

   bool              IsSessionSymbolAllowed(const string symbol) const
     {
      if(m_sessionLockedSymbol=="")
         return true;
      return m_sessionLockedSymbol==symbol;
     }

   void              LockSessionSymbol(const string symbol)
     {
      if(m_sessionLockedSymbol=="")
         m_sessionLockedSymbol=symbol;
     }

   bool              ConsumeToken(const string tokenHash)
     {
      int index=FindIndexByTokenHash(tokenHash);
      if(index<0)
         return false;
      if(m_records[index].Consumed())
         return false;
      m_records[index].SetConsumed(true);
      if(m_store!=NULL)
         m_store.Save(m_records[index]);
      return true;
     }

   bool              TryGetAuthorizedForRequest(const string executionRequestId,
                                                 CManualDemoExecutionAuthorization &record) const
     {
      for(int i=0;i<ArraySize(m_records);i++)
        {
         if(m_records[i].ExecutionRequestId()!=executionRequestId)
            continue;
         if(m_records[i].Status()!=BRE_AUTH_STATUS_AUTHORIZED_FOR_FUTURE_SUBMISSION)
            continue;
         record=m_records[i];
         return true;
      }
      return false;
     }

   int               RestoreFromStore(void)
     {
      if(m_store==NULL)
         return 0;
      CManualDemoExecutionAuthorization restored[];
      int count=m_store.RestoreRecords(restored);
      ArrayResize(m_records,count);
      for(int i=0;i<count;i++)
         m_records[i]=restored[i];
      return count;
     }

   void              Clear(void)
     {
      ArrayResize(m_records,0);
      m_sessionAuthorizedCount=0;
      m_sessionSubmissionCount=0;
      m_sessionLockedSymbol="";
      if(m_store!=NULL)
         m_store.Clear();
     }
  };

#endif
