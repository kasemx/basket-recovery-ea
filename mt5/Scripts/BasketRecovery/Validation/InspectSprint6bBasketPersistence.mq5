#property script_show_inputs
#property description "Sprint 6B.3: inspect sprint6b basket persistence file and CRC path."

#include <BasketRecovery/Infrastructure/Persistence/BasketPersistenceLoadDiagnostic.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>

input string InpBasketId = "sprint6b-demo-btc-001";

void WriteLine(const int handle,const string line)
  {
   if(handle!=INVALID_HANDLE)
      FileWriteString(handle,line+"\r\n");
   Print(line);
  }

void OnStart()
  {
   CBasketId basketId(InpBasketId);
   CFileBasketRepository repository(BRE_PERSISTENCE_BASKET_SUBDIR);
   CBasketPersistenceLoadDiagnostic report=
      CBasketPersistenceLoadDiagnostic::Inspect(BRE_PERSISTENCE_BASKET_SUBDIR,basketId,repository);

   FolderCreate("BasketRecovery\\validation",FILE_COMMON);
   string reportRel="BasketRecovery\\validation\\sprint-6b-basket-inspect-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI);

   WriteLine(reportHandle,"=== Sprint 6B.3 Basket Persistence Inspect ===");
   WriteLine(reportHandle,"timestamp="+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
   WriteLine(reportHandle,CBasketPersistenceLoadDiagnostic::FormatLogLine(report));
   WriteLine(reportHandle,"common_data_path="+report.commonDataPath);
   WriteLine(reportHandle,"relative_file_path="+report.relativeFilePath);
   WriteLine(reportHandle,"file_exists_common="+(report.fileExistsCommon?"true":"false"));
   WriteLine(reportHandle,"file_exists_terminal_local="+(report.fileExistsTerminalLocal?"true":"false"));
   WriteLine(reportHandle,"repository_error_message="+report.repositoryErrorMessage);
   WriteLine(reportHandle,"root_cause="+report.failureClassification);

   string rawContent=CBasketPersistenceLoadDiagnostic::ReadFileContentRaw(report.relativeFilePath,true);
   if(rawContent!="")
     {
      WriteLine(reportHandle,"raw_content_len="+IntegerToString(StringLen(rawContent)));
      WriteLine(reportHandle,"raw_content_head="+StringSubstr(rawContent,0,MathMin(240,StringLen(rawContent))));
     }
   else
     {
      WriteLine(reportHandle,"raw_content_head=UNAVAILABLE");
     }

   if(reportHandle!=INVALID_HANDLE)
      FileClose(reportHandle);
  }
