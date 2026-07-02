#property script_show_inputs
#property description "Sprint 8D: DRY_RUN preview of fresh XAUUSD OPEN_POSITION seed request. No tokens, prepare, submit, or writes."

#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

const string RETIRED_BASKET_ID="sprint8c-demo-xauusd-002";
const ulong RETIRED_TICKET_A=1516350243;
const ulong RETIRED_TICKET_B=1516503131;
const double REQUIRED_SEED_VOLUME=0.01;
const double VOLUME_TOLERANCE=0.00000001;

input string InpBasketId="";
input string InpExecutionRequestId="";
input string InpIdempotencyKey="";
input string InpSymbol="XAUUSD";
input string InpDirection="BUY";
input double InpRequestedVolume=0.01;
input long   InpExpectedBasketVersion=1;
input string InpStrategyProfileHash="";
input long   InpMagicNumber=202608401;
input ulong  InpQuoteSequence=0;
input bool   InpDryRunOnly=true;

void PrintLine(const string line)
  {
   Print(line);
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

bool RunSeedPreflight(string &directionLabelOut,bool &oldStateReuseDetectedOut,string &matchedIdentifierOut,string &failureReasonOut)
  {
   failureReasonOut="";
   directionLabelOut="";
   oldStateReuseDetectedOut=false;
   matchedIdentifierOut="";

   if(!InpDryRunOnly)
     {
      failureReasonOut="InpDryRunOnly must remain true; this script has no submit mode";
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
   if(InpSymbol!="XAUUSD")
     {
      failureReasonOut="Symbol must be XAUUSD";
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
      failureReasonOut="Requested volume must be exactly 0.01";
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

void PrintSeedSummary(const bool preflightOk,
                      const string failureReason,
                      const bool oldStateReuseDetected,
                      const string directionLabel)
  {
   PrintLine("sprint8d_seed_mode=DRY_RUN");
   PrintLine("basket_id="+InpBasketId);
   PrintLine("execution_request_id="+InpExecutionRequestId);
   PrintLine("idempotency_key="+InpIdempotencyKey);
   PrintLine("symbol="+InpSymbol);
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
   PrintLine("seed_preflight_result="+(preflightOk?"PASS":"FAIL"));
   PrintLine("seed_preflight_reason="+failureReason);
   if(preflightOk)
      PrintLine("next_safe_step=REVIEW_AND_APPROVE_CONTROLLED_DEMO_SEED");
   else
      PrintLine("next_safe_step=DO_NOT_ISSUE_TOKEN_OR_SUBMIT_ORDER");
  }

void OnStart(void)
  {
   string failureReason="";
   string directionLabel="";
   bool oldStateReuseDetected=false;
   string matchedIdentifier="";
   bool preflightOk=RunSeedPreflight(directionLabel,oldStateReuseDetected,matchedIdentifier,failureReason);
   if(directionLabel=="")
      directionLabel=InpDirection;
   PrintSeedSummary(preflightOk,failureReason,oldStateReuseDetected,directionLabel);
  }
