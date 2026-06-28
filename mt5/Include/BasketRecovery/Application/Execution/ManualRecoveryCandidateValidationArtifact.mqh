#ifndef BRE_APP_MANUAL_RC_VALIDATION_ARTIFACT_MQH
#define BRE_APP_MANUAL_RC_VALIDATION_ARTIFACT_MQH

#include <BasketRecovery/Domain/Execution/ValueObjects/ManualRecoveryCandidateEntry.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateRegistry.mqh>

class CManualRecoveryCandidateValidationArtifact
  {
public:
   static string     DefaultRelativePath(void) { return "BasketRecovery/validation/sprint-7d-live-candidate.txt"; }

   static bool       WriteEntry(const CManualRecoveryCandidateEntry &entry,
                                const string projectedRiskAllowed,
                                const string candidateStatus)
     {
      int handle=FileOpen(DefaultRelativePath(),FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(handle==INVALID_HANDLE)
         return false;

      FileWriteString(handle,"candidate_id="+entry.CandidateId()+"\r\n");
      FileWriteString(handle,"execution_request_id="+entry.ExecutionRequestId()+"\r\n");
      FileWriteString(handle,"basket_id="+entry.BasketId().Value()+"\r\n");
      FileWriteString(handle,"strategy_profile_hash="+entry.StrategyProfileHash()+"\r\n");
      FileWriteString(handle,"basket_version="+IntegerToString((int)entry.BasketVersion())+"\r\n");
      FileWriteString(handle,"symbol="+entry.Symbol()+"\r\n");
      FileWriteString(handle,"direction="+IntegerToString((int)entry.Direction())+"\r\n");
      FileWriteString(handle,"recovery_step_index="+IntegerToString(entry.RecoveryStepIndex())+"\r\n");
      FileWriteString(handle,"proposed_volume="+DoubleToString(entry.ProposedVolume(),8)+"\r\n");
      FileWriteString(handle,"basket_stop_loss="+DoubleToString(entry.BasketStopLoss(),8)+"\r\n");
      FileWriteString(handle,"current_sl_risk="+DoubleToString(entry.CurrentSlRisk(),4)+"\r\n");
      FileWriteString(handle,"projected_sl_risk="+DoubleToString(entry.ProjectedSlRisk(),4)+"\r\n");
      FileWriteString(handle,"target_risk="+DoubleToString(entry.TargetRisk(),4)+"\r\n");
      FileWriteString(handle,"max_risk="+DoubleToString(entry.MaxRisk(),4)+"\r\n");
      FileWriteString(handle,"quote_sequence="+IntegerToString((long)entry.QuoteSequence())+"\r\n");
      FileWriteString(handle,"created_at_utc="+IntegerToString((long)entry.CreatedAtUtc())+"\r\n");
      FileWriteString(handle,"expires_at_utc="+IntegerToString((long)entry.ExpiresAtUtc())+"\r\n");
      FileWriteString(handle,"candidate_status="+candidateStatus+"\r\n");
      FileWriteString(handle,"projected_max_risk_allowed="+projectedRiskAllowed+"\r\n");
      FileWriteString(handle,"artifact_written_at_utc="+IntegerToString((long)TimeCurrent())+"\r\n");
      FileClose(handle);
      return true;
     }

   static bool       TryRestoreToRegistry(CManualRecoveryCandidateRegistry &registry)
     {
      int handle=FileOpen(DefaultRelativePath(),FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(handle==INVALID_HANDLE)
         return false;

      string values[];
      ArrayResize(values,32);
      for(int i=0;i<32;i++)
         values[i]="";

      int lineIndex=0;
      while(!FileIsEnding(handle) && lineIndex<32)
        {
         string line=FileReadString(handle);
         int eq=StringFind(line,"=");
         if(eq>0)
           {
            string key=StringSubstr(line,0,eq);
            string value=StringSubstr(line,eq+1);
            if(key=="candidate_id") values[0]=value;
            else if(key=="execution_request_id") values[1]=value;
            else if(key=="basket_id") values[2]=value;
            else if(key=="strategy_profile_hash") values[3]=value;
            else if(key=="basket_version") values[4]=value;
            else if(key=="symbol") values[5]=value;
            else if(key=="direction") values[6]=value;
            else if(key=="recovery_step_index") values[7]=value;
            else if(key=="proposed_volume") values[8]=value;
            else if(key=="basket_stop_loss") values[9]=value;
            else if(key=="current_sl_risk") values[10]=value;
            else if(key=="projected_sl_risk") values[11]=value;
            else if(key=="target_risk") values[12]=value;
            else if(key=="max_risk") values[13]=value;
            else if(key=="quote_sequence") values[14]=value;
            else if(key=="created_at_utc") values[15]=value;
            else if(key=="expires_at_utc") values[16]=value;
           }
         lineIndex++;
        }
      FileClose(handle);

      if(values[0]=="" || values[1]=="" || values[2]=="")
         return false;

      CManualRecoveryCandidateEntry entry=CManualRecoveryCandidateEntry::Create(values[0],
                                                                              values[1],
                                                                              values[0],
                                                                              values[0],
                                                                              CBasketId(values[2]),
                                                                              values[3],
                                                                              (long)StringToInteger(values[4]),
                                                                              values[5],
                                                                              (ENUM_BRE_TRADE_DIRECTION)StringToInteger(values[6]),
                                                                              (int)StringToInteger(values[7]),
                                                                              0.0,
                                                                              0.0,
                                                                              0.0,
                                                                              0.0,
                                                                              0.0,
                                                                              StringToDouble(values[8]),
                                                                              StringToDouble(values[9]),
                                                                              StringToDouble(values[10]),
                                                                              StringToDouble(values[11]),
                                                                              StringToDouble(values[12]),
                                                                              StringToDouble(values[13]),
                                                                              (ulong)StringToInteger(values[14]),
                                                                              (datetime)StringToInteger(values[15]),
                                                                              (datetime)StringToInteger(values[16]));
      return registry.TryRegister(entry);
     }
  };

#endif
