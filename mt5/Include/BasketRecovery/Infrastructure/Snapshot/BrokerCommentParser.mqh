#ifndef BRE_INF_BROKER_COMMENT_PARSER_MQH
#define BRE_INF_BROKER_COMMENT_PARSER_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/TradeRole.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CBrokerCommentParser
  {
public:
   static CBasketId  ExtractBasketId(const string comment)
     {
      int brIndex=StringFind(comment,"BR:");
      if(brIndex>=0)
        {
         string remainder=StringSubstr(comment,brIndex+3);
         int separatorIndex=StringFind(remainder,":");
         if(separatorIndex>=0)
            remainder=StringSubstr(remainder,0,separatorIndex);
         return CBasketId(remainder);
        }

      int breIndex=StringFind(comment,"BRE|");
      if(breIndex>=0)
        {
         string remainder=StringSubstr(comment,breIndex+4);
         int separatorIndex=StringFind(remainder,"|");
         if(separatorIndex>=0)
            remainder=StringSubstr(remainder,0,separatorIndex);
         return CBasketId(remainder);
        }

      return CBasketId("");
     }

   static ENUM_BRE_TRADE_ROLE ExtractRole(const string comment)
     {
      int breIndex=StringFind(comment,"BRE|");
      if(breIndex>=0)
        {
         string remainder=StringSubstr(comment,breIndex+4);
         int firstSep=StringFind(remainder,"|");
         if(firstSep<0)
            return BRE_TRADE_ROLE_NONE;
         remainder=StringSubstr(remainder,firstSep+1);
         int secondSep=StringFind(remainder,"|");
         string roleToken=secondSep>=0 ? StringSubstr(remainder,0,secondSep) : remainder;
         if(roleToken=="INITIAL")
            return BRE_TRADE_ROLE_INITIAL;
         if(roleToken=="RECOVERY")
            return BRE_TRADE_ROLE_RECOVERY;
         if(roleToken=="HEDGE")
            return BRE_TRADE_ROLE_HEDGE;
         if(roleToken=="CLOSEOUT")
            return BRE_TRADE_ROLE_CLOSEOUT;
         return BRE_TRADE_ROLE_NONE;
        }

      int brIndex=StringFind(comment,"BR:");
      if(brIndex>=0)
        {
         string remainder=StringSubstr(comment,brIndex+3);
         int firstSep=StringFind(remainder,":");
         if(firstSep<0)
            return BRE_TRADE_ROLE_NONE;
         remainder=StringSubstr(remainder,firstSep+1);
         int secondSep=StringFind(remainder,":");
         string roleToken=secondSep>=0 ? StringSubstr(remainder,0,secondSep) : remainder;
         if(roleToken=="INITIAL")
            return BRE_TRADE_ROLE_INITIAL;
         if(roleToken=="RECOVERY")
            return BRE_TRADE_ROLE_RECOVERY;
        }

      return BRE_TRADE_ROLE_INITIAL;
     }

   static int        ExtractRecoveryStepIndex(const string comment)
     {
      int stepIndex=StringFind(comment,"step=");
      if(stepIndex<0)
         return 0;
      return (int)StringToInteger(StringSubstr(comment,stepIndex+5));
     }

   static string     ExtractCorrelationId(const string comment)
     {
      return comment;
     }
  };

#endif
