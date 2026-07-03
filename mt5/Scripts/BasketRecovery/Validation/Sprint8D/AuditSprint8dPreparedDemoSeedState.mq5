#property script_show_inputs
#property description "Sprint 8D: read-only audit of prepared D0E demo seed state. No writes, tokens, or broker submission."

#include <BasketRecovery/Validation/Sprint8D/Sprint8dDemoM123StrategyProfile.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRequestFingerprint.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionEnvelope.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>

const string REQUIRED_TERMINAL_DATA_PATH="C:\\Users\\a_fea\\AppData\\Roaming\\MetaQuotes\\Terminal\\D0E8209F77C8CF37AD8BF550E51FF075";
const string PENDING_STORE_RELATIVE_PATH="BasketRecovery/pending_executions.dat";
const string TARGET_BASKET_ID="sprint8d-demo-xauusd-m123-001";
const string TARGET_EXECUTION_REQUEST_ID="demo-open-seed:8d9e2-m123-001";
const string TARGET_IDEMPOTENCY_KEY="demo-open-seed:sprint8d-demo-xauusd-m123-001:q:1001";
const string TARGET_SYMBOL="XAUUSD";
const string TARGET_CANONICAL_HASH="53426F50";
const long   TARGET_BASKET_VERSION=5;
const long   TARGET_MAGIC_NUMBER=202608401;
const double TARGET_REQUESTED_VOLUME=0.06;
const double VOLUME_TOLERANCE=0.00000001;
const double EXPECTED_MIN_LOT=0.01;
const double EXPECTED_LOT_STEP=0.01;
const string RETIRED_BASKET_ID="sprint8c-demo-xauusd-002";
const ulong RETIRED_TICKET_A=1516350243;
const ulong RETIRED_TICKET_B=1516503131;

struct SPreparedStateAuditReport
  {
   string terminalDataPath;
   string accountTradeMode;
   string accountMarginMode;
   string accountTradeAllowed;
   string openPositionCountForSymbol;
   string canonicalStrategyId;
   string canonicalStrategyProfileHash;
   string canonicalHashVerification;
   string basketExists;
   string basketLifecycle;
   string basketVersion;
   string basketProfileHash;
   string pendingRestoreOutcome;
   string pendingExists;
   string pendingStatus;
   string envelopeExists;
   string pendingRequestId;
   string pendingIdempotencyKey;
   string pendingExpectedBasketVersion;
   string pendingSymbol;
   string pendingDirection;
   string pendingRequestedVolume;
   string pendingTicket;
   string pendingStopLoss;
   string pendingTakeProfit;
   string envelopeFingerprintMatches;
   string auditResult;
   string auditReason;
   string nextSafeStep;
  };

void PrintLine(const string line)
  {
   Print(line);
  }

void AppendReason(string &reasons,const string reason)
  {
   if(reason=="")
      return;
   if(reasons!="")
      reasons=reasons+"; ";
   reasons=reasons+reason;
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

bool BasketContainsRetiredIdentity(const CBasketAggregate &basket,string &matchedOut)
  {
   if(FieldContainsRetiredIdentifier(basket.Id().Value(),matchedOut))
      return true;
   if(FieldContainsRetiredIdentifier(basket.StrategyId(),matchedOut))
      return true;
   if(FieldContainsRetiredIdentifier(basket.StrategyProfileHash(),matchedOut))
      return true;
   if(FieldContainsRetiredIdentifier(basket.CorrelationKey(),matchedOut))
      return true;
   return false;
  }

bool FindPendingEntryByRequestId(CFilePendingExecutionStore &store,
                                 const string executionRequestId,
                                 CPendingExecutionEntry &entryOut)
  {
   CPendingExecutionEntry entries[];
   const int count=store.RestoreEntries(entries);
   for(int i=0;i<count;i++)
     {
      if(entries[i].ExecutionRequestId()==executionRequestId)
        {
         entryOut=entries[i];
         return true;
        }
     }
   return false;
  }

bool VerifyCanonicalProfile(string &reasons)
  {
   const string canonicalJson=CSprint8dDemoM123StrategyProfile::CanonicalJson();
   const string expectedHash=CSprint8dDemoM123StrategyProfile::ExpectedHash();
   const string computedHash=CStrategyProfileCanonicalSerializer::ComputeHash(canonicalJson);
   bool ok=true;
   if(CSprint8dDemoM123StrategyProfile::StrategyId()!="sprint-8d-demo-xauusd-m123-v1")
     {
      AppendReason(reasons,"Canonical strategy id mismatch");
      ok=false;
     }
   if(expectedHash!=TARGET_CANONICAL_HASH)
     {
      AppendReason(reasons,"ExpectedHash constant mismatch");
      ok=false;
     }
   if(computedHash!=expectedHash)
     {
      AppendReason(reasons,"Computed canonical hash mismatch");
      ok=false;
     }
   return ok;
  }

bool WaitForD0EBrokerAuthorization(string &failureReasonOut)
  {
   failureReasonOut="";
   const int maxAttempts=120;
   for(int attempt=0;attempt<maxAttempts;attempt++)
     {
      const bool tradeAllowed=AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)!=0;
      const string marginMode=MarginModeLabel(AccountInfoInteger(ACCOUNT_MARGIN_MODE));
      if(tradeAllowed && marginMode=="RETAIL_HEDGING")
         return true;
      Sleep(500);
     }
   failureReasonOut="Timed out waiting for D0E RETAIL_HEDGING broker authorization";
   return false;
  }

bool VerifyEnvironment(const string symbol,
                       SPreparedStateAuditReport &report,
                       string &reasons)
  {
   bool ok=true;
   report.terminalDataPath=TerminalInfoString(TERMINAL_DATA_PATH);
   if(report.terminalDataPath!=REQUIRED_TERMINAL_DATA_PATH)
     {
      AppendReason(reasons,"Terminal data path is not the required D0E validation terminal");
      ok=false;
     }

   const ENUM_ACCOUNT_TRADE_MODE accountTradeMode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   report.accountTradeMode=(accountTradeMode==ACCOUNT_TRADE_MODE_DEMO ? "DEMO" : "REAL");
   if(report.accountTradeMode!="DEMO")
     {
      AppendReason(reasons,"Account trade mode is not DEMO");
      ok=false;
     }

   report.accountMarginMode=MarginModeLabel(AccountInfoInteger(ACCOUNT_MARGIN_MODE));
   if(report.accountMarginMode!="RETAIL_HEDGING")
     {
      AppendReason(reasons,"Account margin mode is not RETAIL_HEDGING");
      ok=false;
     }

   const bool tradeAllowed=AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)!=0;
   report.accountTradeAllowed=(tradeAllowed?"true":"false");
   if(!tradeAllowed)
     {
      AppendReason(reasons,"Account trading is not allowed");
      ok=false;
     }

   SymbolSelect(symbol,true);
   if(TradeModeLabel(SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE))!="FULL")
     {
      AppendReason(reasons,"Symbol trade mode is not FULL");
      ok=false;
     }

   const double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   const double volumeStep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(MathAbs(minVolume-EXPECTED_MIN_LOT)>VOLUME_TOLERANCE)
     {
      AppendReason(reasons,"Symbol min lot is not 0.01");
      ok=false;
     }
   if(MathAbs(volumeStep-EXPECTED_LOT_STEP)>VOLUME_TOLERANCE)
     {
      AppendReason(reasons,"Symbol lot step is not 0.01");
      ok=false;
     }

   const string fillingMode=FillingModeSummary(SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE));
   if(fillingMode=="NONE" || StringFind(fillingMode,"IOC")<0)
     {
      AppendReason(reasons,"IOC filling is not supported for symbol");
      ok=false;
     }

   const int openPositionCount=CountSymbolOpenPositions(symbol);
   report.openPositionCountForSymbol=IntegerToString(openPositionCount);
   if(openPositionCount!=0)
     {
      AppendReason(reasons,"Open XAUUSD position count must be zero");
      ok=false;
     }
   return ok;
  }

bool VerifyBasket(SPreparedStateAuditReport &report,string &reasons)
  {
   CFileBasketRepository repository(BRE_PERSISTENCE_BASKET_SUBDIR);
   const CBasketId basketId(TARGET_BASKET_ID);
   if(!repository.Exists(basketId))
     {
      report.basketExists="false";
      report.basketLifecycle="MISSING";
      report.basketVersion="0";
      report.basketProfileHash="";
      AppendReason(reasons,"Target basket does not exist");
      return false;
     }

   report.basketExists="true";
   CResult<CBasketAggregate> loaded=repository.Load(basketId);
   if(loaded.IsFail())
     {
      report.basketLifecycle="LOAD_FAILED";
      report.basketVersion="0";
      report.basketProfileHash="";
      AppendReason(reasons,"Target basket could not be loaded");
      return false;
     }

   CBasketAggregate basket;
   loaded.TryGetValue(basket);
   report.basketLifecycle=CBasketLifecycleStateHelper::ToString(basket.LifecycleState());
   report.basketVersion=IntegerToString((int)basket.Version());
   report.basketProfileHash=basket.StrategyProfileHash();

   bool ok=true;
   if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
     {
      AppendReason(reasons,"Basket lifecycle is not ACTIVE");
      ok=false;
     }
   if((long)basket.Version()!=TARGET_BASKET_VERSION)
     {
      AppendReason(reasons,"Basket version mismatch");
      ok=false;
     }
   if(basket.StrategyProfileHash()!=TARGET_CANONICAL_HASH)
     {
      AppendReason(reasons,"Basket strategy profile hash mismatch");
      ok=false;
     }
   if(basket.StrategyId()!=CSprint8dDemoM123StrategyProfile::StrategyId())
     {
      AppendReason(reasons,"Basket strategy id mismatch");
      ok=false;
     }
   if(basket.Symbol()!=TARGET_SYMBOL)
     {
      AppendReason(reasons,"Basket symbol mismatch");
      ok=false;
     }
   if(basket.Direction()!=BRE_DIRECTION_BUY)
     {
      AppendReason(reasons,"Basket direction mismatch");
      ok=false;
     }

   string retiredMatch="";
   if(BasketContainsRetiredIdentity(basket,retiredMatch))
     {
      AppendReason(reasons,"Retired Sprint 8C identity detected in basket: "+retiredMatch);
      ok=false;
     }
   return ok;
  }

bool VerifyPendingAndEnvelope(SPreparedStateAuditReport &report,string &reasons)
  {
   CFilePendingExecutionStore store(PENDING_STORE_RELATIVE_PATH);
   CVoidResult restoreResult=store.RestoreFromDisk();
   report.pendingRestoreOutcome=store.LastRestoreOutcome();
   if(restoreResult.IsFail())
     {
      report.pendingExists="false";
      report.pendingStatus="MISSING";
      report.envelopeExists="false";
      report.pendingRequestId="";
      report.pendingIdempotencyKey="";
      report.pendingExpectedBasketVersion="0";
      report.pendingSymbol="";
      report.pendingDirection="";
      report.pendingRequestedVolume="0";
      report.pendingTicket="0";
      report.pendingStopLoss="0";
      report.pendingTakeProfit="0";
      report.envelopeFingerprintMatches="false";
      AppendReason(reasons,"Pending restore failed: "+restoreResult.ErrorMessage());
      return false;
     }

   if(report.pendingRestoreOutcome==BRE_PENDING_RESTORE_OUTCOME_PRISTINE_EMPTY)
     {
      AppendReason(reasons,"Pending store is empty");
     }

   CPendingExecutionEntry entry;
   const bool pendingFound=FindPendingEntryByRequestId(store,TARGET_EXECUTION_REQUEST_ID,entry);
   report.pendingExists=(pendingFound?"true":"false");
   report.pendingRequestId=(pendingFound?entry.ExecutionRequestId():"");
   report.pendingIdempotencyKey=(pendingFound?entry.IdempotencyKey():"");
   report.pendingExpectedBasketVersion=(pendingFound?IntegerToString(entry.ExpectedBasketVersion()):"0");
   report.pendingSymbol=(pendingFound?entry.Symbol():"");
   report.pendingRequestedVolume=(pendingFound?DoubleToString(entry.RequestedVolume(),8):"0");
   report.pendingStatus=(pendingFound?TradeExecutionStatusLabel(entry.Status()):"MISSING");

   CResult<CBrokerSubmissionEnvelope> envelopeResult=store.FindEnvelopeByIdempotencyKey(TARGET_IDEMPOTENCY_KEY);
   CBrokerSubmissionEnvelope envelope;
   const bool envelopeFound=envelopeResult.TryGetValue(envelope);
   report.envelopeExists=(envelopeFound?"true":"false");

   if(envelopeFound)
     {
      report.pendingDirection=CTradeDirectionHelper::ToString(envelope.Direction());
      report.pendingTicket=IntegerToString((long)envelope.Ticket());
      report.pendingStopLoss=DoubleToString(envelope.RequestedStopLoss(),8);
      report.pendingTakeProfit=DoubleToString(envelope.RequestedTakeProfit(),8);
     }
   else
     {
      report.pendingDirection="";
      report.pendingTicket="0";
      report.pendingStopLoss="0";
      report.pendingTakeProfit="0";
     }

   bool ok=true;
   if(!pendingFound)
     {
      AppendReason(reasons,"Target pending entry missing");
      ok=false;
     }
   if(!envelopeFound)
     {
      AppendReason(reasons,"Target envelope missing");
      ok=false;
     }
   if(!ok)
     {
      report.envelopeFingerprintMatches="false";
      return false;
     }

   if(entry.Status()!=BRE_TRADE_EXEC_STATUS_QUEUED)
     {
      AppendReason(reasons,"Pending status is not QUEUED");
      ok=false;
     }
   if(entry.IntentType()!=BRE_EXEC_INTENT_OPEN_POSITION)
     {
      AppendReason(reasons,"Pending intent is not OPEN_POSITION");
      ok=false;
     }
   if(entry.BasketId().Value()!=TARGET_BASKET_ID)
     {
      AppendReason(reasons,"Pending basket id mismatch");
      ok=false;
     }
   if(entry.ExecutionRequestId()!=TARGET_EXECUTION_REQUEST_ID)
     {
      AppendReason(reasons,"Pending execution request id mismatch");
      ok=false;
     }
   if(entry.IdempotencyKey()!=TARGET_IDEMPOTENCY_KEY)
     {
      AppendReason(reasons,"Pending idempotency key mismatch");
      ok=false;
     }
   if(entry.ExpectedBasketVersion()!=(int)TARGET_BASKET_VERSION)
     {
      AppendReason(reasons,"Pending expected basket version mismatch");
      ok=false;
     }
   if(entry.StrategyProfileHash()!=TARGET_CANONICAL_HASH)
     {
      AppendReason(reasons,"Pending strategy profile hash mismatch");
      ok=false;
     }
   if(entry.Symbol()!=TARGET_SYMBOL)
     {
      AppendReason(reasons,"Pending symbol mismatch");
      ok=false;
     }
   if(!MathIsValidNumber(entry.RequestedVolume()) ||
      MathAbs(entry.RequestedVolume()-TARGET_REQUESTED_VOLUME)>VOLUME_TOLERANCE)
     {
      AppendReason(reasons,"Pending requested volume mismatch");
      ok=false;
     }

   if(envelope.ExecutionRequestId()!=TARGET_EXECUTION_REQUEST_ID)
     {
      AppendReason(reasons,"Envelope execution request id mismatch");
      ok=false;
     }
   if(envelope.IdempotencyKey()!=TARGET_IDEMPOTENCY_KEY)
     {
      AppendReason(reasons,"Envelope idempotency key mismatch");
      ok=false;
     }
   if(envelope.BasketId().Value()!=TARGET_BASKET_ID)
     {
      AppendReason(reasons,"Envelope basket id mismatch");
      ok=false;
     }
   if(envelope.ExpectedBasketVersion()!=(int)TARGET_BASKET_VERSION)
     {
      AppendReason(reasons,"Envelope expected basket version mismatch");
      ok=false;
     }
   if(envelope.StrategyProfileHash()!=TARGET_CANONICAL_HASH)
     {
      AppendReason(reasons,"Envelope strategy profile hash mismatch");
      ok=false;
     }
   if(envelope.Symbol()!=TARGET_SYMBOL)
     {
      AppendReason(reasons,"Envelope symbol mismatch");
      ok=false;
     }
   if(envelope.Direction()!=BRE_DIRECTION_BUY)
     {
      AppendReason(reasons,"Envelope direction mismatch");
      ok=false;
     }
   if(envelope.IntentType()!=BRE_EXEC_INTENT_OPEN_POSITION)
     {
      AppendReason(reasons,"Envelope intent mismatch");
      ok=false;
     }
   if(envelope.Ticket()!=0)
     {
      AppendReason(reasons,"Envelope ticket must be zero before submission");
      ok=false;
     }
   if(MathAbs(envelope.RequestedStopLoss())>VOLUME_TOLERANCE)
     {
      AppendReason(reasons,"Envelope stop loss must be zero");
      ok=false;
     }
   if(MathAbs(envelope.RequestedTakeProfit())>VOLUME_TOLERANCE)
     {
      AppendReason(reasons,"Envelope take profit must be zero");
      ok=false;
     }
   if(!MathIsValidNumber(envelope.RequestedVolume()) ||
      MathAbs(envelope.RequestedVolume()-TARGET_REQUESTED_VOLUME)>VOLUME_TOLERANCE)
     {
      AppendReason(reasons,"Envelope requested volume mismatch");
      ok=false;
     }
   if(envelope.MagicNumber()!=TARGET_MAGIC_NUMBER)
     {
      AppendReason(reasons,"Envelope magic number mismatch");
      ok=false;
     }

   CTradeExecutionRequest reconstructed=CTradeExecutionRequest::Create(TARGET_EXECUTION_REQUEST_ID,
                                                                       TARGET_IDEMPOTENCY_KEY,
                                                                       "corr-"+TARGET_EXECUTION_REQUEST_ID,
                                                                       CBasketId(TARGET_BASKET_ID),
                                                                       TARGET_BASKET_VERSION,
                                                                       TARGET_CANONICAL_HASH,
                                                                       TARGET_SYMBOL,
                                                                       BRE_EXEC_INTENT_OPEN_POSITION,
                                                                       envelope.Direction(),
                                                                       envelope.Ticket(),
                                                                       envelope.RequestedVolume(),
                                                                       envelope.RequestedPrice(),
                                                                       envelope.RequestedStopLoss(),
                                                                       envelope.RequestedTakeProfit(),
                                                                       envelope.PreparedAtUtc(),
                                                                       CCommandId("cmd-sprint8d-audit"),
                                                                       "sprint8d-audit");
   const CExecutionRequestFingerprint expectedFingerprint=CExecutionRequestFingerprint::Compute(reconstructed);
   const bool fingerprintMatches=(envelope.Fingerprint()==expectedFingerprint);
   report.envelopeFingerprintMatches=(fingerprintMatches?"true":"false");
   if(!fingerprintMatches)
     {
      AppendReason(reasons,"Envelope fingerprint does not match reconstructed canonical request");
      ok=false;
     }

   string retiredMatch="";
   if(FieldContainsRetiredIdentifier(entry.ExecutionRequestId(),retiredMatch) ||
      FieldContainsRetiredIdentifier(entry.IdempotencyKey(),retiredMatch) ||
      FieldContainsRetiredIdentifier(entry.BrokerComment(),retiredMatch))
     {
      AppendReason(reasons,"Retired Sprint 8C identity detected in pending: "+retiredMatch);
      ok=false;
     }
   return ok;
  }

void PrintAuditReport(const SPreparedStateAuditReport &report)
  {
   PrintLine("sprint8d_prepared_state_audit_mode=READ_ONLY");
   PrintLine("terminal_data_path="+report.terminalDataPath);
   PrintLine("account_trade_mode="+report.accountTradeMode);
   PrintLine("account_margin_mode="+report.accountMarginMode);
   PrintLine("account_trade_allowed="+report.accountTradeAllowed);
   PrintLine("open_position_count_for_symbol="+report.openPositionCountForSymbol);
   PrintLine("canonical_strategy_id="+report.canonicalStrategyId);
   PrintLine("canonical_strategy_profile_hash="+report.canonicalStrategyProfileHash);
   PrintLine("canonical_hash_verification="+report.canonicalHashVerification);
   PrintLine("basket_exists="+report.basketExists);
   PrintLine("basket_lifecycle="+report.basketLifecycle);
   PrintLine("basket_version="+report.basketVersion);
   PrintLine("basket_profile_hash="+report.basketProfileHash);
   PrintLine("pending_restore_outcome="+report.pendingRestoreOutcome);
   PrintLine("pending_exists="+report.pendingExists);
   PrintLine("pending_status="+report.pendingStatus);
   PrintLine("envelope_exists="+report.envelopeExists);
   PrintLine("pending_request_id="+report.pendingRequestId);
   PrintLine("pending_idempotency_key="+report.pendingIdempotencyKey);
   PrintLine("pending_expected_basket_version="+report.pendingExpectedBasketVersion);
   PrintLine("pending_symbol="+report.pendingSymbol);
   PrintLine("pending_direction="+report.pendingDirection);
   PrintLine("pending_requested_volume="+report.pendingRequestedVolume);
   PrintLine("pending_ticket="+report.pendingTicket);
   PrintLine("pending_stop_loss="+report.pendingStopLoss);
   PrintLine("pending_take_profit="+report.pendingTakeProfit);
   PrintLine("envelope_fingerprint_matches="+report.envelopeFingerprintMatches);
   PrintLine("prepared_state_audit_result="+report.auditResult);
   PrintLine("prepared_state_audit_reason="+report.auditReason);
   PrintLine("next_safe_step="+report.nextSafeStep);
  }

void OnStart(void)
  {
   SPreparedStateAuditReport report;
   report.terminalDataPath="";
   report.accountTradeMode="UNKNOWN";
   report.accountMarginMode="UNKNOWN";
   report.accountTradeAllowed="false";
   report.openPositionCountForSymbol="0";
   report.canonicalStrategyId=CSprint8dDemoM123StrategyProfile::StrategyId();
   report.canonicalStrategyProfileHash=CSprint8dDemoM123StrategyProfile::ExpectedHash();
   report.canonicalHashVerification="UNKNOWN";
   report.basketExists="false";
   report.basketLifecycle="NOT_EVALUATED";
   report.basketVersion="0";
   report.basketProfileHash="";
   report.pendingRestoreOutcome="NOT_EVALUATED";
   report.pendingExists="false";
   report.pendingStatus="NOT_EVALUATED";
   report.envelopeExists="false";
   report.pendingRequestId="";
   report.pendingIdempotencyKey="";
   report.pendingExpectedBasketVersion="0";
   report.pendingSymbol="";
   report.pendingDirection="";
   report.pendingRequestedVolume="0";
   report.pendingTicket="0";
   report.pendingStopLoss="0";
   report.pendingTakeProfit="0";
   report.envelopeFingerprintMatches="false";
   report.auditResult="FAIL";
   report.auditReason="";
   report.nextSafeStep="DO_NOT_SUBMIT_OR_OVERWRITE_STATE";

   string reasons="";
   string brokerWaitReason="";
   if(!WaitForD0EBrokerAuthorization(brokerWaitReason))
      AppendReason(reasons,brokerWaitReason);

   bool canonicalOk=VerifyCanonicalProfile(reasons);
   const string computedHash=CStrategyProfileCanonicalSerializer::ComputeHash(CSprint8dDemoM123StrategyProfile::CanonicalJson());
   report.canonicalHashVerification=(canonicalOk && computedHash==TARGET_CANONICAL_HASH?"PASS":"FAIL");

   const bool environmentOk=VerifyEnvironment(TARGET_SYMBOL,report,reasons);
   VerifyBasket(report,reasons);
   VerifyPendingAndEnvelope(report,reasons);

   if(report.basketExists=="true" && report.pendingExists=="true")
     {
      if(report.basketVersion!=report.pendingExpectedBasketVersion)
         AppendReason(reasons,"Basket version does not match pending expected basket version");
      if(report.basketProfileHash!=TARGET_CANONICAL_HASH)
         AppendReason(reasons,"Basket profile hash does not match canonical hash");
      if(report.pendingIdempotencyKey==TARGET_IDEMPOTENCY_KEY &&
         report.basketProfileHash!=TARGET_CANONICAL_HASH)
         AppendReason(reasons,"Pending profile hash is not aligned with basket/canonical hash");
     }

   if(reasons=="")
     {
      report.auditResult="PASS";
      report.auditReason="";
      report.nextSafeStep="REVIEW_AND_APPROVE_SINGLE_D0E_ASYNC_SUBMISSION";
     }
   else
     {
      report.auditResult="FAIL";
      report.auditReason=reasons;
      report.nextSafeStep="DO_NOT_SUBMIT_OR_OVERWRITE_STATE";
     }

   PrintAuditReport(report);
  }
