#property script_show_inputs
#property description "Sprint 8D: DRY_RUN seed setup preflight for fresh XAUUSD OPEN_POSITION 0.06. No writes, orders, tokens, or store mutation."

#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

const string REQUIRED_TERMINAL_DATA_ID="D0E8209F77C8CF37AD8BF550E51FF075";
const string RETIRED_BASKET_ID="sprint8c-demo-xauusd-002";
const ulong RETIRED_TICKET_A=1516350243;
const ulong RETIRED_TICKET_B=1516503131;
const double REQUIRED_SEED_VOLUME=0.06;
const double VOLUME_TOLERANCE=0.00000001;
const double EXPECTED_MIN_LOT=0.01;
const double EXPECTED_LOT_STEP=0.01;

input bool   InpDryRunOnly=true;
input string InpBasketId="";
input string InpExecutionRequestId="";
input string InpIdempotencyKey="";
input string InpSymbol="XAUUSD";
input string InpDirection="BUY";
input double InpRequestedVolume=0.06;
input long   InpExpectedBasketVersion=1;
input string InpStrategyProfileHash="";
input long   InpMagicNumber=202608401;
input ulong  InpQuoteSequence=0;

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

int CountSymbolOpenPositions(const string symbol)
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0)
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=symbol)
         continue;
      count++;
     }
   return count;
  }

bool FieldContainsRetiredIdentifier(const string value,string &matchedOut)
  {
   matchedOut="";
   if(value==RETIRED_BASKET_ID)
     {
      matchedOut=RETIRED_BASKET_ID;
      return true;
     }
   if(StringFind(value,RETIRED_BASKET_ID)>=0)
     {
      matchedOut=RETIRED_BASKET_ID;
      return true;
     }
   if(StringFind(value,IntegerToString((long)RETIRED_TICKET_A))>=0)
     {
      matchedOut=IntegerToString((long)RETIRED_TICKET_A);
      return true;
     }
   if(StringFind(value,IntegerToString((long)RETIRED_TICKET_B))>=0)
     {
      matchedOut=IntegerToString((long)RETIRED_TICKET_B);
      return true;
     }
   return false;
  }

bool TryParseDirection(const string value,ENUM_BRE_TRADE_DIRECTION &directionOut,string &normalizedOut)
  {
   string normalized=value;
   StringToUpper(normalized);
   if(normalized=="BUY")
     {
      directionOut=BRE_DIRECTION_BUY;
      normalizedOut="BUY";
      return true;
     }
   if(normalized=="SELL")
     {
      directionOut=BRE_DIRECTION_SELL;
      normalizedOut="SELL";
      return true;
     }
   directionOut=BRE_DIRECTION_NONE;
   normalizedOut="";
   return false;
  }

bool VolumeMatchesRequiredSeedVolume(const double volume)
  {
   return MathAbs(volume-REQUIRED_SEED_VOLUME)<=VOLUME_TOLERANCE;
  }

bool VolumeStepCompatible(const double minVolume,const double volumeStep)
  {
   if(minVolume<=0.0 || volumeStep<=0.0)
      return false;
   if(MathAbs(minVolume-EXPECTED_MIN_LOT)>VOLUME_TOLERANCE)
      return false;
   if(MathAbs(volumeStep-EXPECTED_LOT_STEP)>VOLUME_TOLERANCE)
      return false;
   return true;
  }

bool DetectOldSprint8cStateReuse(string &matchedIdentifierOut)
  {
   matchedIdentifierOut="";
   string matched="";

   if(InpBasketId==RETIRED_BASKET_ID)
     {
      matchedIdentifierOut=RETIRED_BASKET_ID;
      return true;
     }
   if(FieldContainsRetiredIdentifier(InpBasketId,matched))
     {
      matchedIdentifierOut=matched;
      return true;
     }
   if(FieldContainsRetiredIdentifier(InpExecutionRequestId,matched))
     {
      matchedIdentifierOut=matched;
      return true;
     }
   if(FieldContainsRetiredIdentifier(InpIdempotencyKey,matched))
     {
      matchedIdentifierOut=matched;
      return true;
     }
   if(FieldContainsRetiredIdentifier(InpSymbol,matched))
     {
      matchedIdentifierOut=matched;
      return true;
     }
   if(FieldContainsRetiredIdentifier(InpStrategyProfileHash,matched))
     {
      matchedIdentifierOut=matched;
      return true;
     }
   return false;
  }

bool TerminalDataPathMatchesD0E(const string terminalDataPath)
  {
   string upper=terminalDataPath;
   StringToUpper(upper);
   return StringFind(upper,REQUIRED_TERMINAL_DATA_ID)>=0;
  }

bool RunSeedSetupPreflight(const string terminalDataPath,
                           const string accountTradeModeLabel,
                           const string accountMarginModeLabel,
                           const bool accountTradeAllowed,
                           const string symbolTradeModeLabel,
                           const double minVolume,
                           const double volumeStep,
                           const string fillingModeLabel,
                           const int openPositionCount,
                           string &directionLabelOut,
                           bool &oldStateReuseDetectedOut,
                           string &matchedIdentifierOut,
                           string &failureReasonOut)
  {
   failureReasonOut="";
   directionLabelOut="";
   oldStateReuseDetectedOut=false;
   matchedIdentifierOut="";

   if(!InpDryRunOnly)
     {
      failureReasonOut="InpDryRunOnly must remain true; this script has no write mode";
      return false;
     }
   if(!TerminalDataPathMatchesD0E(terminalDataPath))
     {
      failureReasonOut="Terminal data path is not the required D0E validation terminal";
      return false;
     }
   if(accountTradeModeLabel!="DEMO")
     {
      failureReasonOut="Account trade mode is not DEMO";
      return false;
     }
   if(accountMarginModeLabel!="RETAIL_HEDGING")
     {
      failureReasonOut="Account margin mode is not RETAIL_HEDGING";
      return false;
     }
   if(!accountTradeAllowed)
     {
      failureReasonOut="Account trading is not allowed";
      return false;
     }
   if(InpSymbol!="XAUUSD")
     {
      failureReasonOut="Symbol must be XAUUSD";
      return false;
     }
   if(symbolTradeModeLabel!="FULL")
     {
      failureReasonOut="Symbol trade mode does not allow full trading";
      return false;
     }
   if(!VolumeStepCompatible(minVolume,volumeStep))
     {
      failureReasonOut="Symbol volume min/step are not 0.01-compatible";
      return false;
     }
   if(fillingModeLabel=="NONE" || StringFind(fillingModeLabel,"IOC")<0)
     {
      failureReasonOut="IOC filling is not supported for symbol";
      return false;
     }
   if(openPositionCount!=0)
     {
      failureReasonOut="Open XAUUSD position count must be zero";
      return false;
     }
   if(InpBasketId=="")
     {
      failureReasonOut="Basket id empty";
      return false;
     }
   if(InpBasketId==RETIRED_BASKET_ID)
     {
      oldStateReuseDetectedOut=true;
      matchedIdentifierOut=RETIRED_BASKET_ID;
      failureReasonOut="Basket id equals retired Sprint 8C basket sprint8c-demo-xauusd-002";
      return false;
     }
   if(InpExecutionRequestId=="")
     {
      failureReasonOut="Execution request id empty";
      return false;
     }
   if(InpIdempotencyKey=="")
     {
      failureReasonOut="Idempotency key empty";
      return false;
     }
   ENUM_BRE_TRADE_DIRECTION direction=BRE_DIRECTION_NONE;
   string directionLabel="";
   if(!TryParseDirection(InpDirection,direction,directionLabel))
     {
      failureReasonOut="Direction must be BUY or SELL";
      return false;
     }
   directionLabelOut=directionLabel;
   if(!VolumeMatchesRequiredSeedVolume(InpRequestedVolume))
     {
      failureReasonOut="Requested volume must be exactly 0.06";
      return false;
     }
   if(InpExpectedBasketVersion<=0)
     {
      failureReasonOut="Expected basket version must be greater than zero";
      return false;
     }
   if(InpStrategyProfileHash=="")
     {
      failureReasonOut="Strategy profile hash empty";
      return false;
     }
   if(InpQuoteSequence<=0)
     {
      failureReasonOut="Quote sequence invalid";
      return false;
     }
   if(DetectOldSprint8cStateReuse(matchedIdentifierOut))
     {
      oldStateReuseDetectedOut=true;
      failureReasonOut="Retired Sprint 8C identifier detected in supplied fields: "+matchedIdentifierOut;
      return false;
     }
   return true;
  }

void PrintSeedSetupSummary(const bool preflightOk,
                           const string failureReason,
                           const bool oldStateReuseDetected,
                           const string directionLabel,
                           const string terminalDataPath,
                           const string accountTradeModeLabel,
                           const string accountMarginModeLabel,
                           const bool accountTradeAllowed,
                           const string symbolTradeModeLabel,
                           const double minVolume,
                           const double volumeStep,
                           const string fillingModeLabel,
                           const int openPositionCount)
  {
   PrintLine("sprint8d_seed_setup_mode=DRY_RUN");
   PrintLine("terminal_data_path="+terminalDataPath);
   PrintLine("account_trade_mode="+accountTradeModeLabel);
   PrintLine("account_margin_mode="+accountMarginModeLabel);
   PrintLine("account_trade_allowed="+(accountTradeAllowed?"true":"false"));
   PrintLine("symbol="+InpSymbol);
   PrintLine("symbol_trade_mode="+symbolTradeModeLabel);
   PrintLine("symbol_volume_min="+DoubleToString(minVolume,8));
   PrintLine("symbol_volume_step="+DoubleToString(volumeStep,8));
   PrintLine("symbol_filling_mode="+fillingModeLabel);
   PrintLine("open_position_count_for_symbol="+IntegerToString(openPositionCount));
   PrintLine("basket_id="+InpBasketId);
   PrintLine("execution_request_id="+InpExecutionRequestId);
   PrintLine("idempotency_key="+InpIdempotencyKey);
   PrintLine("intent=OPEN_POSITION");
   PrintLine("direction="+directionLabel);
   PrintLine("requested_volume="+DoubleToString(InpRequestedVolume,8));
   PrintLine("requested_stop_loss=0");
   PrintLine("requested_take_profit=0");
   PrintLine("expected_basket_version="+IntegerToString((int)InpExpectedBasketVersion));
   PrintLine("strategy_profile_hash="+InpStrategyProfileHash);
   PrintLine("magic_number="+IntegerToString((int)InpMagicNumber));
   PrintLine("quote_sequence="+IntegerToString((long)InpQuoteSequence));
   PrintLine("old_sprint8c_state_reuse_detected="+(oldStateReuseDetected?"true":"false"));
   PrintLine("seed_setup_preflight_result="+(preflightOk?"PASS":"FAIL"));
   PrintLine("seed_setup_preflight_reason="+failureReason);
   if(preflightOk)
      PrintLine("next_safe_step=REVIEW_WRITE_MODE_DESIGN_WITHOUT_GLOBAL_STORE_CLEAR");
   else
      PrintLine("next_safe_step=DO_NOT_WRITE_STATE_OR_SUBMIT_ORDER");
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
   const string accountMarginModeLabel=MarginModeLabel(marginMode);
   const long symbolTradeMode=SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
   const string symbolTradeModeLabel=TradeModeLabel(symbolTradeMode);
   const double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   const double volumeStep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   const long fillingMask=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   const string fillingModeLabel=FillingModeSummary(fillingMask);
   const int openPositionCount=CountSymbolOpenPositions(symbol);

   string failureReason="";
   string directionLabel="";
   bool oldStateReuseDetected=false;
   string matchedIdentifier="";
   bool preflightOk=RunSeedSetupPreflight(terminalDataPath,
                                          accountTradeModeLabel,
                                          accountMarginModeLabel,
                                          accountTradeAllowed,
                                          symbolTradeModeLabel,
                                          minVolume,
                                          volumeStep,
                                          fillingModeLabel,
                                          openPositionCount,
                                          directionLabel,
                                          oldStateReuseDetected,
                                          matchedIdentifier,
                                          failureReason);
   if(directionLabel=="")
      directionLabel=InpDirection;
   PrintSeedSetupSummary(preflightOk,
                         failureReason,
                         oldStateReuseDetected,
                         directionLabel,
                         terminalDataPath,
                         accountTradeModeLabel,
                         accountMarginModeLabel,
                         accountTradeAllowed,
                         symbolTradeModeLabel,
                         minVolume,
                         volumeStep,
                         fillingModeLabel,
                         openPositionCount);
  }
