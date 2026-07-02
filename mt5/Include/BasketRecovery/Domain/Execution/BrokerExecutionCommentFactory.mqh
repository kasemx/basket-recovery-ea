#ifndef BRE_DOMAIN_BROKER_EXECUTION_COMMENT_FACTORY_MQH
#define BRE_DOMAIN_BROKER_EXECUTION_COMMENT_FACTORY_MQH

#include <BasketRecovery/Shared/Utils/Crc32.mqh>

#define BRE_BROKER_EXECUTION_COMMENT_FACTORY_BUILD_MARKER "S8C_BROKER_COMMENT_FACTORY_V1"
#define BRE_BROKER_COMMENT_CONSERVATIVE_MAX_LENGTH 31

class CBrokerExecutionCommentFactory
  {
public:
   static string     BuildMarker(void) { return BRE_BROKER_EXECUTION_COMMENT_FACTORY_BUILD_MARKER; }
   static int        ConservativeMaxLength(void) { return BRE_BROKER_COMMENT_CONSERVATIVE_MAX_LENGTH; }
   static string     ProfitCloseIntentCode(void) { return "PC"; }

   static string     ComputeFingerprint(const string executionRequestId,const int alternateAttempt=0)
     {
      string source=executionRequestId;
      if(alternateAttempt>0)
         source=executionRequestId+"|alt"+IntegerToString(alternateAttempt);
      if(source=="")
         return "00000000";
      uint crc=CCrc32::Compute(source);
      return StringSubstr(CCrc32::ToHex(crc),0,8);
     }

   static string     TicketSuffix(const ulong ticket)
     {
      if(ticket==0)
         return "0";
      string ticketText=IntegerToString((long)ticket);
      if(StringLen(ticketText)<=4)
         return ticketText;
      return StringSubstr(ticketText,StringLen(ticketText)-4);
     }

   static string     BuildProfitCloseComment(const string executionRequestId,
                                             const ulong ticket,
                                             const int alternateAttempt=0)
     {
      return StringFormat("BRE|PC|%s|%s",
                          ComputeFingerprint(executionRequestId,alternateAttempt),
                          TicketSuffix(ticket));
     }

   static bool       IsProfitCloseComment(const string comment)
     {
      return StringFind(comment,"BRE|PC|")==0;
     }

   static string     ExtractFingerprint(const string comment)
     {
      if(!IsProfitCloseComment(comment))
         return "";
      string parts[];
      if(StringSplit(comment,'|',parts)<4)
         return "";
      return parts[2];
     }

   static string     ExtractTicketSuffix(const string comment)
     {
      if(!IsProfitCloseComment(comment))
         return "";
      string parts[];
      if(StringSplit(comment,'|',parts)<4)
         return "";
      return parts[3];
     }

   static bool       ValidateLength(const string comment)
     {
      return StringLen(comment)>0 && StringLen(comment)<=ConservativeMaxLength();
     }

   static bool       TicketSuffixMatches(const string comment,const ulong ticket)
     {
      if(ticket==0 || !IsProfitCloseComment(comment))
         return false;
      string suffix=ExtractTicketSuffix(comment);
      if(suffix=="")
         return false;
      return suffix==TicketSuffix(ticket);
     }
  };

#endif
