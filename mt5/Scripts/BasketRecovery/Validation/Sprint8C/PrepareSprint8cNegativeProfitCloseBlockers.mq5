#property script_show_inputs
#property description "Sprint 8C: force expired candidate or invalid volume for negative profit-close tests."

#include <BasketRecovery/Validation/Sprint8C/ManualProfitCloseCandidateValidationArtifact.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateRegistry.mqh>

input string InpMode = "EXPIRED";
input string InpBasketId = "sprint8c-neg-expiry-001";

void WriteLine(const int handle,const string line)
  {
   if(handle!=INVALID_HANDLE)
      FileWriteString(handle,line+"\r\n");
   Print(line);
  }

string ReadArtifactValue(const string key)
  {
   int handle=FileOpen(CManualProfitCloseCandidateValidationArtifact::DefaultRelativePath(),
                       FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle==INVALID_HANDLE)
      return "";
   string prefix=key+"=";
   while(!FileIsEnding(handle))
     {
      string line=FileReadString(handle);
      if(StringFind(line,prefix)==0)
        {
         FileClose(handle);
         return StringSubstr(line,StringLen(prefix));
        }
     }
   FileClose(handle);
   return "";
  }

bool PatchArtifactField(const string key,const string value)
  {
   int readHandle=FileOpen(CManualProfitCloseCandidateValidationArtifact::DefaultRelativePath(),
                           FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(readHandle==INVALID_HANDLE)
      return false;
   string lines[];
   int count=0;
   while(!FileIsEnding(readHandle))
     {
      ArrayResize(lines,count+1);
      lines[count]=FileReadString(readHandle);
      count++;
     }
   FileClose(readHandle);

   int writeHandle=FileOpen(CManualProfitCloseCandidateValidationArtifact::DefaultRelativePath(),
                            FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(writeHandle==INVALID_HANDLE)
      return false;
   string prefix=key+"=";
   for(int i=0;i<count;i++)
     {
      if(StringFind(lines[i],prefix)==0)
         FileWriteString(writeHandle,prefix+value+"\r\n");
      else
         FileWriteString(writeHandle,lines[i]+"\r\n");
     }
   FileClose(writeHandle);
   return true;
  }

void OnStart(void)
  {
   string reportRel="BasketRecovery/validation/sprint-8c-negative-prep-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      return;

   WriteLine(reportHandle,"mode="+InpMode);
   WriteLine(reportHandle,"basket_id="+InpBasketId);

   if(InpMode=="EXPIRED")
     {
      datetime expiredAt=TimeCurrent()-120;
      if(!PatchArtifactField("expires_at_utc",IntegerToString((long)expiredAt)))
        {
         WriteLine(reportHandle,"negative_prep_verification=FAIL");
         WriteLine(reportHandle,"failure_reason=Could not patch candidate expiry");
         FileClose(reportHandle);
         return;
        }
      PatchArtifactField("candidate_status","EXPIRED_NEGATIVE_TEST");
      CManualProfitCloseCandidateRegistry registry;
      registry.Clear();
      if(!CManualProfitCloseCandidateValidationArtifact::TryRestoreToRegistry(registry))
        {
         WriteLine(reportHandle,"negative_prep_verification=FAIL");
         WriteLine(reportHandle,"failure_reason=Could not restore expired candidate");
         FileClose(reportHandle);
         return;
        }
      WriteLine(reportHandle,"expires_at_utc="+IntegerToString((long)expiredAt));
      WriteLine(reportHandle,"negative_prep_verification=OK");
     }
   else if(InpMode=="STALE_VOLUME")
     {
      string originalVolume=ReadArtifactValue("original_position_volume");
      double excessive=StringToDouble(originalVolume)+1.0;
      if(!PatchArtifactField("proposed_close_volume",DoubleToString(excessive,8)))
        {
         WriteLine(reportHandle,"negative_prep_verification=FAIL");
         WriteLine(reportHandle,"failure_reason=Could not patch proposed close volume");
         FileClose(reportHandle);
         return;
        }
      WriteLine(reportHandle,"patched_proposed_close_volume="+DoubleToString(excessive,8));
      WriteLine(reportHandle,"negative_prep_verification=OK");
     }
   else
     {
      WriteLine(reportHandle,"negative_prep_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Unknown mode");
     }

   FileClose(reportHandle);
  }
