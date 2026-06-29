#property script_show_inputs
#property description "Read-only pending execution reconciliation proof (no broker mutation, no persistence writes)."

#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionQuery.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Application/Execution/ExecutionReconciliationResolver.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/Mt5BrokerPositionReader.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionReconciliationHydrator.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/Mt5BrokerExecutionHistoryReader.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/Mt5ReconciliationHistoryLookupDiagnostic.mqh>

input string InpPendingRelativePath = "BasketRecovery/pending_executions.dat";
input string InpReportRelativePath = "BasketRecovery/validation/pending-reconciliation-proof.txt";

bool IsTargetRecord(const string executionRequestId)
  {
   return executionRequestId=="recovery-manual:375360093-3A70-2EF6" ||
          executionRequestId=="sprint6g-req-001" ||
          executionRequestId=="sprint7d-blocker-req-001";
  }

string            ProofOutputAbsolutePath(void)
  {
   string commonRoot=TerminalInfoString(TERMINAL_COMMONDATA_PATH);
   if(StringLen(commonRoot)>0 && StringGetCharacter(commonRoot,StringLen(commonRoot)-1)!='\\')
      commonRoot+="\\";
   return commonRoot+"Files\\"+InpReportRelativePath;
  }

bool              EnsureProofFolders(void)
  {
   ResetLastError();
   if(!FolderCreate("BasketRecovery",FILE_COMMON))
     {
      int err=GetLastError();
      if(err!=5019 && err!=0)
         return false;
     }
   ResetLastError();
   if(!FolderCreate("BasketRecovery\\validation",FILE_COMMON))
     {
      int err=GetLastError();
      if(err!=5019 && err!=0)
         return false;
     }
   return true;
  }

long              PendingFileSizeBytes(const string relativePath)
  {
   if(!FileIsExist(relativePath,FILE_COMMON))
     {
      if(!FileIsExist(relativePath,0))
         return -1;
      int localHandle=FileOpen(relativePath,FILE_READ|FILE_BIN);
      if(localHandle==INVALID_HANDLE)
         return -1;
      long localSize=FileSize(localHandle);
      FileClose(localHandle);
      return localSize;
     }
   int handle=FileOpen(relativePath,FILE_READ|FILE_BIN|FILE_COMMON);
   if(handle==INVALID_HANDLE)
      return -1;
   long size=FileSize(handle);
   FileClose(handle);
   return size;
  }

void              WriteLine(const int handle,const string line)
  {
   if(handle!=INVALID_HANDLE)
      FileWriteString(handle,line+"\r\n");
   Print(line);
  }

void              WriteFailedProof(const string errorMessage)
  {
   if(!EnsureProofFolders())
     {
      Print("status=FAILED | error=",errorMessage," | folder_create_failed=",IntegerToString(GetLastError()));
      return;
     }

   int handle=FileOpen(InpReportRelativePath,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle==INVALID_HANDLE)
     {
      Print("status=FAILED | error=",errorMessage," | report_open_failed=",IntegerToString(GetLastError()));
      return;
     }

   WriteLine(handle,"status=STARTED");
   WriteLine(handle,"timestamp_utc="+IntegerToString((long)TimeGMT()));
   WriteLine(handle,"proof_output_path="+ProofOutputAbsolutePath());
   WriteLine(handle,"status=FAILED");
   WriteLine(handle,"error="+errorMessage);
   FileClose(handle);
  }

void              OnStart(void)
  {
   Print("InspectPendingExecutionReconciliation | read_only_proof_start");

   if(!EnsureProofFolders())
     {
      WriteFailedProof("proof_folder_create_failed:"+IntegerToString(GetLastError()));
      return;
     }

   int reportHandle=FileOpen(InpReportRelativePath,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
     {
      WriteFailedProof("proof_report_open_failed:"+IntegerToString(GetLastError()));
      return;
     }

   WriteLine(reportHandle,"status=STARTED");
   WriteLine(reportHandle,"timestamp_utc="+IntegerToString((long)TimeGMT()));
   WriteLine(reportHandle,"proof_output_path="+ProofOutputAbsolutePath());
   WriteLine(reportHandle,"validation_stage=read_only_reconciliation_proof");
   WriteLine(reportHandle,"broker_mutation_performed=false");
   WriteLine(reportHandle,"terminal_data_path="+TerminalInfoString(TERMINAL_DATA_PATH));
   WriteLine(reportHandle,"terminal_common_data_path="+TerminalInfoString(TERMINAL_COMMONDATA_PATH));

   long pendingBytesBefore=PendingFileSizeBytes(InpPendingRelativePath);
   WriteLine(reportHandle,"pending_file_bytes_before="+IntegerToString(pendingBytesBefore));

   CMt5BrokerPositionReader *positionReader=new CMt5BrokerPositionReader();
   CMt5BrokerExecutionHistoryReader *historyReader=new CMt5BrokerExecutionHistoryReader();
   CFilePendingExecutionStore *store=new CFilePendingExecutionStore(InpPendingRelativePath);
   store.RestoreFromDisk();

   CPendingExecutionEntry entries[];
   int total=store.RestoreEntries(entries);
   datetime nowUtc=TimeCurrent();
   int evaluated=0;

   for(int i=0;i<total;i++)
     {
      if(!IsTargetRecord(entries[i].ExecutionRequestId()))
         continue;

      CPendingExecutionEntry entry=entries[i];
      string persistedStatus=TradeExecutionStatusLabel(entry.Status());
      CPendingExecutionReconciliationHydrator::TryHydrate(entry,store);

      CMt5ReconciliationHistoryLookupDiagnostic::TraceRecord(reportHandle,entry,nowUtc);

      double matchedVolume=0.0;
      CExecutionReconciliationReport report;
      ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
         CExecutionReconciliationResolver::ResolveWithReport(entry,positionReader,matchedVolume,historyReader,nowUtc,report);

      evaluated++;
      WriteLine(reportHandle,"record["+IntegerToString(evaluated)+"]="
                            +"execution_request_id="+entry.ExecutionRequestId()
                            +" | persisted_status_before="+persistedStatus
                            +" | current_open_state="+report.CurrentOpenState()
                            +" | history_correlation_state="+report.HistoryCorrelationState()
                            +" | stamp_candidate_count="+IntegerToString(report.StampCandidateCount())
                            +" | fingerprint_candidate_count="+IntegerToString(report.FingerprintCandidateCount())
                            +" | order_filled_candidate_count="+IntegerToString(report.OrderFilledCandidateCount())
                            +" | evidence_method="+report.EvidenceMethod()
                            +" | final_proposed_state="+TradeExecutionStatusLabel(resolved)
                            +" | matched_volume="+DoubleToString(matchedVolume,8)
                            +" | confidence="+report.Confidence()
                            +" | startup_mutation_permitted="+(report.MutationPermitted()?"true":"false"));
     }

   long pendingBytesAfter=PendingFileSizeBytes(InpPendingRelativePath);
   WriteLine(reportHandle,"pending_file_bytes_after="+IntegerToString(pendingBytesAfter));
   WriteLine(reportHandle,"pending_file_unchanged="+((pendingBytesBefore==pendingBytesAfter)?"true":"false"));
   WriteLine(reportHandle,"records_evaluated="+IntegerToString(evaluated));
   WriteLine(reportHandle,"status=COMPLETED");

   FileClose(reportHandle);
   delete store;
   delete historyReader;
   delete positionReader;
  }
