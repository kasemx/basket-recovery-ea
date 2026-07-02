#property script_show_inputs
#property description "Sprint 8D: DRY_RUN preflight for fresh isolated demo basket bootstrap. No writes, orders, or tokens."

const string RETIRED_BASKET_ID="sprint8c-demo-xauusd-002";
const ulong RETIRED_TICKET_A=1516350243;
const ulong RETIRED_TICKET_B=1516503131;

input string InpBasketId="";
input ulong  InpPositionTicket=0;
input double InpCurrentRemainingVolume=0.0;
input string InpSymbol="XAUUSD";
input string InpStrategyProfileHash="";
input long   InpBasketVersion=0;
input ulong  InpQuoteSequence=0;
input bool   InpM1CompletedOperatorAttestation=false;
input bool   InpM2ReachedOperatorAttestation=false;
input bool   InpNoUnresolvedPendingOperatorAttestation=false;
input string InpUseFreshArtifactPath="BasketRecovery/validation/sprint-8d-live-candidate.txt";
input bool   InpDryRunOnly=true;

void PrintLine(const string line)
  {
   Print(line);
  }

bool FieldContainsRetiredIdentifier(const string value,string &matchedOut)
  {
   matchedOut="";
   if(value==RETIRED_BASKET_ID)
     {
      matchedOut=RETIRED_BASKET_ID;
      return true;
     }
   if(StringFind(value,RETIRED_BASKET_ID)>=0)
     {
      matchedOut=RETIRED_BASKET_ID;
      return true;
     }
   if(StringFind(value,IntegerToString((long)RETIRED_TICKET_A))>=0)
     {
      matchedOut=IntegerToString((long)RETIRED_TICKET_A);
      return true;
     }
   if(StringFind(value,IntegerToString((long)RETIRED_TICKET_B))>=0)
     {
      matchedOut=IntegerToString((long)RETIRED_TICKET_B);
      return true;
     }
   return false;
  }

bool DetectOldSprint8cStateReuse(string &matchedIdentifierOut)
  {
   matchedIdentifierOut="";
   string matched="";

   if(InpBasketId==RETIRED_BASKET_ID)
     {
      matchedIdentifierOut=RETIRED_BASKET_ID;
      return true;
     }
   if(InpPositionTicket==RETIRED_TICKET_A || InpPositionTicket==RETIRED_TICKET_B)
     {
      matchedIdentifierOut=IntegerToString((long)InpPositionTicket);
      return true;
     }

   if(FieldContainsRetiredIdentifier(InpBasketId,matched))
     {
      matchedIdentifierOut=matched;
      return true;
     }
   if(FieldContainsRetiredIdentifier(InpSymbol,matched))
     {
      matchedIdentifierOut=matched;
      return true;
     }
   if(FieldContainsRetiredIdentifier(InpStrategyProfileHash,matched))
     {
      matchedIdentifierOut=matched;
      return true;
     }
   if(FieldContainsRetiredIdentifier(InpUseFreshArtifactPath,matched))
     {
      matchedIdentifierOut=matched;
      return true;
     }
   return false;
  }

bool ArtifactPathContainsRetiredLiveCandidatePath(const string artifactPath)
  {
   return StringFind(artifactPath,"sprint-8c-live-candidate")>=0;
  }

bool RunBootstrapPreflight(string &failureReasonOut,bool &oldStateReuseDetectedOut,string &matchedIdentifierOut)
  {
   failureReasonOut="";
   oldStateReuseDetectedOut=false;
   matchedIdentifierOut="";

   if(!InpDryRunOnly)
     {
      failureReasonOut="InpDryRunOnly must remain true; this script has no write mode";
      return false;
     }

   if(InpBasketId=="")
     {
      failureReasonOut="Basket id empty";
      return false;
     }
   if(InpBasketId==RETIRED_BASKET_ID)
     {
      oldStateReuseDetectedOut=true;
      matchedIdentifierOut=RETIRED_BASKET_ID;
      failureReasonOut="Basket id equals retired Sprint 8C basket sprint8c-demo-xauusd-002";
      return false;
     }
   if(InpPositionTicket<=0)
     {
      failureReasonOut="Position ticket must be greater than zero";
      return false;
     }
   if(InpPositionTicket==RETIRED_TICKET_A)
     {
      oldStateReuseDetectedOut=true;
      matchedIdentifierOut=IntegerToString((long)RETIRED_TICKET_A);
      failureReasonOut="Position ticket equals retired Sprint 8C ticket 1516350243";
      return false;
     }
   if(InpPositionTicket==RETIRED_TICKET_B)
     {
      oldStateReuseDetectedOut=true;
      matchedIdentifierOut=IntegerToString((long)RETIRED_TICKET_B);
      failureReasonOut="Position ticket equals retired Sprint 8C ticket 1516503131";
      return false;
     }
   if(InpCurrentRemainingVolume<=0.0)
     {
      failureReasonOut="Current remaining volume must be greater than zero";
      return false;
     }
   if(InpSymbol=="")
     {
      failureReasonOut="Symbol empty";
      return false;
     }
   if(InpStrategyProfileHash=="")
     {
      failureReasonOut="Strategy profile hash empty";
      return false;
     }
   if(InpBasketVersion<=0)
     {
      failureReasonOut="Basket version must be greater than zero";
      return false;
     }
   if(InpQuoteSequence<=0)
     {
      failureReasonOut="Quote sequence invalid";
      return false;
     }
   if(!InpM1CompletedOperatorAttestation)
     {
      failureReasonOut="M1 completed operator attestation is false";
      return false;
     }
   if(!InpM2ReachedOperatorAttestation)
     {
      failureReasonOut="M2 reached operator attestation is false";
      return false;
     }
   if(!InpNoUnresolvedPendingOperatorAttestation)
     {
      failureReasonOut="No-unresolved-pending operator attestation is false";
      return false;
     }
   if(InpUseFreshArtifactPath=="")
     {
      failureReasonOut="Artifact path empty";
      return false;
     }
   if(ArtifactPathContainsRetiredLiveCandidatePath(InpUseFreshArtifactPath))
     {
      oldStateReuseDetectedOut=true;
      matchedIdentifierOut="sprint-8c-live-candidate";
      failureReasonOut="Artifact path must not contain sprint-8c-live-candidate";
      return false;
     }

   if(DetectOldSprint8cStateReuse(matchedIdentifierOut))
     {
      oldStateReuseDetectedOut=true;
      failureReasonOut="Retired Sprint 8C identifier detected in supplied fields: "+matchedIdentifierOut;
      return false;
     }

   return true;
  }

void PrintBootstrapSummary(const bool preflightOk,
                           const string failureReason,
                           const bool oldStateReuseDetected)
  {
   PrintLine("sprint8d_bootstrap_mode=DRY_RUN");
   PrintLine("basket_id="+InpBasketId);
   PrintLine("position_ticket="+IntegerToString((long)InpPositionTicket));
   PrintLine("current_remaining_volume="+DoubleToString(InpCurrentRemainingVolume,8));
   PrintLine("symbol="+InpSymbol);
   PrintLine("strategy_profile_hash="+InpStrategyProfileHash);
   PrintLine("basket_version="+IntegerToString((int)InpBasketVersion));
   PrintLine("quote_sequence="+IntegerToString((long)InpQuoteSequence));
   PrintLine("m1_completed_operator_attestation="+(InpM1CompletedOperatorAttestation?"true":"false"));
   PrintLine("m2_reached_operator_attestation="+(InpM2ReachedOperatorAttestation?"true":"false"));
   PrintLine("no_unresolved_pending_operator_attestation="+(InpNoUnresolvedPendingOperatorAttestation?"true":"false"));
   PrintLine("planned_artifact_path="+InpUseFreshArtifactPath);
   PrintLine("old_sprint8c_state_reuse_detected="+(oldStateReuseDetected?"true":"false"));
   PrintLine("bootstrap_preflight_result="+(preflightOk?"PASS":"FAIL"));
   PrintLine("bootstrap_preflight_reason="+failureReason);
   if(preflightOk)
      PrintLine("next_safe_step=RUN_M2_ARTIFACT_DRY_RUN_ONLY");
   else
      PrintLine("next_safe_step=DO_NOT_CREATE_ARTIFACT_OR_TOKEN");
  }

void OnStart(void)
  {
   string failureReason="";
   bool oldStateReuseDetected=false;
   string matchedIdentifier="";
   bool preflightOk=RunBootstrapPreflight(failureReason,oldStateReuseDetected,matchedIdentifier);
   PrintBootstrapSummary(preflightOk,failureReason,oldStateReuseDetected);
  }
