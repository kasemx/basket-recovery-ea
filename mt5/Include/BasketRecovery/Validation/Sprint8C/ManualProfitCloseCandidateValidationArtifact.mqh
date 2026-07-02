#ifndef BRE_APP_MANUAL_PC_VALIDATION_ARTIFACT_MQH
#define BRE_APP_MANUAL_PC_VALIDATION_ARTIFACT_MQH

// Validation-only artifact I/O for Sprint 8C chart scripts. Do not include from production paths.

#include <BasketRecovery/Domain/Execution/ValueObjects/ManualProfitCloseCandidateEntry.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateRegistry.mqh>
#include <BasketRecovery/Domain/Market/Enums/AccountPositionModel.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5LivePositionTicketAuthority.mqh>
#include <BasketRecovery/Shared/Utils/Crc32.mqh>

const int SPRINT8C_CANDIDATE_ARTIFACT_SCHEMA_VERSION=1;
const int SPRINT8C_VALIDATION_CANDIDATE_ARTIFACT_TTL_SECONDS=360;
const int SPRINT8C_VALIDATION_AUTH_TOKEN_TTL_SECONDS=300;
const int SPRINT8C_VALIDATION_ARTIFACT_REUSE_SAFETY_MARGIN_SECONDS=30;

struct SSprint8cCandidateArtifactRecord
  {
   int               schema_version;
   string            artifact_key;
   string            basket_id;
   string            candidate_id;
   string            execution_request_id;
   string            idempotency_key;
   string            profit_level_id;
   int               profit_level_index;
   string            strategy_profile_hash;
   long              basket_version;
   string            symbol;
   ulong             position_ticket;
   double            original_volume;
   double            requested_close_volume;
   ENUM_BRE_ACCOUNT_POSITION_MODEL position_model;
   string            status;
   datetime          created_at;
   datetime          expires_at;
   ulong             quote_sequence;
   string            integrity_hash;
  };

struct SSprint8cCandidateArtifactDiagnostics
  {
   string            store_path;
   string            artifact_key;
   bool              found;
   datetime          created_at;
   datetime          expires_at;
   string            execution_request_id;
   ulong             ticket;
   double            volume;
   string            validation;
   string            failure_reason;
   string            existing_state;
   bool              replaced_expired;
   bool              replaced_insufficient_remaining;
   long              expiry_remaining_seconds;
   long              candidate_artifact_ttl_seconds;
   long              auth_token_ttl_seconds;
   long              required_minimum_artifact_remaining_seconds;
   bool              reuse_allowed;
   string            reuse_rejection_reason;

   void              Reset(void)
     {
      store_path="";
      artifact_key="";
      found=false;
      created_at=0;
      expires_at=0;
      execution_request_id="";
      ticket=0;
      volume=0.0;
      validation="";
      failure_reason="";
      existing_state="none";
      replaced_expired=false;
      replaced_insufficient_remaining=false;
      expiry_remaining_seconds=0;
      candidate_artifact_ttl_seconds=0;
      auth_token_ttl_seconds=0;
      required_minimum_artifact_remaining_seconds=0;
      reuse_allowed=false;
      reuse_rejection_reason="";
     }
  };

struct SSprint8cProfitCloseRestoreOutcome
  {
   bool              attempted;
   bool              restored;
   string            failure_reason;
   string            candidate_id;
   string            execution_request_id;
   ulong             ticket;
   double            close_volume;

   void              Reset(void)
     {
      attempted=false;
      restored=false;
      failure_reason="";
      candidate_id="";
      execution_request_id="";
      ticket=0;
      close_volume=0.0;
     }
  };

class CManualProfitCloseCandidateValidationArtifact
  {
public:
   static string     DefaultRelativePath(void) { return "BasketRecovery/validation/sprint-8c-live-candidate.txt"; }
   static string     TestRelativePath(void) { return "BasketRecovery/validation/sprint-8c-test-candidate-handoff.txt"; }
   static string     ArtifactFilePattern(void) { return "sprint-8c-live-candidate"; }
   static int        DefaultArtifactTtlSeconds(void) { return SPRINT8C_VALIDATION_CANDIDATE_ARTIFACT_TTL_SECONDS; }
   static int        DefaultAuthTokenTtlSeconds(void) { return SPRINT8C_VALIDATION_AUTH_TOKEN_TTL_SECONDS; }
   static int        ArtifactReuseSafetyMarginSeconds(void) { return SPRINT8C_VALIDATION_ARTIFACT_REUSE_SAFETY_MARGIN_SECONDS; }

   static int        ResolveAuthTokenTtlSeconds(const int authTokenTtlSeconds)
     {
      return authTokenTtlSeconds>0 ? authTokenTtlSeconds : DefaultAuthTokenTtlSeconds();
     }

   static int        ComputeRequiredMinimumArtifactRemainingSeconds(const int authTokenTtlSeconds=0)
     {
      return ResolveAuthTokenTtlSeconds(authTokenTtlSeconds)+ArtifactReuseSafetyMarginSeconds();
     }

   static void       FillReuseEligibilityDiagnostics(const SSprint8cCandidateArtifactRecord &record,
                                                     const datetime nowUtc,
                                                     const int authTokenTtlSeconds,
                                                     SSprint8cCandidateArtifactDiagnostics &diagnostics)
     {
      diagnostics.candidate_artifact_ttl_seconds=DefaultArtifactTtlSeconds();
      diagnostics.auth_token_ttl_seconds=ResolveAuthTokenTtlSeconds(authTokenTtlSeconds);
      diagnostics.expiry_remaining_seconds=ComputeExpiryRemainingSeconds(record,nowUtc);
      diagnostics.required_minimum_artifact_remaining_seconds=
         ComputeRequiredMinimumArtifactRemainingSeconds(authTokenTtlSeconds);
      diagnostics.reuse_allowed=(diagnostics.expiry_remaining_seconds>=
                                 diagnostics.required_minimum_artifact_remaining_seconds);
      diagnostics.reuse_rejection_reason=diagnostics.reuse_allowed ?
         "" :
         "Artifact remaining TTL insufficient for auth workflow";
     }

   static void       PrintReuseEligibilityDiagnostics(const SSprint8cCandidateArtifactDiagnostics &diagnostics)
     {
      Print("candidate_artifact_ttl_seconds=",IntegerToString(diagnostics.candidate_artifact_ttl_seconds));
      Print("candidate_artifact_expiry_remaining_seconds=",IntegerToString(diagnostics.expiry_remaining_seconds));
      Print("auth_token_ttl_seconds=",IntegerToString(diagnostics.auth_token_ttl_seconds));
      Print("required_minimum_artifact_remaining_seconds=",
            IntegerToString(diagnostics.required_minimum_artifact_remaining_seconds));
      Print("candidate_artifact_reuse_allowed=",diagnostics.reuse_allowed?"true":"false");
      Print("candidate_artifact_reuse_rejection_reason=",diagnostics.reuse_rejection_reason);
     }

   static bool       VolumesMatch(const double left,const double right)
     {
      return MathAbs(left-right)<=0.00000001;
     }

   static bool       IsRecordExpired(const SSprint8cCandidateArtifactRecord &record,const datetime nowUtc)
     {
      return record.expires_at>0 && nowUtc>=record.expires_at;
     }

   static long       ComputeExpiryRemainingSeconds(const SSprint8cCandidateArtifactRecord &record,
                                                   const datetime nowUtc)
     {
      if(record.expires_at<=0)
         return 0;
      long remaining=(long)record.expires_at-(long)nowUtc;
      return remaining>0 ? remaining : 0;
     }

   static string     BuildArtifactKey(const string basketId,const string profitLevelId)
     {
      return basketId+"|"+profitLevelId;
     }

   static string     BuildIntegrityPayload(const SSprint8cCandidateArtifactRecord &record)
     {
      return StringFormat("%d|%s|%s|%s|%s|%s|%I64u|%.8f|%.8f|%s|%d|%s|%I64d|%I64d",
                          record.schema_version,
                          record.artifact_key,
                          record.basket_id,
                          record.candidate_id,
                          record.execution_request_id,
                          record.profit_level_id,
                          record.position_ticket,
                          record.original_volume,
                          record.requested_close_volume,
                          record.strategy_profile_hash,
                          (int)record.position_model,
                          record.status,
                          (long)record.created_at,
                          (long)record.expires_at);
     }

   static string     ComputeIntegrityHash(const SSprint8cCandidateArtifactRecord &record)
     {
      string payload=BuildIntegrityPayload(record);
      uint crc=CCrc32::Compute(payload);
      return CCrc32::ToHex(crc);
     }

   static bool       RecordFromEntry(const CManualProfitCloseCandidateEntry &entry,
                                     const string candidateStatus,
                                     SSprint8cCandidateArtifactRecord &record)
     {
      record.schema_version=SPRINT8C_CANDIDATE_ARTIFACT_SCHEMA_VERSION;
      record.artifact_key=BuildArtifactKey(entry.BasketId().Value(),entry.ProfitLevelId());
      record.basket_id=entry.BasketId().Value();
      record.candidate_id=entry.CandidateId();
      record.execution_request_id=entry.ExecutionRequestId();
      record.idempotency_key=entry.IdempotencyKey();
      record.profit_level_id=entry.ProfitLevelId();
      record.profit_level_index=entry.ProfitLevelIndex();
      record.strategy_profile_hash=entry.StrategyProfileHash();
      record.basket_version=entry.BasketVersion();
      record.symbol=entry.Symbol();
      record.position_ticket=entry.PositionTicket();
      record.original_volume=entry.OriginalPositionVolume();
      record.requested_close_volume=entry.ProposedCloseVolume();
      record.position_model=entry.AccountPositionModel();
      record.status=candidateStatus;
      record.created_at=entry.CreatedAtUtc();
      record.expires_at=entry.ExpiresAtUtc();
      record.quote_sequence=entry.QuoteSequence();
      record.integrity_hash=ComputeIntegrityHash(record);
      return true;
     }

   static bool       EntryFromRecord(const SSprint8cCandidateArtifactRecord &record,
                                     CManualProfitCloseCandidateEntry &entry)
     {
      if(record.candidate_id=="" || record.execution_request_id=="" || record.basket_id=="")
         return false;

      ENUM_BRE_TRADE_DIRECTION positionDirection=BRE_DIRECTION_BUY;
      string liveSymbol="";
      long livePositionType=0;
      double liveVolume=0.0;
      string liveLookupFailure="";
      if(CMt5LivePositionTicketAuthority::TryResolveByTicket(record.position_ticket,
                                                             liveSymbol,
                                                             livePositionType,
                                                             positionDirection,
                                                             liveVolume,
                                                             liveLookupFailure))
        {
         // live ticket authority wins over artifact defaults
        }

      entry=CManualProfitCloseCandidateEntry::Create(record.candidate_id,
                                                     record.execution_request_id,
                                                     record.idempotency_key,
                                                     CBasketId(record.basket_id),
                                                     record.profit_level_id,
                                                     record.profit_level_index,
                                                     record.strategy_profile_hash,
                                                     record.basket_version,
                                                     record.symbol,
                                                     BRE_DIRECTION_BUY,
                                                     positionDirection,
                                                     record.position_ticket,
                                                     record.original_volume,
                                                     record.requested_close_volume,
                                                     0.0,
                                                     BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,
                                                     0.01,
                                                     record.quote_sequence,
                                                     record.created_at,
                                                     record.expires_at,
                                                     record.position_model);
      return true;
     }

   static void       FillDiagnosticsFromRecord(const string relativePath,
                                               const SSprint8cCandidateArtifactRecord &record,
                                               SSprint8cCandidateArtifactDiagnostics &diagnostics)
     {
      diagnostics.store_path=relativePath;
      diagnostics.artifact_key=record.artifact_key;
      diagnostics.found=true;
      diagnostics.created_at=record.created_at;
      diagnostics.expires_at=record.expires_at;
      diagnostics.execution_request_id=record.execution_request_id;
      diagnostics.ticket=record.position_ticket;
      diagnostics.volume=record.requested_close_volume;
     }

   static void       LogDiagnostics(const SSprint8cCandidateArtifactDiagnostics &diagnostics)
     {
      Print("candidate_artifact_store_path=",diagnostics.store_path);
      Print("candidate_artifact_key=",diagnostics.artifact_key);
      Print("candidate_artifact_found=",diagnostics.found?"true":"false");
      Print("candidate_artifact_created_at=",IntegerToString((long)diagnostics.created_at));
      Print("candidate_artifact_expires_at=",IntegerToString((long)diagnostics.expires_at));
      Print("candidate_artifact_execution_request_id=",diagnostics.execution_request_id);
      Print("candidate_artifact_ticket=",IntegerToString((long)diagnostics.ticket));
      Print("candidate_artifact_volume=",DoubleToString(diagnostics.volume,8));
      Print("candidate_artifact_validation=",diagnostics.validation);
      Print("candidate_artifact_failure_reason=",diagnostics.failure_reason);
      if(diagnostics.existing_state!="")
         Print("candidate_artifact_existing_state=",diagnostics.existing_state);
      Print("candidate_artifact_replaced_expired=",diagnostics.replaced_expired?"true":"false");
      if(diagnostics.expiry_remaining_seconds>0 || diagnostics.validation=="OK")
         Print("candidate_artifact_expiry_remaining_seconds=",IntegerToString(diagnostics.expiry_remaining_seconds));
      if(diagnostics.candidate_artifact_ttl_seconds>0 || diagnostics.auth_token_ttl_seconds>0)
         PrintReuseEligibilityDiagnostics(diagnostics);
     }

   static bool       TryRemoveRecord(const string relativePath)
     {
      if(relativePath=="")
         return false;
      if(!FileIsExist(relativePath,FILE_COMMON))
         return true;
      return FileDelete(relativePath,FILE_COMMON);
     }

   static bool       ValidateRecordIntegrity(const SSprint8cCandidateArtifactRecord &record,
                                             string &failureReason)
     {
      failureReason="";
      if(record.schema_version!=SPRINT8C_CANDIDATE_ARTIFACT_SCHEMA_VERSION)
        {
         failureReason="Unsupported artifact schema_version";
         return false;
        }
      if(record.status!="DUE")
        {
         failureReason="Candidate status is not DUE";
         return false;
        }
      if(record.strategy_profile_hash=="")
        {
         failureReason="Strategy profile hash missing";
         return false;
        }
      if(!CAccountPositionModelHelper::SupportsExplicitTicketPartialClose(record.position_model))
        {
         failureReason="Position model does not support ticket-bound partial close";
         return false;
        }
      if(record.requested_close_volume<=0.0)
        {
         failureReason="Requested close volume invalid";
         return false;
        }
      if(record.integrity_hash=="")
        {
         failureReason="Integrity hash missing";
         return false;
        }
      if(record.integrity_hash!=ComputeIntegrityHash(record))
        {
         failureReason="Integrity hash mismatch";
         return false;
        }
      return true;
     }

   static bool       RecordMatchesEntryBinding(const SSprint8cCandidateArtifactRecord &record,
                                               const CManualProfitCloseCandidateEntry &entry)
     {
      if(record.basket_id!=entry.BasketId().Value())
         return false;
      if(record.profit_level_id!=entry.ProfitLevelId())
         return false;
      if(record.candidate_id!=entry.CandidateId())
         return false;
      if(record.position_ticket!=entry.PositionTicket())
         return false;
      if(!VolumesMatch(record.original_volume,entry.OriginalPositionVolume()))
         return false;
      if(!VolumesMatch(record.requested_close_volume,entry.ProposedCloseVolume()))
         return false;
      if(record.strategy_profile_hash!=entry.StrategyProfileHash())
         return false;
      return true;
     }

   static string     ClassifyExistingArtifactState(const SSprint8cCandidateArtifactRecord &record,
                                                   const datetime nowUtc,
                                                   const CManualProfitCloseCandidateEntry &entry,
                                                   string &failureReason,
                                                   const int authTokenTtlSeconds=0)
     {
      failureReason="";
      if(IsRecordExpired(record,nowUtc))
         return "expired";

      if(!ValidateRecordIntegrity(record,failureReason))
         return "invalid";

      if(!RecordMatchesEntryBinding(record,entry))
        {
         failureReason="Existing artifact binding mismatch";
         return "invalid";
        }

      long remaining=ComputeExpiryRemainingSeconds(record,nowUtc);
      long requiredMinimum=ComputeRequiredMinimumArtifactRemainingSeconds(authTokenTtlSeconds);
      if(remaining<requiredMinimum)
        {
         failureReason="Artifact remaining TTL insufficient for auth workflow";
         return "insufficient_remaining";
        }

      return "valid";
     }

   static bool       TryEvaluateArtifactReuseAllowed(const SSprint8cCandidateArtifactRecord &record,
                                                     const datetime nowUtc,
                                                     const CManualProfitCloseCandidateEntry &entry,
                                                     const int authTokenTtlSeconds,
                                                     SSprint8cCandidateArtifactDiagnostics &diagnostics)
     {
      FillReuseEligibilityDiagnostics(record,nowUtc,authTokenTtlSeconds,diagnostics);
      if(IsRecordExpired(record,nowUtc))
         return false;
      string failureReason="";
      if(!ValidateRecordIntegrity(record,failureReason))
         return false;
      if(!RecordMatchesEntryBinding(record,entry))
         return false;
      return diagnostics.reuse_allowed;
     }

   static bool       ValidateLiveRegistrationPreconditions(const bool candidateDue,
                                                         const double floatingProfitUsd,
                                                         const ulong plannerTicket,
                                                         const double plannerOriginalVolume,
                                                         const ulong liveTicket,
                                                         const double liveVolume,
                                                         const string basketProfileHash,
                                                         string &failureReason)
     {
      failureReason="";
      if(!candidateDue)
        {
         failureReason="Candidate is not DUE";
         return false;
        }
      if(floatingProfitUsd<=0.0)
        {
         failureReason="Current floating profit is not positive";
         return false;
        }
      if(plannerTicket<=0 || liveTicket<=0)
        {
         failureReason="Live position ticket missing";
         return false;
        }
      if(plannerTicket!=liveTicket)
        {
         failureReason="Live position ticket mismatch";
         return false;
        }
      if(!VolumesMatch(plannerOriginalVolume,liveVolume))
        {
         failureReason="Live position volume mismatch";
         return false;
        }
      if(basketProfileHash=="")
        {
         failureReason="Basket strategy profile hash missing";
         return false;
        }
      return true;
     }

   static bool       WriteRecord(const SSprint8cCandidateArtifactRecord &record)
     {
      return WriteRecord(record,DefaultRelativePath());
     }

   static bool       WriteRecord(const SSprint8cCandidateArtifactRecord &record,
                                 const string relativePath)
     {
      SSprint8cCandidateArtifactRecord toWrite=record;
      toWrite.integrity_hash=ComputeIntegrityHash(toWrite);

      int handle=FileOpen(relativePath,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(handle==INVALID_HANDLE)
         return false;

      FileWriteString(handle,"schema_version="+IntegerToString(toWrite.schema_version)+"\r\n");
      FileWriteString(handle,"artifact_key="+toWrite.artifact_key+"\r\n");
      FileWriteString(handle,"candidate_id="+toWrite.candidate_id+"\r\n");
      FileWriteString(handle,"execution_request_id="+toWrite.execution_request_id+"\r\n");
      FileWriteString(handle,"idempotency_key="+toWrite.idempotency_key+"\r\n");
      FileWriteString(handle,"basket_id="+toWrite.basket_id+"\r\n");
      FileWriteString(handle,"profit_level_id="+toWrite.profit_level_id+"\r\n");
      FileWriteString(handle,"profit_level_index="+IntegerToString(toWrite.profit_level_index)+"\r\n");
      FileWriteString(handle,"strategy_profile_hash="+toWrite.strategy_profile_hash+"\r\n");
      FileWriteString(handle,"basket_version="+IntegerToString((int)toWrite.basket_version)+"\r\n");
      FileWriteString(handle,"symbol="+toWrite.symbol+"\r\n");
      FileWriteString(handle,"position_ticket="+IntegerToString((long)toWrite.position_ticket)+"\r\n");
      FileWriteString(handle,"original_volume="+DoubleToString(toWrite.original_volume,8)+"\r\n");
      FileWriteString(handle,"requested_close_volume="+DoubleToString(toWrite.requested_close_volume,8)+"\r\n");
      FileWriteString(handle,"proposed_close_volume="+DoubleToString(toWrite.requested_close_volume,8)+"\r\n");
      FileWriteString(handle,"account_position_model="+IntegerToString((int)toWrite.position_model)+"\r\n");
      FileWriteString(handle,"position_model="+IntegerToString((int)toWrite.position_model)+"\r\n");
      FileWriteString(handle,"status="+toWrite.status+"\r\n");
      FileWriteString(handle,"candidate_status="+toWrite.status+"\r\n");
      FileWriteString(handle,"created_at="+IntegerToString((long)toWrite.created_at)+"\r\n");
      FileWriteString(handle,"created_at_utc="+IntegerToString((long)toWrite.created_at)+"\r\n");
      FileWriteString(handle,"expires_at="+IntegerToString((long)toWrite.expires_at)+"\r\n");
      FileWriteString(handle,"expires_at_utc="+IntegerToString((long)toWrite.expires_at)+"\r\n");
      FileWriteString(handle,"quote_sequence="+IntegerToString((long)toWrite.quote_sequence)+"\r\n");
      FileWriteString(handle,"integrity_hash="+toWrite.integrity_hash+"\r\n");
      FileWriteString(handle,"artifact_written_at_utc="+IntegerToString((long)TimeCurrent())+"\r\n");
      FileClose(handle);
      return true;
     }

   static bool       TryReadRecord(const string relativePath,SSprint8cCandidateArtifactRecord &record)
     {
      int handle=FileOpen(relativePath,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(handle==INVALID_HANDLE)
         return false;

      SSprint8cCandidateArtifactRecord parsed;
      parsed.schema_version=0;

      while(!FileIsEnding(handle))
        {
         string line=FileReadString(handle);
         int eq=StringFind(line,"=");
         if(eq<=0)
            continue;
         string key=StringSubstr(line,0,eq);
         string value=StringSubstr(line,eq+1);

         if(key=="schema_version") parsed.schema_version=(int)StringToInteger(value);
         else if(key=="artifact_key") parsed.artifact_key=value;
         else if(key=="candidate_id") parsed.candidate_id=value;
         else if(key=="execution_request_id") parsed.execution_request_id=value;
         else if(key=="idempotency_key") parsed.idempotency_key=value;
         else if(key=="basket_id") parsed.basket_id=value;
         else if(key=="profit_level_id") parsed.profit_level_id=value;
         else if(key=="profit_level_index") parsed.profit_level_index=(int)StringToInteger(value);
         else if(key=="strategy_profile_hash") parsed.strategy_profile_hash=value;
         else if(key=="basket_version") parsed.basket_version=(long)StringToInteger(value);
         else if(key=="symbol") parsed.symbol=value;
         else if(key=="position_ticket") parsed.position_ticket=(ulong)StringToInteger(value);
         else if(key=="original_volume") parsed.original_volume=StringToDouble(value);
         else if(key=="original_position_volume") parsed.original_volume=StringToDouble(value);
         else if(key=="requested_close_volume") parsed.requested_close_volume=StringToDouble(value);
         else if(key=="proposed_close_volume" && parsed.requested_close_volume<=0.0) parsed.requested_close_volume=StringToDouble(value);
         else if(key=="account_position_model") parsed.position_model=(ENUM_BRE_ACCOUNT_POSITION_MODEL)StringToInteger(value);
         else if(key=="position_model") parsed.position_model=(ENUM_BRE_ACCOUNT_POSITION_MODEL)StringToInteger(value);
         else if(key=="status") parsed.status=value;
         else if(key=="candidate_status" && parsed.status=="") parsed.status=value;
         else if(key=="created_at") parsed.created_at=(datetime)StringToInteger(value);
         else if(key=="created_at_utc" && parsed.created_at==0) parsed.created_at=(datetime)StringToInteger(value);
         else if(key=="expires_at") parsed.expires_at=(datetime)StringToInteger(value);
         else if(key=="expires_at_utc" && parsed.expires_at==0) parsed.expires_at=(datetime)StringToInteger(value);
         else if(key=="quote_sequence") parsed.quote_sequence=(ulong)StringToInteger(value);
         else if(key=="integrity_hash") parsed.integrity_hash=value;
        }
      FileClose(handle);

      if(parsed.candidate_id=="" || parsed.execution_request_id=="" || parsed.basket_id=="")
         return false;

      if(parsed.schema_version<=0)
         parsed.schema_version=1;
      if(parsed.artifact_key=="")
         parsed.artifact_key=BuildArtifactKey(parsed.basket_id,parsed.profit_level_id);
      if(parsed.status=="")
         parsed.status="DUE";

      record=parsed;
      return true;
     }

   static int        CountDueArtifactFiles(string &firstPath,string &secondPath)
     {
      firstPath="";
      secondPath="";
      int dueCount=0;
      string fileName="";
      string filter="BasketRecovery\\validation\\"+ArtifactFilePattern()+"*.txt";
      long search=FileFindFirst(filter,fileName,FILE_COMMON);
      if(search==INVALID_HANDLE)
         return 0;

      do
        {
         string relativePath="BasketRecovery/validation/"+fileName;
         SSprint8cCandidateArtifactRecord record;
         if(TryReadRecord(relativePath,record) && record.status=="DUE")
           {
            if(dueCount==0)
               firstPath=relativePath;
            else if(dueCount==1)
               secondPath=relativePath;
            dueCount++;
           }
        }
      while(FileFindNext(search,fileName));

      FileFindClose(search);
      return dueCount;
     }

   static bool       WriteEntry(const CManualProfitCloseCandidateEntry &entry,
                                const string candidateStatus)
     {
      return WriteEntry(entry,candidateStatus,DefaultRelativePath());
     }

   static bool       WriteEntry(const CManualProfitCloseCandidateEntry &entry,
                                const string candidateStatus,
                                const string relativePath)
     {
      SSprint8cCandidateArtifactRecord record;
      RecordFromEntry(entry,candidateStatus,record);
      return WriteRecord(record,relativePath);
     }

   static bool       TryLoadActiveRecord(const string relativePath,
                                         SSprint8cCandidateArtifactRecord &record,
                                         SSprint8cCandidateArtifactDiagnostics &diagnostics)
     {
      diagnostics.Reset();
      diagnostics.store_path=relativePath;
      if(!TryReadRecord(relativePath,record))
        {
         diagnostics.found=false;
         diagnostics.validation="FAIL";
         diagnostics.failure_reason="Candidate artifact file not found or unreadable";
         return false;
        }

      FillDiagnosticsFromRecord(relativePath,record,diagnostics);
      return true;
     }

   static bool       ValidateLoadedRecord(const SSprint8cCandidateArtifactRecord &record,
                                          const datetime nowUtc,
                                          const string expectedBasketId,
                                          const ulong expectedTicket,
                                          string &failureReason)
     {
      failureReason="";
      if(record.basket_id!=expectedBasketId)
        {
         failureReason="Basket ID mismatch";
         return false;
        }
      if(expectedTicket>0 && record.position_ticket!=expectedTicket)
        {
         failureReason="Position ticket mismatch";
         return false;
        }
      if(IsRecordExpired(record,nowUtc))
        {
         failureReason="Candidate artifact expired";
         return false;
        }
      return ValidateRecordIntegrity(record,failureReason);
     }

   static bool       TryLoadAndValidate(const string expectedBasketId,
                                        const ulong expectedTicket,
                                        const datetime nowUtc,
                                        SSprint8cCandidateArtifactRecord &record,
                                        SSprint8cCandidateArtifactDiagnostics &diagnostics)
     {
      return TryLoadAndValidate(expectedBasketId,expectedTicket,nowUtc,record,diagnostics,DefaultRelativePath());
     }

   static bool       TryLoadAndValidate(const string expectedBasketId,
                                        const ulong expectedTicket,
                                        const datetime nowUtc,
                                        SSprint8cCandidateArtifactRecord &record,
                                        SSprint8cCandidateArtifactDiagnostics &diagnostics,
                                        const string relativePath,
                                        const int authTokenTtlSeconds=0)
     {
      diagnostics.Reset();
      diagnostics.store_path=relativePath;

      if(relativePath==DefaultRelativePath())
        {
         string firstPath="";
         string secondPath="";
         int dueCount=CountDueArtifactFiles(firstPath,secondPath);
         if(dueCount>1)
           {
            diagnostics.found=true;
            diagnostics.validation="FAIL";
            diagnostics.failure_reason="Multiple active DUE candidate artifacts: "+firstPath+" and "+secondPath;
            return false;
           }
        }

      if(!TryLoadActiveRecord(relativePath,record,diagnostics))
         return false;

      FillReuseEligibilityDiagnostics(record,nowUtc,authTokenTtlSeconds,diagnostics);

      string failureReason="";
      if(!ValidateLoadedRecord(record,nowUtc,expectedBasketId,expectedTicket,failureReason))
        {
         diagnostics.validation="FAIL";
         diagnostics.failure_reason=failureReason;
         return false;
        }

      diagnostics.validation="OK";
      diagnostics.failure_reason="";
      return true;
     }

   static bool       TryPersistIdempotent(const CManualProfitCloseCandidateEntry &entry,
                                          const string candidateStatus,
                                          const datetime nowUtc,
                                          CManualProfitCloseCandidateEntry &outEntry,
                                          bool &reusedExisting,
                                          bool &replacedExpired,
                                          SSprint8cCandidateArtifactDiagnostics &diagnostics)
     {
      return TryPersistIdempotent(entry,candidateStatus,nowUtc,outEntry,reusedExisting,replacedExpired,diagnostics,DefaultRelativePath());
     }

   static bool       TryPersistIdempotent(const CManualProfitCloseCandidateEntry &entry,
                                          const string candidateStatus,
                                          const datetime nowUtc,
                                          CManualProfitCloseCandidateEntry &outEntry,
                                          bool &reusedExisting,
                                          bool &replacedExpired,
                                          SSprint8cCandidateArtifactDiagnostics &diagnostics,
                                          const string relativePath,
                                          const int authTokenTtlSeconds=0)
     {
      reusedExisting=false;
      replacedExpired=false;
      outEntry=entry;
      diagnostics.Reset();
      diagnostics.store_path=relativePath;
      diagnostics.existing_state="none";

      SSprint8cCandidateArtifactRecord existing;
      if(TryReadRecord(relativePath,existing))
        {
         FillDiagnosticsFromRecord(relativePath,existing,diagnostics);
         string classifyFailure="";
         string existingState=ClassifyExistingArtifactState(existing,nowUtc,entry,classifyFailure,authTokenTtlSeconds);
         diagnostics.existing_state=existingState;
         FillReuseEligibilityDiagnostics(existing,nowUtc,authTokenTtlSeconds,diagnostics);

         if(existingState=="valid")
           {
            CManualProfitCloseCandidateEntry restored;
            if(EntryFromRecord(existing,restored))
              {
               outEntry=restored;
               reusedExisting=true;
               replacedExpired=false;
               diagnostics.validation="OK";
               diagnostics.failure_reason="";
               LogDiagnostics(diagnostics);
               return true;
              }
            diagnostics.validation="FAIL";
            diagnostics.failure_reason="Could not restore candidate artifact entry";
            return false;
           }

         if(existingState=="invalid")
           {
            diagnostics.validation="FAIL";
            diagnostics.failure_reason=classifyFailure;
            LogDiagnostics(diagnostics);
            return false;
           }

         if(existingState=="expired")
           {
            if(!TryRemoveRecord(relativePath))
              {
               diagnostics.validation="FAIL";
               diagnostics.failure_reason="Could not remove replaceable candidate artifact";
               return false;
              }
            replacedExpired=true;
            diagnostics.found=false;
            diagnostics.replaced_expired=true;
           }
         else if(existingState=="insufficient_remaining")
           {
            if(!TryRemoveRecord(relativePath))
              {
               diagnostics.validation="FAIL";
               diagnostics.failure_reason="Could not remove replaceable candidate artifact";
               return false;
              }
            replacedExpired=true;
            diagnostics.found=false;
            diagnostics.replaced_expired=true;
            diagnostics.replaced_insufficient_remaining=true;
           }
        }

      SSprint8cCandidateArtifactRecord record;
      RecordFromEntry(entry,candidateStatus,record);
      if(!WriteRecord(record,relativePath))
        {
         diagnostics.found=false;
         diagnostics.validation="FAIL";
         diagnostics.failure_reason="Could not write candidate artifact";
         return false;
        }

      TryLoadActiveRecord(relativePath,record,diagnostics);
      diagnostics.validation="OK";
      diagnostics.failure_reason="";
      diagnostics.existing_state=replacedExpired ? diagnostics.existing_state : diagnostics.existing_state;
      diagnostics.replaced_expired=replacedExpired;
      FillReuseEligibilityDiagnostics(record,nowUtc,authTokenTtlSeconds,diagnostics);
      LogDiagnostics(diagnostics);
      return true;
     }

   static bool       TryPersistIdempotent(const CManualProfitCloseCandidateEntry &entry,
                                          const string candidateStatus,
                                          const datetime nowUtc,
                                          CManualProfitCloseCandidateEntry &outEntry,
                                          bool &reusedExisting,
                                          SSprint8cCandidateArtifactDiagnostics &diagnostics)
     {
      bool replacedExpired=false;
      return TryPersistIdempotent(entry,candidateStatus,nowUtc,outEntry,reusedExisting,replacedExpired,diagnostics,DefaultRelativePath());
     }

   static bool       TryPersistIdempotent(const CManualProfitCloseCandidateEntry &entry,
                                          const string candidateStatus,
                                          const datetime nowUtc,
                                          CManualProfitCloseCandidateEntry &outEntry,
                                          bool &reusedExisting,
                                          SSprint8cCandidateArtifactDiagnostics &diagnostics,
                                          const string relativePath)
     {
      bool replacedExpired=false;
      return TryPersistIdempotent(entry,candidateStatus,nowUtc,outEntry,reusedExisting,replacedExpired,diagnostics,relativePath);
     }

   static bool       TryRestoreToRegistry(CManualProfitCloseCandidateRegistry &registry)
     {
      SSprint8cProfitCloseRestoreOutcome outcome;
      return TryRestoreToRegistry(registry,TimeCurrent(),outcome,DefaultRelativePath());
     }

   static bool       TryRestoreToRegistry(CManualProfitCloseCandidateRegistry &registry,
                                          const string relativePath)
     {
      SSprint8cProfitCloseRestoreOutcome outcome;
      return TryRestoreToRegistry(registry,TimeCurrent(),outcome,relativePath);
     }

   static bool       TryRestoreToRegistry(CManualProfitCloseCandidateRegistry &registry,
                                          const datetime nowUtc,
                                          SSprint8cProfitCloseRestoreOutcome &outcome)
     {
      return TryRestoreToRegistry(registry,nowUtc,outcome,DefaultRelativePath());
     }

   static bool       TryRestoreToRegistry(CManualProfitCloseCandidateRegistry &registry,
                                          const datetime nowUtc,
                                          SSprint8cProfitCloseRestoreOutcome &outcome,
                                          const string relativePath)
     {
      outcome.Reset();
      if(!FileIsExist(relativePath,FILE_COMMON))
         return false;

      outcome.attempted=true;

      if(relativePath==DefaultRelativePath())
        {
         string firstPath="";
         string secondPath="";
         int dueCount=CountDueArtifactFiles(firstPath,secondPath);
         if(dueCount>1)
           {
            outcome.failure_reason="Multiple active DUE candidate artifacts: "+firstPath+" and "+secondPath;
            return false;
           }
        }

      SSprint8cCandidateArtifactRecord record;
      SSprint8cCandidateArtifactDiagnostics diagnostics;
      if(!TryLoadActiveRecord(relativePath,record,diagnostics))
        {
         outcome.failure_reason=diagnostics.failure_reason;
         if(outcome.failure_reason=="")
            outcome.failure_reason="Candidate artifact file not found or unreadable";
         return false;
        }

      string validationFailure="";
      if(!ValidateLoadedRecord(record,nowUtc,record.basket_id,record.position_ticket,validationFailure))
        {
         outcome.failure_reason=validationFailure;
         return false;
        }

      if(record.execution_request_id=="" || record.candidate_id=="" || record.position_ticket<=0)
        {
         outcome.failure_reason="Candidate artifact binding fields incomplete";
         return false;
        }

      CManualProfitCloseCandidateEntry entry;
      if(!EntryFromRecord(record,entry))
        {
         outcome.failure_reason="Could not convert candidate artifact to registry entry";
         return false;
        }

      if(entry.ExecutionRequestId()!=record.execution_request_id)
        {
         outcome.failure_reason="Restored entry execution_request_id mismatch";
         return false;
        }

      CManualProfitCloseCandidateEntry existing;
      if(registry.TryGetByCandidateId(entry.CandidateId(),existing))
        {
         if(existing.ExecutionRequestId()!=entry.ExecutionRequestId())
           {
            outcome.failure_reason="Registry candidate id conflict with different execution_request_id";
            return false;
           }
         outcome.restored=true;
         outcome.candidate_id=existing.CandidateId();
         outcome.execution_request_id=existing.ExecutionRequestId();
         outcome.ticket=existing.PositionTicket();
         outcome.close_volume=existing.ProposedCloseVolume();
         return true;
        }

      if(!registry.TryRegister(entry))
        {
         outcome.failure_reason="Registry rejected restored candidate entry";
         return false;
        }

      outcome.restored=true;
      outcome.candidate_id=entry.CandidateId();
      outcome.execution_request_id=entry.ExecutionRequestId();
      outcome.ticket=entry.PositionTicket();
      outcome.close_volume=entry.ProposedCloseVolume();
      return true;
     }
  };

#endif
