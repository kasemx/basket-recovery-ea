#ifndef BRE_INF_IN_MEMORY_EXECUTION_AUTHORIZATION_STORE_MQH
#define BRE_INF_IN_MEMORY_EXECUTION_AUTHORIZATION_STORE_MQH

#include <BasketRecovery/Application/Execution/Ports/IExecutionAuthorizationStore.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationPersistenceCodec.mqh>

class CInMemoryExecutionAuthorizationStore : public IExecutionAuthorizationStore
  {
private:
   CManualDemoExecutionAuthorization m_records[];

   int               FindIndex(const string tokenHash) const
     {
      for(int i=0;i<ArraySize(m_records);i++)
        {
         if(m_records[i].TokenHash()==tokenHash)
            return i;
        }
      return -1;
     }

public:
   virtual CVoidResult Save(const CManualDemoExecutionAuthorization &record)
     {
      int index=FindIndex(record.TokenHash());
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
      return CVoidResult::Ok();
     }

   virtual bool      TryGetByTokenHash(const string tokenHash,CManualDemoExecutionAuthorization &record) const
     {
      int index=FindIndex(tokenHash);
      if(index<0)
         return false;
      record=m_records[index];
      return true;
     }

   virtual int         RestoreRecords(CManualDemoExecutionAuthorization &records[]) const
     {
      int count=ArraySize(m_records);
      ArrayResize(records,count);
      for(int i=0;i<count;i++)
         records[i]=m_records[i];
      return count;
     }

   virtual CVoidResult Clear(void)
     {
      ArrayResize(m_records,0);
      return CVoidResult::Ok();
     }

   string            ExportText(void) const
     {
      string text="";
      for(int i=0;i<ArraySize(m_records);i++)
        {
         if(text!="")
            text+="\n";
         text+=CExecutionAuthorizationPersistenceCodec::Encode(m_records[i]);
        }
      return text;
     }

   void              ImportText(const string text)
     {
      string lines[];
      int count=StringSplit(text,'\n',lines);
      ArrayResize(m_records,0);
      for(int i=0;i<count;i++)
        {
         CManualDemoExecutionAuthorization record;
         if(!CExecutionAuthorizationPersistenceCodec::TryDecode(lines[i],record))
            continue;
         Save(record);
        }
     }
  };

#endif
