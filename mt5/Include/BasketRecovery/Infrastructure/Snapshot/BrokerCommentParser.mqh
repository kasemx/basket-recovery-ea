#ifndef BRE_INF_BROKER_COMMENT_PARSER_MQH
#define BRE_INF_BROKER_COMMENT_PARSER_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/TradeRole.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

#define BRE_BROKER_COMMENT_PARSER_PROFIT_CLOSE_BUILD_MARKER "S8C_BROKER_COMMENT_PARSER_PROFIT_CLOSE_V1"

class CBrokerCommentParser
  {
private:
   static bool       StartsWithNormalized(const string comment,const string prefix)
     {
      if(prefix=="")
         return false;
      return StringFind(comment,prefix)==0;
     }

   static void       PrintProfitCloseReconcileExclusionDiagnosticsOnce(const string comment)
     {
      static string loggedProfitCloseComments[];
      for(int i=0;i<ArraySize(loggedProfitCloseComments);i++)
        {
         if(loggedProfitCloseComments[i]==comment)
            return;
        }

      int size=ArraySize(loggedProfitCloseComments);
      ArrayResize(loggedProfitCloseComments,size+1);
      loggedProfitCloseComments[size]=comment;

      Print("broker_comment_parser_build_marker=",BRE_BROKER_COMMENT_PARSER_PROFIT_CLOSE_BUILD_MARKER);
      Print("broker_comment_parser_classification=PROFIT_CLOSE");
      Print("broker_comment_parser_basket_id=");
      Print("broker_comment_parser_reconcile_excluded=true");
     }

public:
   static CBasketId  ExtractBasketId(const string comment)
     {
      if(StartsWithNormalized(comment,"BRE|PC|"))
        {
         PrintProfitCloseReconcileExclusionDiagnosticsOnce(comment);
         return CBasketId("");
        }

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
      if(StartsWithNormalized(comment,"BRE|PC|"))
         return BRE_TRADE_ROLE_NONE;

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
