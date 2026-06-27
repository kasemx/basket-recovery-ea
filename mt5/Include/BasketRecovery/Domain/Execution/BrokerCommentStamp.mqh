#ifndef BRE_DOMAIN_BROKER_COMMENT_STAMP_MQH
#define BRE_DOMAIN_BROKER_COMMENT_STAMP_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Shared/Utils/Crc32.mqh>

class CBrokerCommentStampParsed
  {
private:
   string m_correlationToken;
   string m_basketShort;
   string m_intentCode;
   string m_checksum;
   string m_fullComment;

public:
                     CBrokerCommentStampParsed(void)
     {
      m_correlationToken="";
      m_basketShort="";
      m_intentCode="";
      m_checksum="";
      m_fullComment="";
     }

   string            CorrelationToken(void) const { return m_correlationToken; }
   string            BasketShort(void) const { return m_basketShort; }
   string            IntentCode(void) const { return m_intentCode; }
   string            Checksum(void) const { return m_checksum; }
   string            FullComment(void) const { return m_fullComment; }

   void              SetCorrelationToken(const string value) { m_correlationToken=value; }
   void              SetBasketShort(const string value) { m_basketShort=value; }
   void              SetIntentCode(const string value) { m_intentCode=value; }
   void              SetChecksum(const string value) { m_checksum=value; }
   void              SetFullComment(const string value) { m_fullComment=value; }
  };

class CBrokerCommentStamp
  {
public:
   static int        DefaultMaxLength(void) { return 31; }

   static string     IntentCode(const ENUM_BRE_TRADE_EXECUTION_INTENT intent)
     {
      switch(intent)
        {
         case BRE_EXEC_INTENT_OPEN_POSITION: return "O";
         case BRE_EXEC_INTENT_CLOSE_POSITION: return "C";
         case BRE_EXEC_INTENT_MODIFY_STOP_LOSS: return "S";
         case BRE_EXEC_INTENT_MODIFY_TAKE_PROFIT: return "T";
         case BRE_EXEC_INTENT_REDUCE_POSITION: return "R";
         case BRE_EXEC_INTENT_CANCEL_PENDING_REQUEST: return "X";
         default: return "N";
        }
     }

   static string     ShortCorrelationToken(const string executionRequestId,const string idempotencyKey)
     {
      string source=idempotencyKey!="" ? idempotencyKey : executionRequestId;
      if(source=="")
         return "00000000";
      uint crc=CCrc32::Compute(source);
      return StringSubstr(CCrc32::ToHex(crc),0,8);
     }

   static string     ShortBasketId(const CBasketId &basketId)
     {
      string value=basketId.Value();
      if(value=="")
         return "basket";
      if(StringLen(value)<=8)
         return value;
      return StringSubstr(value,StringLen(value)-8);
     }

   static string     ComputeChecksum(const string correlationToken,
                                     const string basketShort,
                                     const string intentCode)
     {
      string payload=correlationToken+"|"+basketShort+"|"+intentCode;
      uint crc=CCrc32::Compute(payload);
      return StringSubstr(CCrc32::ToHex(crc),0,4);
     }

   static bool       ValidateChecksumPayload(const string correlationToken,
                                             const string basketShort,
                                             const string intentCode,
                                             const string checksum)
     {
      if(checksum=="")
         return false;
      return ComputeChecksum(correlationToken,basketShort,intentCode)==checksum;
     }

   static string     FitSegments(string correlationToken,
                                 string basketShort,
                                 const string intentCode,
                                 const int maxLength)
     {
      string checksum=ComputeChecksum(correlationToken,basketShort,intentCode);
      string comment=StringFormat("BRE|%s|%s|%s|%s",correlationToken,basketShort,intentCode,checksum);
      if(StringLen(comment)<=maxLength)
         return comment;

      int fixedPrefix=4;
      int fixedSuffix=1+StringLen(intentCode)+1+StringLen(checksum);
      int available=maxLength-fixedPrefix-fixedSuffix-2;
      if(available<4)
         available=4;

      while(StringLen(comment)>maxLength)
        {
         if(StringLen(basketShort)>1)
            basketShort=StringSubstr(basketShort,0,StringLen(basketShort)-1);
         else if(StringLen(correlationToken)>4)
            correlationToken=StringSubstr(correlationToken,0,StringLen(correlationToken)-1);
         else
            break;
         checksum=ComputeChecksum(correlationToken,basketShort,intentCode);
         comment=StringFormat("BRE|%s|%s|%s|%s",correlationToken,basketShort,intentCode,checksum);
        }
      return comment;
     }

   static string     Build(const string executionRequestId,
                           const string idempotencyKey,
                           const CBasketId &basketId,
                           const ENUM_BRE_TRADE_EXECUTION_INTENT intent,
                           const int maxLength=31)
     {
      string correlationToken=ShortCorrelationToken(executionRequestId,idempotencyKey);
      string basketShort=ShortBasketId(basketId);
      string intentCode=IntentCode(intent);
      return FitSegments(correlationToken,basketShort,intentCode,maxLength);
     }

   static bool       TryParse(const string comment,CBrokerCommentStampParsed &parsed)
     {
      parsed=CBrokerCommentStampParsed();
      if(StringFind(comment,"BRE|")!=0)
         return false;

      string parts[];
      int count=StringSplit(comment,'|',parts);
      if(count<5)
         return false;
      if(parts[0]!="BRE")
         return false;

      parsed.SetCorrelationToken(parts[1]);
      parsed.SetBasketShort(parts[2]);
      parsed.SetIntentCode(parts[3]);
      parsed.SetChecksum(parts[4]);
      parsed.SetFullComment(comment);
      return ValidateChecksumPayload(parsed.CorrelationToken(),parsed.BasketShort(),parsed.IntentCode(),parsed.Checksum());
     }

   static bool       ValidateChecksum(const string comment)
     {
      CBrokerCommentStampParsed parsed;
      return TryParse(comment,parsed);
     }

   static string     ExtractCorrelationToken(const string comment)
     {
      CBrokerCommentStampParsed parsed;
      if(!TryParse(comment,parsed))
         return "";
      return parsed.CorrelationToken();
     }
  };

#endif
