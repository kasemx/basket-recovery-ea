#ifndef BRE_APP_MANUAL_PC_VALIDATION_ARTIFACT_MQH
#define BRE_APP_MANUAL_PC_VALIDATION_ARTIFACT_MQH

// Validation-only artifact I/O for Sprint 8C chart scripts. Do not include from production paths.

#include <BasketRecovery/Domain/Execution/ValueObjects/ManualProfitCloseCandidateEntry.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateRegistry.mqh>

class CManualProfitCloseCandidateValidationArtifact
  {
public:
   static string     DefaultRelativePath(void) { return "BasketRecovery/validation/sprint-8c-live-candidate.txt"; }

   static bool       WriteEntry(const CManualProfitCloseCandidateEntry &entry,
                                const string candidateStatus)
     {
      int handle=FileOpen(DefaultRelativePath(),FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(handle==INVALID_HANDLE)
         return false;

      FileWriteString(handle,"candidate_id="+entry.CandidateId()+"\r\n");
      FileWriteString(handle,"execution_request_id="+entry.ExecutionRequestId()+"\r\n");
      FileWriteString(handle,"idempotency_key="+entry.IdempotencyKey()+"\r\n");
      FileWriteString(handle,"basket_id="+entry.BasketId().Value()+"\r\n");
      FileWriteString(handle,"profit_level_id="+entry.ProfitLevelId()+"\r\n");
      FileWriteString(handle,"profit_level_index="+IntegerToString(entry.ProfitLevelIndex())+"\r\n");
      FileWriteString(handle,"strategy_profile_hash="+entry.StrategyProfileHash()+"\r\n");
      FileWriteString(handle,"basket_version="+IntegerToString((int)entry.BasketVersion())+"\r\n");
      FileWriteString(handle,"symbol="+entry.Symbol()+"\r\n");
      FileWriteString(handle,"position_ticket="+IntegerToString((long)entry.PositionTicket())+"\r\n");
      FileWriteString(handle,"original_position_volume="+DoubleToString(entry.OriginalPositionVolume(),8)+"\r\n");
      FileWriteString(handle,"proposed_close_volume="+DoubleToString(entry.ProposedCloseVolume(),8)+"\r\n");
      FileWriteString(handle,"quote_sequence="+IntegerToString((long)entry.QuoteSequence())+"\r\n");
      FileWriteString(handle,"created_at_utc="+IntegerToString((long)entry.CreatedAtUtc())+"\r\n");
      FileWriteString(handle,"expires_at_utc="+IntegerToString((long)entry.ExpiresAtUtc())+"\r\n");
      FileWriteString(handle,"account_position_model="+IntegerToString((int)entry.AccountPositionModel())+"\r\n");
      FileWriteString(handle,"candidate_status="+candidateStatus+"\r\n");
      FileWriteString(handle,"reduction_count=1\r\n");
      FileWriteString(handle,"artifact_written_at_utc="+IntegerToString((long)TimeCurrent())+"\r\n");
      FileClose(handle);
      return true;
     }

   static bool       TryRestoreToRegistry(CManualProfitCloseCandidateRegistry &registry)
     {
      int handle=FileOpen(DefaultRelativePath(),FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(handle==INVALID_HANDLE)
         return false;

      string values[];
      ArrayResize(values,20);
      for(int i=0;i<20;i++)
         values[i]="";

      while(!FileIsEnding(handle))
        {
         string line=FileReadString(handle);
         int eq=StringFind(line,"=");
         if(eq<=0)
            continue;
         string key=StringSubstr(line,0,eq);
         string value=StringSubstr(line,eq+1);
         if(key=="candidate_id") values[0]=value;
         else if(key=="execution_request_id") values[1]=value;
         else if(key=="idempotency_key") values[2]=value;
         else if(key=="basket_id") values[3]=value;
         else if(key=="profit_level_id") values[4]=value;
         else if(key=="profit_level_index") values[5]=value;
         else if(key=="strategy_profile_hash") values[6]=value;
         else if(key=="basket_version") values[7]=value;
         else if(key=="symbol") values[8]=value;
         else if(key=="position_ticket") values[9]=value;
         else if(key=="original_position_volume") values[10]=value;
         else if(key=="proposed_close_volume") values[11]=value;
         else if(key=="quote_sequence") values[12]=value;
         else if(key=="created_at_utc") values[13]=value;
         else if(key=="expires_at_utc") values[14]=value;
         else if(key=="account_position_model") values[15]=value;
        }
      FileClose(handle);

      if(values[0]=="" || values[1]=="" || values[3]=="")
         return false;

      ENUM_BRE_TRADE_DIRECTION positionDirection=BRE_DIRECTION_BUY;
      CManualProfitCloseCandidateEntry entry=CManualProfitCloseCandidateEntry::Create(values[0],
                                                                                      values[1],
                                                                                      values[2],
                                                                                      CBasketId(values[3]),
                                                                                      values[4],
                                                                                      (int)StringToInteger(values[5]),
                                                                                      values[6],
                                                                                      (long)StringToInteger(values[7]),
                                                                                      values[8],
                                                                                      BRE_DIRECTION_BUY,
                                                                                      positionDirection,
                                                                                      (ulong)StringToInteger(values[9]),
                                                                                      StringToDouble(values[10]),
                                                                                      StringToDouble(values[11]),
                                                                                      0.0,
                                                                                      BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,
                                                                                      0.01,
                                                                                      (ulong)StringToInteger(values[12]),
                                                                                      (datetime)StringToInteger(values[13]),
                                                                                      (datetime)StringToInteger(values[14]),
                                                                                      (ENUM_BRE_ACCOUNT_POSITION_MODEL)StringToInteger(values[15]));
      return registry.TryRegister(entry);
     }
  };

#endif
