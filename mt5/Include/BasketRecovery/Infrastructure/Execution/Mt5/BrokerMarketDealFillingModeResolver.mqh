#ifndef BRE_INF_BROKER_MARKET_DEAL_FILLING_MODE_RESOLVER_MQH
#define BRE_INF_BROKER_MARKET_DEAL_FILLING_MODE_RESOLVER_MQH

class CBrokerMarketDealFillingModeResolver
  {
public:
   static string     FormatSymbolFillingModeMask(const long mask)
     {
      string parts="";
      if((mask & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
         parts+=(parts==""?"":"|")+"FOK";
      if((mask & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
         parts+=(parts==""?"":"|")+"IOC";
      if(parts=="")
         parts="NONE";
      return parts+"("+IntegerToString(mask)+")";
     }

   static string     FormatOrderTypeFilling(const ENUM_ORDER_TYPE_FILLING filling)
     {
      if(filling==ORDER_FILLING_IOC)
         return "ORDER_FILLING_IOC";
      if(filling==ORDER_FILLING_FOK)
         return "ORDER_FILLING_FOK";
      if(filling==ORDER_FILLING_RETURN)
         return "ORDER_FILLING_RETURN";
      return "ORDER_FILLING_UNKNOWN("+IntegerToString((int)filling)+")";
     }

   static bool       TrySelectFromMask(const int mask,
                                       ENUM_ORDER_TYPE_FILLING &outFilling,
                                       string &failureReason)
     {
      failureReason="";
      outFilling=ORDER_FILLING_RETURN;
      if((mask & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
        {
         outFilling=ORDER_FILLING_IOC;
         return true;
        }
      if((mask & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
        {
         outFilling=ORDER_FILLING_FOK;
         return true;
        }
      if(mask==0)
         failureReason="SYMBOL_FILLING_MODE empty";
      else
         failureReason="No IOC or FOK filling mode supported for symbol";
      return false;
     }

   static bool       TryResolveForSymbol(const string symbol,
                                         ENUM_ORDER_TYPE_FILLING &outFilling,
                                         long &outMask,
                                         string &failureReason)
     {
      failureReason="";
      outFilling=ORDER_FILLING_RETURN;
      outMask=0;
      if(symbol=="")
        {
         failureReason="Symbol is required for filling mode resolution";
         return false;
        }
      outMask=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
      return TrySelectFromMask((int)outMask,outFilling,failureReason);
     }

   static void       LogMarketDealSubmissionDiagnostics(const string resolvedSymbol,
                                                        const long symbolFillingMode,
                                                        const ENUM_ORDER_TYPE_FILLING resolvedTypeFilling,
                                                        const MqlTradeRequest &request)
     {
      Print("resolved_symbol=",resolvedSymbol,
            " symbol_filling_mode=",FormatSymbolFillingModeMask(symbolFillingMode),
            " resolved_type_filling=",FormatOrderTypeFilling(resolvedTypeFilling),
            " request_type_filling=",IntegerToString((int)request.type_filling),
            " request_action=",IntegerToString((int)request.action),
            " request_type=",IntegerToString((int)request.type));
     }

   static bool       TryApplyToMarketDealRequest(const string symbol,
                                                 MqlTradeRequest &request,
                                                 string &failureReason)
     {
      ENUM_ORDER_TYPE_FILLING resolved=ORDER_FILLING_RETURN;
      long mask=0;
      if(!TryResolveForSymbol(symbol,resolved,mask,failureReason))
        {
         Print("filling_mode_resolution=FAILED failure_reason=",failureReason);
         return false;
        }
      request.type_filling=resolved;
      Print("filling_mode_resolution=OK");
      LogMarketDealSubmissionDiagnostics(symbol,mask,resolved,request);
      return true;
     }
  };

#endif
