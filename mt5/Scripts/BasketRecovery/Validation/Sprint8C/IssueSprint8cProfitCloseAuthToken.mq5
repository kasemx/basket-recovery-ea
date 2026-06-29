#property script_show_inputs
#property description "Sprint 8C: issue manual profit-close authorization token from live candidate artifact."

#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Validation/Sprint8C/ManualProfitCloseCandidateValidationArtifact.mqh>

input int InpAuthorizationTokenExpirySeconds = 3600;

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

void OnStart(void)
  {
   string reportRel="BasketRecovery/validation/sprint-8c-auth-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      return;

   string candidateId=ReadArtifactValue("candidate_id");
   string executionRequestId=ReadArtifactValue("execution_request_id");
   string basketId=ReadArtifactValue("basket_id");
   string symbol=ReadArtifactValue("symbol");
   string strategyHash=ReadArtifactValue("strategy_profile_hash");
   string basketVersion=ReadArtifactValue("basket_version");
   string volume=ReadArtifactValue("proposed_close_volume");

   if(candidateId=="" || executionRequestId=="" || basketId=="")
     {
      WriteLine(reportHandle,"auth_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Live candidate artifact missing");
      FileClose(reportHandle);
      return;
     }

   datetime expiry=TimeCurrent()+InpAuthorizationTokenExpirySeconds;
   string fingerprint=CExecutionAuthorizationToken::ComputeBindingFingerprint(executionRequestId,
                                                                              CBasketId(basketId),
                                                                              symbol,
                                                                              BRE_EXEC_INTENT_CLOSE_POSITION,
                                                                              StringToDouble(volume),
                                                                              (int)StringToInteger(basketVersion),
                                                                              strategyHash);
   string authToken=CExecutionAuthorizationToken::IssuePlaintextToken(fingerprint,expiry);

   WriteLine(reportHandle,"candidate_id="+candidateId);
   WriteLine(reportHandle,"execution_request_id="+executionRequestId);
   WriteLine(reportHandle,"basket_id="+basketId);
   WriteLine(reportHandle,"authorization_token="+authToken);
   WriteLine(reportHandle,"authorization_token_expiry="+IntegerToString((long)expiry));
   WriteLine(reportHandle,"auth_verification=OK");
   FileClose(reportHandle);
  }
