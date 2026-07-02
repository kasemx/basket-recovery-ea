#property script_show_inputs
#property description "Sprint 8C: issue manual profit-close authorization token from live candidate artifact."

#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>
#include <BasketRecovery/Domain/Execution/ProfitCloseAuthorizationBinding.mqh>
#include <BasketRecovery/Validation/Sprint8C/ManualProfitCloseCandidateValidationArtifact.mqh>
#include <BasketRecovery/Validation/Sprint8C/Sprint8cValidationProfile.mqh>

#define BRE_AUTH_ISSUE_SCRIPT_BUILD_MARKER "S8C_AUTH_ISSUE_SCRIPT_V2"

input string InpBasketId = "sprint8c-demo-xauusd-002";
input int    InpAuthorizationTokenExpirySeconds = 300;

void WriteLine(const int handle,const string line)
  {
   if(handle!=INVALID_HANDLE)
      FileWriteString(handle,line+"\r\n");
   Print(line);
  }

void WriteArtifactDiagnostics(const int reportHandle,const SSprint8cCandidateArtifactDiagnostics &diagnostics)
  {
   WriteLine(reportHandle,"candidate_artifact_store_path="+diagnostics.store_path);
   WriteLine(reportHandle,"candidate_artifact_key="+diagnostics.artifact_key);
   WriteLine(reportHandle,"candidate_artifact_found="+(diagnostics.found?"true":"false"));
   WriteLine(reportHandle,"candidate_artifact_created_at="+IntegerToString((long)diagnostics.created_at));
   WriteLine(reportHandle,"candidate_artifact_expires_at="+IntegerToString((long)diagnostics.expires_at));
   WriteLine(reportHandle,"candidate_artifact_execution_request_id="+diagnostics.execution_request_id);
   WriteLine(reportHandle,"candidate_artifact_ticket="+IntegerToString((long)diagnostics.ticket));
   WriteLine(reportHandle,"candidate_artifact_volume="+DoubleToString(diagnostics.volume,8));
   WriteLine(reportHandle,"candidate_artifact_validation="+diagnostics.validation);
   WriteLine(reportHandle,"candidate_artifact_failure_reason="+diagnostics.failure_reason);
   WriteLine(reportHandle,"candidate_artifact_expiry_remaining_seconds="+IntegerToString(diagnostics.expiry_remaining_seconds));
   WriteLine(reportHandle,"candidate_artifact_ttl_seconds="+IntegerToString(CManualProfitCloseCandidateValidationArtifact::DefaultArtifactTtlSeconds()));
   WriteLine(reportHandle,"auth_token_ttl_seconds="+IntegerToString(InpAuthorizationTokenExpirySeconds));
   WriteLine(reportHandle,"required_minimum_artifact_remaining_seconds="+IntegerToString(
      CManualProfitCloseCandidateValidationArtifact::ComputeRequiredMinimumArtifactRemainingSeconds(InpAuthorizationTokenExpirySeconds)));
   CManualProfitCloseCandidateValidationArtifact::LogDiagnostics(diagnostics);
   CManualProfitCloseCandidateValidationArtifact::PrintReuseEligibilityDiagnostics(diagnostics);
  }

void WriteValidationProfileMarkers(const int reportHandle)
  {
   CSprint8cValidationProfile::LogProfileMarkers();
   WriteLine(reportHandle,"validation_profile_version="+CSprint8cValidationProfile::ProfileVersionLabel());
   WriteLine(reportHandle,"validation_profile_id="+CSprint8cValidationProfile::ProfileId());
   WriteLine(reportHandle,"validation_profit_trigger_type="+CSprint8cValidationProfile::FloatingProfitTriggerTypeLabel());
   WriteLine(reportHandle,"validation_profit_trigger_value_usd="+DoubleToString(CSprint8cValidationProfile::FloatingProfitTriggerUsd(),2));
   WriteLine(reportHandle,"validation_require_floating_profit_positive=true");
  }

void OnStart(void)
  {
   string reportRel="BasketRecovery/validation/sprint-8c-auth-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      return;

   WriteValidationProfileMarkers(reportHandle);
   WriteLine(reportHandle,"auth_token_ttl_seconds="+IntegerToString(InpAuthorizationTokenExpirySeconds));
   WriteLine(reportHandle,"candidate_artifact_ttl_seconds="+IntegerToString(CManualProfitCloseCandidateValidationArtifact::DefaultArtifactTtlSeconds()));

   datetime nowUtc=TimeCurrent();
   SSprint8cCandidateArtifactRecord artifact;
   SSprint8cCandidateArtifactDiagnostics diagnostics;
   if(!CManualProfitCloseCandidateValidationArtifact::TryLoadAndValidate(InpBasketId,0,nowUtc,artifact,diagnostics,CManualProfitCloseCandidateValidationArtifact::DefaultRelativePath(),InpAuthorizationTokenExpirySeconds))
     {
      WriteArtifactDiagnostics(reportHandle,diagnostics);
      WriteLine(reportHandle,"auth_verification=FAIL");
      if(diagnostics.failure_reason=="")
         WriteLine(reportHandle,"failure_reason=Live candidate artifact missing");
      else
         WriteLine(reportHandle,"failure_reason="+diagnostics.failure_reason);
      FileClose(reportHandle);
      return;
     }

   WriteArtifactDiagnostics(reportHandle,diagnostics);

   datetime expiry=nowUtc+InpAuthorizationTokenExpirySeconds;
   string fingerprint=CProfitCloseAuthorizationBinding::ComputeBindingHash(artifact.basket_id,
                                                                           artifact.candidate_id,
                                                                           artifact.execution_request_id,
                                                                           artifact.position_ticket,
                                                                           artifact.requested_close_volume);
   CProfitCloseAuthorizationBinding::PrintIssueBindingDiagnostics(BRE_AUTH_ISSUE_SCRIPT_BUILD_MARKER,
                                                             artifact.basket_id,
                                                             artifact.candidate_id,
                                                             artifact.execution_request_id,
                                                             artifact.position_ticket,
                                                             artifact.requested_close_volume);
   string authToken=CExecutionAuthorizationToken::IssuePlaintextToken(fingerprint,expiry);

   WriteLine(reportHandle,"auth_issue_runtime_build_marker="+BRE_AUTH_ISSUE_SCRIPT_BUILD_MARKER);
   WriteLine(reportHandle,"auth_binding_build_marker="+CProfitCloseAuthorizationBinding::BuildMarker());

   WriteLine(reportHandle,"candidate_id="+artifact.candidate_id);
   WriteLine(reportHandle,"execution_request_id="+artifact.execution_request_id);
   WriteLine(reportHandle,"basket_id="+artifact.basket_id);
   WriteLine(reportHandle,"position_ticket="+IntegerToString((long)artifact.position_ticket));
   WriteLine(reportHandle,"requested_close_volume="+DoubleToString(artifact.requested_close_volume,8));
   WriteLine(reportHandle,"authorization_token="+authToken);
   WriteLine(reportHandle,"authorization_token_expiry="+IntegerToString((long)expiry));
   WriteLine(reportHandle,"auth_verification=OK");
   FileClose(reportHandle);
  }
