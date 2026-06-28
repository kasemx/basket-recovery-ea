#ifndef BRE_INF_FILE_PENDING_EXECUTION_STORE_MQH
#define BRE_INF_FILE_PENDING_EXECUTION_STORE_MQH

#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>

class CFilePendingExecutionStore : public CInMemoryPendingExecutionStore
  {
private:
   string m_filePath;

   bool              ReadFileText(string &content) const
     {
      content="";
      int handle=FileOpen(m_filePath,FILE_READ|FILE_TXT|FILE_ANSI);
      if(handle==INVALID_HANDLE)
         return false;
      while(!FileIsEnding(handle))
        {
         string line=FileReadString(handle);
         if(content!="")
            content+="\n";
         content+=line;
        }
      FileClose(handle);
      return true;
     }

   bool              WriteFileText(const string content) const
     {
      int handle=FileOpen(m_filePath,FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(handle==INVALID_HANDLE)
         return false;
      FileWriteString(handle,content);
      FileClose(handle);
      return true;
     }

public:
                     CFilePendingExecutionStore(const string filePath)
     {
      m_filePath=filePath;
     }

   CVoidResult       RestoreFromDisk(void)
     {
      string content;
      if(!ReadFileText(content))
         return CVoidResult::Ok();

      string sections[];
      int sectionCount=StringSplit(content,'\f',sections);
      if(sectionCount>=1)
         ImportEntriesText(sections[0]);
      if(sectionCount>=2)
         ImportEnvelopesText(sections[1]);
      return CVoidResult::Ok();
     }

   virtual CVoidResult SavePreparedState(const CPendingExecutionEntry &entry,
                                         const CBrokerSubmissionEnvelope &envelope)
     {
      CVoidResult saved=CInMemoryPendingExecutionStore::SavePreparedState(entry,envelope);
      if(saved.IsFail())
         return saved;

      string payload=ExportEntriesText()+"\f"+ExportEnvelopesText();
      if(!WriteFileText(payload))
         return CVoidResult::Fail(-1,"Failed to persist pending execution store");
      return CVoidResult::Ok();
     }

   virtual CVoidResult SaveEntryState(const CPendingExecutionEntry &entry)
     {
      CVoidResult saved=CInMemoryPendingExecutionStore::SaveEntryState(entry);
      if(saved.IsFail())
         return saved;

      string payload=ExportEntriesText()+"\f"+ExportEnvelopesText();
      if(!WriteFileText(payload))
         return CVoidResult::Fail(-1,"Failed to persist pending execution entry state");
      return CVoidResult::Ok();
     }
  };

#endif
