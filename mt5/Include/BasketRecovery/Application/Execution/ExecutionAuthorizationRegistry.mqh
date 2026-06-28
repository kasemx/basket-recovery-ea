#ifndef BRE_APP_EXECUTION_AUTHORIZATION_REGISTRY_MQH
#define BRE_APP_EXECUTION_AUTHORIZATION_REGISTRY_MQH

#include <BasketRecovery/Domain/Execution/ManualDemoExecutionAuthorization.mqh>
#include <BasketRecovery/Application/Execution/Ports/IExecutionAuthorizationStore.mqh>

class CExecutionAuthorizationRegistry
  {
private:
   CManualDemoExecutionAuthorization m_records[];
   IExecutionAuthorizationStore     *m_store;
   int                               m_sessionAuthorizedCount;

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
     }

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
      if(m_store!=NULL)
         m_store.Clear();
     }
  };

#endif
