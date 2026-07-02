#property script_show_inputs
#property description "Sprint 8D: dry-run or write M2 profit-close candidate artifact for D0E demo validation."

#include <BasketRecovery/Validation/Sprint8C/ManualProfitCloseCandidateValidationArtifact.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualProfitCloseCandidateEntry.mqh>
#include <BasketRecovery/Domain/Market/Enums/AccountPositionModel.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ProfitLevelTriggerType.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

input string InpBasketId="";
input string InpProfitLevelId="M2";
input int    InpProfitLevelIndex=1;
input string InpCandidateId="";
input string InpExecutionRequestId="";
input ulong  InpPositionTicket=0;
input double InpOriginalVolume=0.0;
input double InpRequestedCloseVolume=0.0;
input string InpSymbol="XAUUSD";
input string InpStrategyProfileHash="";
input long   InpBasketVersion=0;
input ulong  InpQuoteSequence=0;
input datetime InpCreatedAtUtc=0;
input datetime InpExpiresAtUtc=0;
input string InpPositionModel="hedging";
input bool   InpWriteArtifact=false;
input string InpArtifactPath="BasketRecovery/validation/sprint-8c-live-candidate.txt";

void PrintLine(const string line)
  {
   Print(line);
  }

bool TryParsePositionModel(const string value,ENUM_BRE_ACCOUNT_POSITION_MODEL &modelOut)
  {
   string normalized=value;
   StringToUpper(normalized);
   if(normalized=="HEDGING" || normalized=="hedging")
     {
      modelOut=BRE_ACCOUNT_POSITION_MODEL_HEDGING;
      return true;
     }
   if(normalized=="NETTING" || normalized=="netting")
     {
      modelOut=BRE_ACCOUNT_POSITION_MODEL_NETTING;
      return true;
     }
   modelOut=BRE_ACCOUNT_POSITION_MODEL_UNKNOWN;
   return normalized!="";
  }

bool CandidateIdMatchesM2Pattern(const string basketId,const string candidateId)
  {
   string expectedPrefix="profit-level-close:"+basketId+":level:M2:q:";
   if(StringFind(candidateId,expectedPrefix)!=0)
      return false;
   string suffix=StringSubstr(candidateId,StringLen(expectedPrefix));
   if(StringLen(suffix)==0)
      return false;
   for(int i=0;i<StringLen(suffix);i++)
     {
      ushort ch=StringGetCharacter(suffix,i);
      if(ch<'0' || ch>'9')
         return false;
     }
   return true;
  }

bool RunPreflight(const datetime createdAtUtc,
                  const datetime expiresAtUtc,
                  const datetime nowUtc,
                  const ENUM_BRE_ACCOUNT_POSITION_MODEL positionModel,
                  long &remainingTtlSecondsOut,
                  string &failureReasonOut)
  {
   failureReasonOut="";
   remainingTtlSecondsOut=0;

   if(InpBasketId=="")
     {
      failureReasonOut="Basket id empty";
      return false;
     }
   if(InpProfitLevelId!="M2")
     {
      failureReasonOut="Profit level id must be M2";
      return false;
     }
   if(!CandidateIdMatchesM2Pattern(InpBasketId,InpCandidateId))
     {
      failureReasonOut="Candidate id must match profit-level-close:<basket-id>:level:M2:q:<digits>";
      return false;
     }
   if(InpExecutionRequestId=="")
     {
      failureReasonOut="Execution request id empty";
      return false;
     }
   if(InpPositionTicket<=0)
     {
      failureReasonOut="Position ticket must be greater than zero";
      return false;
     }
   if(InpOriginalVolume<=0.0)
     {
      failureReasonOut="Original volume must be greater than zero";
      return false;
     }
   if(InpRequestedCloseVolume<=0.0)
     {
      failureReasonOut="Requested close volume must be greater than zero";
      return false;
     }
   if(InpRequestedCloseVolume>InpOriginalVolume)
     {
      failureReasonOut="Requested close volume must not exceed original volume";
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
   if(expiresAtUtc<=createdAtUtc)
     {
      failureReasonOut="expiresAtUtc must be greater than createdAtUtc";
      return false;
     }
   remainingTtlSecondsOut=(long)expiresAtUtc-(long)nowUtc;
   if(remainingTtlSecondsOut<=CManualProfitCloseCandidateValidationArtifact::ComputeRequiredMinimumArtifactRemainingSeconds(0))
     {
      failureReasonOut="Remaining artifact TTL must exceed required minimum (330 seconds)";
      return false;
     }
   if(!CAccountPositionModelHelper::SupportsExplicitTicketPartialClose(positionModel))
     {
      failureReasonOut="Position model is not explicit hedging-compatible";
      return false;
     }
   return true;
  }

CManualProfitCloseCandidateEntry BuildEntry(const datetime createdAtUtc,
                                            const datetime expiresAtUtc,
                                            const ENUM_BRE_ACCOUNT_POSITION_MODEL positionModel)
  {
   return CManualProfitCloseCandidateEntry::Create(InpCandidateId,
                                                   InpExecutionRequestId,
                                                   InpCandidateId,
                                                   CBasketId(InpBasketId),
                                                   InpProfitLevelId,
                                                   InpProfitLevelIndex,
                                                   InpStrategyProfileHash,
                                                   InpBasketVersion,
                                                   InpSymbol,
                                                   BRE_DIRECTION_BUY,
                                                   BRE_DIRECTION_SELL,
                                                   InpPositionTicket,
                                                   InpOriginalVolume,
                                                   InpRequestedCloseVolume,
                                                   1.0,
                                                   BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,
                                                   30.0,
                                                   InpQuoteSequence,
                                                   createdAtUtc,
                                                   expiresAtUtc,
                                                   positionModel);
  }

void PrintDryRunSummary(const string mode,
                        const datetime expiresAtUtc,
                        const long remainingTtlSeconds,
                        const string preflightResult,
                        const string preflightReason)
  {
   PrintLine("sprint8d_m2_artifact_mode="+mode);
   PrintLine("basket_id="+InpBasketId);
   PrintLine("candidate_id="+InpCandidateId);
   PrintLine("execution_request_id="+InpExecutionRequestId);
   PrintLine("profit_level_id="+InpProfitLevelId);
   PrintLine("position_ticket="+IntegerToString((long)InpPositionTicket));
   PrintLine("original_volume="+DoubleToString(InpOriginalVolume,8));
   PrintLine("requested_close_volume="+DoubleToString(InpRequestedCloseVolume,8));
   PrintLine("symbol="+InpSymbol);
   PrintLine("strategy_profile_hash="+InpStrategyProfileHash);
   PrintLine("basket_version="+IntegerToString((int)InpBasketVersion));
   PrintLine("quote_sequence="+IntegerToString((long)InpQuoteSequence));
   PrintLine("expires_at="+IntegerToString((long)expiresAtUtc));
   PrintLine("remaining_ttl_seconds="+IntegerToString(remainingTtlSeconds));
   PrintLine("artifact_path="+InpArtifactPath);
   PrintLine("preflight_result="+preflightResult);
   PrintLine("preflight_reason="+preflightReason);
  }

void OnStart(void)
  {
   const datetime nowUtc=TimeCurrent();
   const datetime createdAtUtc=InpCreatedAtUtc>0 ? InpCreatedAtUtc : nowUtc;
   const datetime expiresAtUtc=InpExpiresAtUtc;
   const string mode=InpWriteArtifact ? "WRITE" : "DRY_RUN";

   ENUM_BRE_ACCOUNT_POSITION_MODEL positionModel=BRE_ACCOUNT_POSITION_MODEL_UNKNOWN;
   if(!TryParsePositionModel(InpPositionModel,positionModel))
     {
      PrintDryRunSummary(mode,expiresAtUtc,0,"FAIL","Position model invalid");
      return;
     }

   long remainingTtlSeconds=0;
   string preflightReason="";
   bool preflightOk=RunPreflight(createdAtUtc,expiresAtUtc,nowUtc,positionModel,remainingTtlSeconds,preflightReason);

   if(!preflightOk)
     {
      PrintDryRunSummary(mode,expiresAtUtc,remainingTtlSeconds,"FAIL",preflightReason);
      return;
     }

   CManualProfitCloseCandidateEntry entry=BuildEntry(createdAtUtc,expiresAtUtc,positionModel);
   PrintDryRunSummary(mode,expiresAtUtc,remainingTtlSeconds,"PASS","");

   if(!InpWriteArtifact)
      return;

   bool reusedExisting=false;
   bool replacedExpired=false;
   CManualProfitCloseCandidateEntry persistedEntry;
   SSprint8cCandidateArtifactDiagnostics diagnostics;
   if(!CManualProfitCloseCandidateValidationArtifact::TryPersistIdempotent(entry,
                                                                        "DUE",
                                                                        nowUtc,
                                                                        persistedEntry,
                                                                        reusedExisting,
                                                                        replacedExpired,
                                                                        diagnostics,
                                                                        InpArtifactPath))
     {
      PrintLine("artifact_write_result=FAIL");
      PrintLine("artifact_write_failure_reason="+diagnostics.failure_reason);
      CManualProfitCloseCandidateValidationArtifact::LogDiagnostics(diagnostics);
      return;
     }

   PrintLine("artifact_write_result=OK");
   PrintLine("candidate_artifact_reused="+(reusedExisting?"true":"false"));
   PrintLine("candidate_artifact_replaced_expired="+(replacedExpired?"true":"false"));
   CManualProfitCloseCandidateValidationArtifact::LogDiagnostics(diagnostics);
   CManualProfitCloseCandidateValidationArtifact::PrintReuseEligibilityDiagnostics(diagnostics);
  }
