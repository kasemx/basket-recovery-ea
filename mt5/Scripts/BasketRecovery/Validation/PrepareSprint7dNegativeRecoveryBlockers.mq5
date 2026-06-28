#property script_show_inputs
#property description "Sprint 7D: force expired candidate or pending execution blocker for negative tests."

#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateValidationArtifact.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateRegistry.mqh>
#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionEnvelope.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>

input string InpMode = "EXPIRED";
input string InpBasketId = "sprint7d-neg-expiry-001";

void WriteLine(const int handle,const string line)
  {
   if(handle!=INVALID_HANDLE)
      FileWriteString(handle,line+"\r\n");
   Print(line);
  }

string ReadArtifactValue(const string key)
  {
   int handle=FileOpen(CManualRecoveryCandidateValidationArtifact::DefaultRelativePath(),
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

bool PatchArtifactExpiry(const datetime expiredAtUtc)
  {
   int readHandle=FileOpen(CManualRecoveryCandidateValidationArtifact::DefaultRelativePath(),
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

   int writeHandle=FileOpen(CManualRecoveryCandidateValidationArtifact::DefaultRelativePath(),
                            FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(writeHandle==INVALID_HANDLE)
      return false;
   for(int i=0;i<count;i++)
     {
      if(StringFind(lines[i],"expires_at_utc=")==0)
         FileWriteString(writeHandle,"expires_at_utc="+IntegerToString((long)expiredAtUtc)+"\r\n");
      else if(StringFind(lines[i],"candidate_status=")==0)
         FileWriteString(writeHandle,"candidate_status=EXPIRED_NEGATIVE_TEST\r\n");
      else
         FileWriteString(writeHandle,lines[i]+"\r\n");
     }
   FileClose(writeHandle);
   return true;
  }

void ForcePendingBlocker(const string basketId,
                         const string symbol,
                         const string strategyHash,
                         const int basketVersion)
  {
   CFilePendingExecutionStore *store=new CFilePendingExecutionStore("BasketRecovery/pending_executions.dat");
   store.RestoreFromDisk();

   double volume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   if(volume<=0.0)
      volume=0.01;
   datetime nowUtc=TimeCurrent();

   CPendingExecutionEntry entry;
   entry.SetExecutionRequestId("sprint7d-blocker-req-001");
   entry.SetIdempotencyKey("sprint7d-blocker-key-001");
   entry.SetBasketId(CBasketId(basketId));
   entry.SetSymbol(symbol);
   entry.SetIntentType(BRE_EXEC_INTENT_OPEN_POSITION);
   entry.SetRequestedVolume(volume);
   entry.SetExpectedBasketVersion(basketVersion);
   entry.SetStrategyProfileHash(strategyHash);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_SUBMITTED);
   entry.SetCreatedAtUtc(nowUtc);
   entry.SetSubmittedAtUtc(nowUtc);
   entry.SetPreparedAtUtc(nowUtc);
   entry.SetBrokerComment("BRE|blocker|pending|test");
   entry.SetCorrelationToken("corr-blocker");

   CBrokerSubmissionEnvelope envelope;
   envelope.SetExecutionRequestId(entry.ExecutionRequestId());
   envelope.SetIdempotencyKey(entry.IdempotencyKey());
   envelope.SetBasketId(entry.BasketId());
   envelope.SetSymbol(symbol);
   envelope.SetIntentType(BRE_EXEC_INTENT_OPEN_POSITION);
   envelope.SetRequestedVolume(volume);
   envelope.SetBrokerComment(entry.BrokerComment());
   envelope.SetCorrelationToken(entry.CorrelationToken());
   envelope.SetPreparedAtUtc(nowUtc);
   envelope.SetExpirationUtc(nowUtc+3600);
   envelope.SetExpectedBasketVersion(basketVersion);
   envelope.SetStrategyProfileHash(strategyHash);

   store.SavePreparedState(entry,envelope);
   WriteLine(INVALID_HANDLE,"pending_blocker_written=true");
   WriteLine(INVALID_HANDLE,"pending_blocker_basket_id="+basketId);
   delete store;
  }

void OnStart(void)
  {
   string reportRel="BasketRecovery/validation/sprint-7d-negative-prep-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      return;

   string basketId=ReadArtifactValue("basket_id");
   if(basketId=="")
      basketId=InpBasketId;
   string symbol=ReadArtifactValue("symbol");
   string strategyHash=ReadArtifactValue("strategy_profile_hash");
   int basketVersion=(int)StringToInteger(ReadArtifactValue("basket_version"));

   WriteLine(reportHandle,"mode="+InpMode);
   WriteLine(reportHandle,"basket_id="+basketId);

   if(InpMode=="EXPIRED")
     {
      datetime expiredAt=TimeCurrent()-120;
      if(!PatchArtifactExpiry(expiredAt))
        {
         WriteLine(reportHandle,"negative_prep_verification=FAIL");
         WriteLine(reportHandle,"failure_reason=Could not patch candidate artifact expiry");
         FileClose(reportHandle);
         return;
        }
      CManualRecoveryCandidateRegistry registry;
      registry.Clear();
      if(!CManualRecoveryCandidateValidationArtifact::TryRestoreToRegistry(registry))
        {
         WriteLine(reportHandle,"negative_prep_verification=FAIL");
         WriteLine(reportHandle,"failure_reason=Could not restore expired candidate to registry");
         FileClose(reportHandle);
         return;
        }
      WriteLine(reportHandle,"expires_at_utc="+IntegerToString((long)expiredAt));
      WriteLine(reportHandle,"negative_prep_verification=OK");
     }
   else if(InpMode=="PENDING")
     {
      if(symbol=="" || strategyHash=="")
        {
         WriteLine(reportHandle,"negative_prep_verification=FAIL");
         WriteLine(reportHandle,"failure_reason=Candidate artifact missing symbol/hash");
         FileClose(reportHandle);
         return;
        }
      ForcePendingBlocker(basketId,symbol,strategyHash,basketVersion);
      WriteLine(reportHandle,"negative_prep_verification=OK");
     }
   else
     {
      WriteLine(reportHandle,"negative_prep_verification=FAIL");
      WriteLine(reportHandle,"failure_reason=Unknown mode");
     }

   FileClose(reportHandle);
  }
