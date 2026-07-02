#ifndef BRE_INF_FILE_PENDING_EXECUTION_STORE_MQH
#define BRE_INF_FILE_PENDING_EXECUTION_STORE_MQH

#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionPersistenceCodec.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

#define BRE_FILE_PENDING_EXECUTION_STORE_BUILD_MARKER "S8D_FILE_PENDING_STORE_PRISTINE_V1"

#define BRE_PENDING_RESTORE_OUTCOME_PRISTINE_EMPTY "PRISTINE_EMPTY_STORE"
#define BRE_PENDING_RESTORE_OUTCOME_ACTIVE         "RESTORED_FROM_ACTIVE"
#define BRE_PENDING_RESTORE_OUTCOME_TEMP           "RESTORED_FROM_TEMP"
#define BRE_PENDING_RESTORE_OUTCOME_BACKUP         "RESTORED_FROM_BACKUP"

class CFilePendingExecutionStore : public CInMemoryPendingExecutionStore
  {
private:
   string m_filePath;
   string m_lastRestoreOutcome;

   string            TempPath(void) const { return m_filePath+".tmp"; }
   string            BackupPath(void) const { return m_filePath+".bak"; }

   bool              SnapshotArtifactExists(const string relativePath) const
     {
      return FileIsExist(relativePath);
     }

   bool              HasAnySnapshotArtifact(void) const
     {
      return SnapshotArtifactExists(m_filePath) ||
             SnapshotArtifactExists(TempPath()) ||
             SnapshotArtifactExists(BackupPath());
     }

   CVoidResult       InitializePristineEmptyStore(void)
     {
      CVoidResult cleared=CInMemoryPendingExecutionStore::Clear();
      if(cleared.IsFail())
         return cleared;
      m_lastRestoreOutcome=BRE_PENDING_RESTORE_OUTCOME_PRISTINE_EMPTY;
      return CVoidResult::Ok();
     }

   bool              ReadFileTextAtPath(const string relativePath,string &content) const
     {
      content="";
      int handle=FileOpen(relativePath,FILE_READ|FILE_TXT|FILE_ANSI);
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

   bool              ReadFileText(string &content) const
     {
      return ReadFileTextAtPath(m_filePath,content);
     }

   bool              TryValidateSnapshotContent(const string content) const
     {
      string sections[];
      int sectionCount=StringSplit(content,'\f',sections);
      if(sectionCount<1)
         return content=="";

      string entryLines[];
      int entryLineCount=StringSplit(sections[0],'\n',entryLines);
      for(int i=0;i<entryLineCount;i++)
        {
         if(entryLines[i]=="")
            continue;
         CPendingExecutionEntry entry;
         if(!CPendingExecutionPersistenceCodec::TryDecodeEntry(entryLines[i],entry))
            return false;
        }

      if(sectionCount<2)
         return true;

      string envelopeLines[];
      int envelopeLineCount=StringSplit(sections[1],'\n',envelopeLines);
      for(int i=0;i<envelopeLineCount;i++)
        {
         if(envelopeLines[i]=="")
            continue;
         CBrokerSubmissionEnvelope envelope;
         if(!CPendingExecutionPersistenceCodec::TryDecodeEnvelope(envelopeLines[i],envelope))
            return false;
        }
      return true;
     }

   void              ImportSnapshotContent(const string content)
     {
      string sections[];
      int sectionCount=StringSplit(content,'\f',sections);
      if(sectionCount>=1)
         ImportEntriesText(sections[0]);
      if(sectionCount>=2)
         ImportEnvelopesText(sections[1]);
     }

   CVoidResult       EnsureDirectoryChain(const string relativePath) const
     {
      int lastSlash=-1;
      for(int i=StringLen(relativePath)-1;i>=0;i--)
        {
         if(StringGetCharacter(relativePath,i)=='/' || StringGetCharacter(relativePath,i)=='\\')
           {
            lastSlash=i;
            break;
           }
        }
      if(lastSlash<=0)
         return CVoidResult::Ok();

      string directory=StringSubstr(relativePath,0,lastSlash);
      string parts[];
      int count=StringSplit(directory,'/',parts);
      string current="";
      for(int i=0;i<count;i++)
        {
         if(parts[i]=="")
            continue;
         if(current=="")
            current=parts[i];
         else
            current=current+"/"+parts[i];
         if(!FolderCreate(current))
           {
            int error=GetLastError();
            if(error!=5019 && error!=5020)
               return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to create pending snapshot directory");
           }
        }
      return CVoidResult::Ok();
     }

   CVoidResult       WriteStringToHandle(const int handle,const string content) const
     {
      if(FileWriteString(handle,content)<=0)
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to write pending snapshot content");
      FileFlush(handle);
      return CVoidResult::Ok();
     }

   CVoidResult       WriteSnapshotFile(const string relativePath,const string content) const
     {
      int handle=FileOpen(relativePath,FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(handle==INVALID_HANDLE)
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to open pending snapshot file");

      CVoidResult writeResult=WriteStringToHandle(handle,content);
      FileClose(handle);
      if(writeResult.IsFail())
         return writeResult;

      string verifiedContent;
      if(!ReadFileTextAtPath(relativePath,verifiedContent) || verifiedContent!=content)
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Pending snapshot write verification failed");

      return CVoidResult::Ok();
     }

   CVoidResult       PromoteTempToActive(void) const
     {
      string tempPath=TempPath();
      ResetLastError();
      if(FileMove(tempPath,0,m_filePath,FILE_REWRITE))
         return CVoidResult::Ok();

      if(!FileCopy(tempPath,0,m_filePath,FILE_REWRITE))
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to promote pending snapshot temp file");

      FileDelete(tempPath);
      return CVoidResult::Ok();
     }

   CVoidResult       RecoverActiveFromBackup(void) const
     {
      string backupPath=BackupPath();
      if(!FileCopy(backupPath,0,m_filePath,FILE_REWRITE))
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to recover pending snapshot from backup");
      return CVoidResult::Ok();
     }

   CVoidResult       RefreshBackupFromActive(void) const
     {
      if(!FileIsExist(m_filePath))
         return CVoidResult::Ok();

      string activeContent;
      if(!ReadFileText(activeContent) || !TryValidateSnapshotContent(activeContent))
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Active pending snapshot is not backupable");

      string backupPath=BackupPath();
      FileDelete(backupPath);
      if(!FileCopy(m_filePath,0,backupPath,FILE_REWRITE))
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to refresh pending snapshot backup");

      return CVoidResult::Ok();
     }

   CVoidResult       BackupValidActiveSnapshot(void) const
     {
      if(!FileIsExist(m_filePath))
         return CVoidResult::Ok();

      string activeContent;
      if(!ReadFileText(activeContent) || !TryValidateSnapshotContent(activeContent))
         return CVoidResult::Ok();

      string backupPath=BackupPath();
      FileDelete(backupPath);
      if(!FileCopy(m_filePath,0,backupPath,FILE_REWRITE))
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to backup pending snapshot");

      return CVoidResult::Ok();
     }

   CVoidResult       WriteSnapshotAtomic(const string content) const
     {
      CVoidResult directoryResult=EnsureDirectoryChain(m_filePath);
      if(directoryResult.IsFail())
         return directoryResult;

      string tempPath=TempPath();

      if(FileIsExist(tempPath))
         FileDelete(tempPath);

      CVoidResult tempWrite=WriteSnapshotFile(tempPath,content);
      if(tempWrite.IsFail())
        {
         FileDelete(tempPath);
         return tempWrite;
        }

      CVoidResult backupResult=BackupValidActiveSnapshot();
      if(backupResult.IsFail())
        {
         FileDelete(tempPath);
         return backupResult;
        }

      CVoidResult promoteResult=PromoteTempToActive();
      if(promoteResult.IsFail())
         return promoteResult;

      string verifiedActive;
      if(!ReadFileText(verifiedActive) || verifiedActive!=content || !TryValidateSnapshotContent(verifiedActive))
        {
         if(FileIsExist(BackupPath()))
            RecoverActiveFromBackup();
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Pending snapshot active verification failed");
        }

      if(FileIsExist(tempPath))
         FileDelete(tempPath);

      return RefreshBackupFromActive();
     }

public:
                     CFilePendingExecutionStore(const string filePath)
     {
      m_filePath=filePath;
      m_lastRestoreOutcome="";
     }

   static string     BuildMarker(void) { return BRE_FILE_PENDING_EXECUTION_STORE_BUILD_MARKER; }

   string            FileRelativePath(void) const { return m_filePath; }

   string            LastRestoreOutcome(void) const { return m_lastRestoreOutcome; }

   CVoidResult       RestoreFromDisk(void)
     {
      m_lastRestoreOutcome="";

      string activeContent;
      if(ReadFileText(activeContent) && TryValidateSnapshotContent(activeContent))
        {
         ImportSnapshotContent(activeContent);
         m_lastRestoreOutcome=BRE_PENDING_RESTORE_OUTCOME_ACTIVE;
         return CVoidResult::Ok();
        }

      string tempContent;
      if(ReadFileTextAtPath(TempPath(),tempContent) && TryValidateSnapshotContent(tempContent))
        {
         CVoidResult promoted=PromoteTempToActive();
         if(promoted.IsFail())
            return CVoidResult::Fail(BRE_ERR_PERSIST_READ_FAILED,"Failed to recover pending snapshot from temp file");

         string verifiedActive;
         if(!ReadFileText(verifiedActive) || verifiedActive!=tempContent)
            return CVoidResult::Fail(BRE_ERR_PERSIST_READ_FAILED,"Pending snapshot temp recovery verification failed");

         ImportSnapshotContent(tempContent);
         m_lastRestoreOutcome=BRE_PENDING_RESTORE_OUTCOME_TEMP;
         return CVoidResult::Ok();
        }

      string backupContent;
      if(ReadFileTextAtPath(BackupPath(),backupContent) && TryValidateSnapshotContent(backupContent))
        {
         CVoidResult recovered=RecoverActiveFromBackup();
         if(recovered.IsFail())
            return CVoidResult::Fail(BRE_ERR_PERSIST_READ_FAILED,"Failed to recover pending snapshot from backup file");

         string verifiedActive;
         if(!ReadFileText(verifiedActive) || verifiedActive!=backupContent)
            return CVoidResult::Fail(BRE_ERR_PERSIST_READ_FAILED,"Pending snapshot backup recovery verification failed");

         ImportSnapshotContent(backupContent);
         m_lastRestoreOutcome=BRE_PENDING_RESTORE_OUTCOME_BACKUP;
         return CVoidResult::Ok();
        }

      if(!HasAnySnapshotArtifact())
         return InitializePristineEmptyStore();

      return CVoidResult::Fail(BRE_ERR_PERSIST_READ_FAILED,"Pending execution snapshot is corrupt and not recoverable");
     }

   int               CountPersistedEntriesOnDisk(void) const
     {
      string content;
      if(!ReadFileText(content) || !TryValidateSnapshotContent(content))
         return 0;
      string sections[];
      int sectionCount=StringSplit(content,'\f',sections);
      if(sectionCount<1 || sections[0]=="")
         return 0;
      string lines[];
      return StringSplit(sections[0],'\n',lines);
     }

   virtual CVoidResult Clear(void)
     {
      CVoidResult cleared=CInMemoryPendingExecutionStore::Clear();
      if(cleared.IsFail())
         return cleared;
      CVoidResult persisted=WriteSnapshotAtomic("");
      if(persisted.IsFail())
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to clear persisted pending execution store");
      return CVoidResult::Ok();
     }

   virtual CVoidResult SavePreparedState(const CPendingExecutionEntry &entry,
                                         const CBrokerSubmissionEnvelope &envelope)
     {
      CVoidResult saved=CInMemoryPendingExecutionStore::SavePreparedState(entry,envelope);
      if(saved.IsFail())
         return saved;

      string payload=ExportEntriesText()+"\f"+ExportEnvelopesText();
      CVoidResult persisted=WriteSnapshotAtomic(payload);
      if(persisted.IsFail())
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to persist pending execution store");
      return CVoidResult::Ok();
     }

   virtual CVoidResult SaveEntryState(const CPendingExecutionEntry &entry)
     {
      CVoidResult saved=CInMemoryPendingExecutionStore::SaveEntryState(entry);
      if(saved.IsFail())
         return saved;

      string payload=ExportEntriesText()+"\f"+ExportEnvelopesText();
      CVoidResult persisted=WriteSnapshotAtomic(payload);
      if(persisted.IsFail())
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to persist pending execution entry state");
      return CVoidResult::Ok();
     }
  };

#endif
