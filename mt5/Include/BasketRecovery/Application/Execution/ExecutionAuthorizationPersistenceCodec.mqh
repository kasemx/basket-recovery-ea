#ifndef BRE_APP_EXECUTION_AUTHORIZATION_PERSISTENCE_CODEC_MQH
#define BRE_APP_EXECUTION_AUTHORIZATION_PERSISTENCE_CODEC_MQH

#include <BasketRecovery/Domain/Execution/ManualDemoExecutionAuthorization.mqh>

class CExecutionAuthorizationPersistenceCodec
  {
public:
   static string     Encode(const CManualDemoExecutionAuthorization &record)
     {
      return StringFormat("AUTH|%s|%s|%s|%I64d|%s|%d|%d|%d|%d|%s",
                          record.TokenHash(),
                          record.ExecutionRequestId(),
                          record.BasketId().Value(),
                          (long)record.ExpiryUtc(),
                          record.Consumed() ? "1" : "0",
                          (int)record.Status(),
                          (int)record.Scope(),
                          (int)record.RejectionReason(),
                          (long)record.AuthorizedAtUtc(),
                          record.RejectionDetail());
     }

   static bool       TryDecode(const string line,CManualDemoExecutionAuthorization &record)
     {
      if(StringFind(line,"AUTH|")!=0)
         return false;
      string parts[];
      int count=StringSplit(line,'|',parts);
      if(count<10)
         return false;
      record.SetTokenHash(parts[1]);
      record.SetExecutionRequestId(parts[2]);
      record.SetBasketId(CBasketId(parts[3]));
      record.SetExpiryUtc((datetime)StringToInteger(parts[4]));
      record.SetConsumed(parts[5]=="1");
      record.SetStatus((ENUM_BRE_EXECUTION_AUTHORIZATION_STATUS)StringToInteger(parts[6]));
      record.SetScope((ENUM_BRE_EXECUTION_AUTHORIZATION_SCOPE)StringToInteger(parts[7]));
      record.SetRejectionReason((ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON)StringToInteger(parts[8]));
      record.SetAuthorizedAtUtc((datetime)StringToInteger(parts[9]));
      if(count>10)
         record.SetRejectionDetail(parts[10]);
      return record.TokenHash()!="";
     }
  };

#endif
