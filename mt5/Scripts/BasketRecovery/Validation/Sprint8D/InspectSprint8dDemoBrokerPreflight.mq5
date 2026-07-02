#property script_show_inputs
#property description "Sprint 8D: read-only D0E demo broker preflight for fresh isolated XAUUSD scenario planning."

input string InpSymbol="XAUUSD";

void PrintLine(const string line)
  {
   Print(line);
  }

string MarginModeLabel(const long marginMode)
  {
   if(marginMode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return "RETAIL_HEDGING";
   if(marginMode==ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
      return "RETAIL_NETTING";
   if(marginMode==ACCOUNT_MARGIN_MODE_EXCHANGE)
      return "EXCHANGE";
   return "UNKNOWN";
  }

string TradeModeLabel(const long tradeMode)
  {
   if(tradeMode==SYMBOL_TRADE_MODE_DISABLED)
      return "DISABLED";
   if(tradeMode==SYMBOL_TRADE_MODE_LONGONLY)
      return "LONGONLY";
   if(tradeMode==SYMBOL_TRADE_MODE_SHORTONLY)
      return "SHORTONLY";
   if(tradeMode==SYMBOL_TRADE_MODE_CLOSEONLY)
      return "CLOSEONLY";
   if(tradeMode==SYMBOL_TRADE_MODE_FULL)
      return "FULL";
   return "UNKNOWN";
  }

string FillingModeSummary(const long fillingMask)
  {
   string parts="";
   if((fillingMask & SYMBOL_FILLING_FOK)!=0)
      parts=(parts=="" ? "FOK" : parts+"|FOK");
   if((fillingMask & SYMBOL_FILLING_IOC)!=0)
      parts=(parts=="" ? "IOC" : parts+"|IOC");
   if(parts=="")
      return "NONE";
   return parts;
  }

bool IocFillingSupported(const long fillingMask)
  {
   return (fillingMask & SYMBOL_FILLING_IOC)!=0;
  }

int CountSymbolOpenPositions(const string symbol,string &summaryOut)
  {
   summaryOut="";
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0)
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=symbol)
         continue;
      count++;
      string entry=IntegerToString((long)ticket)+":"+DoubleToString(PositionGetDouble(POSITION_VOLUME),8);
      if(summaryOut!="")
         summaryOut+=",";
      summaryOut+=entry;
     }
   if(summaryOut=="")
      summaryOut="none";
   return count;
  }

string EvaluatePreflight(const string symbol,
                         const ENUM_ACCOUNT_TRADE_MODE accountTradeMode,
                         const bool accountTradeAllowed,
                         const long marginMode,
                         const long symbolTradeMode,
                         const double minVolume,
                         const double volumeStep,
                         const long fillingMask,
                         const int openPositionCount)
  {
   if(accountTradeMode!=ACCOUNT_TRADE_MODE_DEMO)
      return "Account trade mode is not DEMO";
   if(!accountTradeAllowed)
      return "Account trading is not allowed";
   if(marginMode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return "Account margin mode is not RETAIL_HEDGING";
   if(symbol!="XAUUSD")
      return "Symbol is not XAUUSD";
   if(symbolTradeMode!=SYMBOL_TRADE_MODE_FULL)
      return "Symbol trade mode does not allow full trading";
   if(minVolume<=0.0)
      return "Symbol min lot must be greater than zero";
   if(volumeStep<=0.0)
      return "Symbol lot step must be greater than zero";
   if(!IocFillingSupported(fillingMask))
      return "IOC filling is not supported for symbol";
   if(openPositionCount!=0)
      return "Open XAUUSD position count must be zero";
   return "";
  }

void OnStart(void)
  {
   const string symbol=InpSymbol;
   SymbolSelect(symbol,true);

   const string terminalDataPath=TerminalInfoString(TERMINAL_DATA_PATH);
   const ENUM_ACCOUNT_TRADE_MODE accountTradeMode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   const string accountTradeModeLabel=(accountTradeMode==ACCOUNT_TRADE_MODE_DEMO ? "DEMO" : "REAL");
   const bool accountTradeAllowed=AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)!=0;
   const long marginMode=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   const long symbolTradeMode=SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
   const double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   const double volumeStep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   const double maxVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   const long fillingMask=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);

   string openPositionsSummary="";
   const int openPositionCount=CountSymbolOpenPositions(symbol,openPositionsSummary);
   const string failureReason=EvaluatePreflight(symbol,
                                                accountTradeMode,
                                                accountTradeAllowed,
                                                marginMode,
                                                symbolTradeMode,
                                                minVolume,
                                                volumeStep,
                                                fillingMask,
                                                openPositionCount);
   const bool preflightOk=(failureReason=="");

   PrintLine("terminal_data_path="+terminalDataPath);
   PrintLine("account_trade_mode="+accountTradeModeLabel);
   PrintLine("account_margin_mode="+MarginModeLabel(marginMode));
   PrintLine("account_trade_allowed="+(accountTradeAllowed?"true":"false"));
   PrintLine("symbol="+symbol);
   PrintLine("symbol_trade_mode="+TradeModeLabel(symbolTradeMode));
   PrintLine("symbol_volume_min="+DoubleToString(minVolume,8));
   PrintLine("symbol_volume_step="+DoubleToString(volumeStep,8));
   PrintLine("symbol_volume_max="+DoubleToString(maxVolume,8));
   PrintLine("symbol_filling_mode="+FillingModeSummary(fillingMask));
   PrintLine("open_position_count_for_symbol="+IntegerToString(openPositionCount));
   PrintLine("open_positions_summary="+openPositionsSummary);
   PrintLine("sprint8d_preflight_result="+(preflightOk?"PASS":"FAIL"));
   PrintLine("sprint8d_preflight_reason="+failureReason);
  }
