#property script_show_inputs
#property description "Sprint 8D: validate prepared OPEN_POSITION seed and optionally issue one demo auth token. Dry-run default."

#include <BasketRecovery/Validation/Sprint8D/Sprint8dDemoM123StrategyProfile.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>
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
const double VOLUME_TOLERANCE=0.00000001;
const double EXPECTED_MIN_LOT=0.01;
const double EXPECTED_LOT_STEP=0.01;
const string RETIRED_BASKET_ID="sprint8c-demo-xauusd-002";
const ulong RETIRED_TICKET_A=1516350243;
const ulong RETIRED_TICKET_B=1516503131;

input bool   InpIssueToken=false;
input int    InpAuthorizationTokenExpirySeconds=300;
input string InpBasketId="sprint8d-demo-xauusd-m123-001";
input string InpExecutionRequestId="demo-open-seed:8d9e2-m123-001";
input string InpIdempotencyKey="demo-open-seed:sprint8d-demo-xauusd-m123-001:q:1001";
input string InpSymbol="XAUUSD";
input string InpIntent="OPEN_POSITION";
input double InpRequestedVolume=0.06;
input int    InpExpectedBasketVersion=5;
input string InpStrategyProfileHash="53426F50";

struct SOpenSeedAuthReport
  {
   string authMode;
   string basketId;
   string executionRequestId;
   string idempotencyKey;
   string canonicalStrategyProfileHash;
   string bindingFingerprint;
   string tokenExpirySeconds;
   string preparedStateVerified;
   string tokenIssued;
   string contractResult;
   string contractReason;
   string authorizationToken;
   string authorizationTokenExpiryUnix;
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
      ulong positionTicket=PositionGetTicket(i);
      if(positionTicket==0)
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

bool ResolveInputIntent(ENUM_BRE_TRADE_EXECUTION_INTENT &intentOut,string &reasons)
  {
   if(InpIntent=="OPEN_POSITION")
     {
      intentOut=BRE_EXEC_INTENT_OPEN_POSITION;
      return true;
     }
   AppendReason(reasons,"InpIntent must be OPEN_POSITION");
   return false;
  }

bool VerifyInputContract(string &reasons)
  {
   bool ok=true;
   if(InpBasketId=="")
     {
      AppendReason(reasons,"InpBasketId is required");
      ok=false;
     }
   if(InpExecutionRequestId=="")
     {
      AppendReason(reasons,"InpExecutionRequestId is required");
      ok=false;
     }
   if(InpIdempotencyKey=="")
     {
      AppendReason(reasons,"InpIdempotencyKey is required");
      ok=false;
     }
   if(InpSymbol!="XAUUSD")
     {
      AppendReason(reasons,"InpSymbol must be XAUUSD");
      ok=false;
     }
   if(InpStrategyProfileHash!="53426F50")
     {
      AppendReason(reasons,"InpStrategyProfileHash must be 53426F50");
      ok=false;
     }
   if(InpExpectedBasketVersion!=5)
     {
      AppendReason(reasons,"InpExpectedBasketVersion must be 5");
      ok=false;
     }
   if(!MathIsValidNumber(InpRequestedVolume) ||
      MathAbs(InpRequestedVolume-0.06)>VOLUME_TOLERANCE)
     {
      AppendReason(reasons,"InpRequestedVolume must be 0.06");
      ok=false;
     }
   if(InpAuthorizationTokenExpirySeconds<=0)
     {
      AppendReason(reasons,"InpAuthorizationTokenExpirySeconds must be positive");
      ok=false;
     }
   ENUM_BRE_TRADE_EXECUTION_INTENT intent=BRE_EXEC_INTENT_OPEN_POSITION;
   if(!ResolveInputIntent(intent,reasons))
      ok=false;
   return ok;
  }

bool VerifyCanonicalProfile(string &reasons)
  {
   const string computedHash=CStrategyProfileCanonicalSerializer::ComputeHash(CSprint8dDemoM123StrategyProfile::CanonicalJson());
   bool ok=true;
   if(CSprint8dDemoM123StrategyProfile::StrategyId()!="sprint-8d-demo-xauusd-m123-v1")
     {
      AppendReason(reasons,"Canonical strategy id mismatch");
      ok=false;
     }
   if(CSprint8dDemoM123StrategyProfile::ExpectedHash()!=InpStrategyProfileHash)
     {
      AppendReason(reasons,"Canonical ExpectedHash mismatch");
      ok=false;
     }
   if(computedHash!=CSprint8dDemoM123StrategyProfile::ExpectedHash())
     {
      AppendReason(reasons,"Computed canonical hash mismatch");
      ok=false;
     }
   return ok;
  }

bool VerifyD0EPreflight(const string symbol,string &reasons)
  {
   bool ok=true;
   if(TerminalInfoString(TERMINAL_DATA_PATH)!=REQUIRED_TERMINAL_DATA_PATH)
     {
      AppendReason(reasons,"Terminal data path is not the required D0E validation terminal");
      ok=false;
     }
   const ENUM_ACCOUNT_TRADE_MODE accountTradeMode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(accountTradeMode!=ACCOUNT_TRADE_MODE_DEMO)
     {
      AppendReason(reasons,"Account trade mode is not DEMO");
      ok=false;
     }
   if(MarginModeLabel(AccountInfoInteger(ACCOUNT_MARGIN_MODE))!="RETAIL_HEDGING")
     {
      AppendReason(reasons,"Account margin mode is not RETAIL_HEDGING");
      ok=false;
     }
   if(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)==0)
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
   if(CountSymbolOpenPositions(symbol)!=0)
     {
      AppendReason(reasons,"Open XAUUSD position count must be zero");
      ok=false;
     }
   return ok;
  }

bool VerifyPreparedBasket(string &reasons)
  {
   CFileBasketRepository repository(BRE_PERSISTENCE_BASKET_SUBDIR);
   const CBasketId basketId(InpBasketId);
   if(!repository.Exists(basketId))
     {
      AppendReason(reasons,"Target basket does not exist");
      return false;
     }
   CResult<CBasketAggregate> loaded=repository.Load(basketId);
   if(loaded.IsFail())
     {
      AppendReason(reasons,"Target basket could not be loaded");
      return false;
     }
   CBasketAggregate basket;
   loaded.TryGetValue(basket);
   bool ok=true;
   if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
     {
      AppendReason(reasons,"Basket lifecycle is not ACTIVE");
      ok=false;
     }
   if((int)basket.Version()!=InpExpectedBasketVersion)
     {
      AppendReason(reasons,"Basket version mismatch");
      ok=false;
     }
   if(basket.StrategyProfileHash()!=InpStrategyProfileHash)
     {
      AppendReason(reasons,"Basket strategy profile hash mismatch");
      ok=false;
     }
   if(basket.StrategyId()!=CSprint8dDemoM123StrategyProfile::StrategyId())
     {
      AppendReason(reasons,"Basket strategy id mismatch");
      ok=false;
     }
   if(basket.Symbol()!=InpSymbol)
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

bool VerifyPreparedPendingAndEnvelope(CPendingExecutionEntry &entryOut,
                                      CBrokerSubmissionEnvelope &envelopeOut,
                                      string &reasons)
  {
   ENUM_BRE_TRADE_EXECUTION_INTENT expectedIntent=BRE_EXEC_INTENT_OPEN_POSITION;
   if(!ResolveInputIntent(expectedIntent,reasons))
      return false;

   CFilePendingExecutionStore store(PENDING_STORE_RELATIVE_PATH);
   CVoidResult restoreResult=store.RestoreFromDisk();
   if(restoreResult.IsFail())
     {
      AppendReason(reasons,"Pending restore failed: "+restoreResult.ErrorMessage());
      return false;
     }
   if(store.LastRestoreOutcome()==BRE_PENDING_RESTORE_OUTCOME_PRISTINE_EMPTY)
     {
      AppendReason(reasons,"Pending store is empty");
      return false;
     }
   if(!FindPendingEntryByRequestId(store,InpExecutionRequestId,entryOut))
     {
      AppendReason(reasons,"Target pending entry missing");
      return false;
     }
   CResult<CBrokerSubmissionEnvelope> envelopeResult=store.FindEnvelopeByIdempotencyKey(InpIdempotencyKey);
   if(!envelopeResult.TryGetValue(envelopeOut))
     {
      AppendReason(reasons,"Target envelope missing");
      return false;
     }

   bool ok=true;
   if(entryOut.Status()!=BRE_TRADE_EXEC_STATUS_QUEUED)
     {
      AppendReason(reasons,"Pending status is not QUEUED");
      ok=false;
     }
   if(entryOut.IntentType()!=expectedIntent)
     {
      AppendReason(reasons,"Pending intent is not OPEN_POSITION");
      ok=false;
     }
   if(entryOut.BasketId().Value()!=InpBasketId)
     {
      AppendReason(reasons,"Pending basket id mismatch");
      ok=false;
     }
   if(entryOut.ExecutionRequestId()!=InpExecutionRequestId)
     {
      AppendReason(reasons,"Pending execution request id mismatch");
      ok=false;
     }
   if(entryOut.IdempotencyKey()!=InpIdempotencyKey)
     {
      AppendReason(reasons,"Pending idempotency key mismatch");
      ok=false;
     }
   if(entryOut.ExpectedBasketVersion()!=InpExpectedBasketVersion)
     {
      AppendReason(reasons,"Pending expected basket version mismatch");
      ok=false;
     }
   if(entryOut.StrategyProfileHash()!=InpStrategyProfileHash)
     {
      AppendReason(reasons,"Pending strategy profile hash mismatch");
      ok=false;
     }
   if(entryOut.Symbol()!=InpSymbol)
     {
      AppendReason(reasons,"Pending symbol mismatch");
      ok=false;
     }
   if(!MathIsValidNumber(entryOut.RequestedVolume()) ||
      MathAbs(entryOut.RequestedVolume()-InpRequestedVolume)>VOLUME_TOLERANCE)
     {
      AppendReason(reasons,"Pending requested volume mismatch");
      ok=false;
     }
   if(envelopeOut.Direction()!=BRE_DIRECTION_BUY)
     {
      AppendReason(reasons,"Envelope direction mismatch");
      ok=false;
     }
   if(envelopeOut.Ticket()!=0)
     {
      AppendReason(reasons,"Envelope ticket must be zero");
      ok=false;
     }
   if(MathAbs(envelopeOut.RequestedStopLoss())>VOLUME_TOLERANCE)
     {
      AppendReason(reasons,"Envelope stop loss must be zero");
      ok=false;
     }
   if(MathAbs(envelopeOut.RequestedTakeProfit())>VOLUME_TOLERANCE)
     {
      AppendReason(reasons,"Envelope take profit must be zero");
      ok=false;
     }
   if(envelopeOut.ExecutionRequestId()!=InpExecutionRequestId)
     {
      AppendReason(reasons,"Envelope execution request id mismatch");
      ok=false;
     }
   if(envelopeOut.IdempotencyKey()!=InpIdempotencyKey)
     {
      AppendReason(reasons,"Envelope idempotency key mismatch");
      ok=false;
     }
   if(envelopeOut.BasketId().Value()!=InpBasketId)
     {
      AppendReason(reasons,"Envelope basket id mismatch");
      ok=false;
     }
   if(envelopeOut.ExpectedBasketVersion()!=InpExpectedBasketVersion)
     {
      AppendReason(reasons,"Envelope expected basket version mismatch");
      ok=false;
     }
   if(envelopeOut.StrategyProfileHash()!=InpStrategyProfileHash)
     {
      AppendReason(reasons,"Envelope strategy profile hash mismatch");
      ok=false;
     }
   if(envelopeOut.Symbol()!=InpSymbol)
     {
      AppendReason(reasons,"Envelope symbol mismatch");
      ok=false;
     }
   if(!MathIsValidNumber(envelopeOut.RequestedVolume()) ||
      MathAbs(envelopeOut.RequestedVolume()-InpRequestedVolume)>VOLUME_TOLERANCE)
     {
      AppendReason(reasons,"Envelope requested volume mismatch");
      ok=false;
     }
   if(envelopeOut.IntentType()!=expectedIntent)
     {
      AppendReason(reasons,"Envelope intent mismatch");
      ok=false;
     }

   CTradeExecutionRequest reconstructed=CTradeExecutionRequest::Create(InpExecutionRequestId,
                                                                       InpIdempotencyKey,
                                                                       "corr-"+InpExecutionRequestId,
                                                                       CBasketId(InpBasketId),
                                                                       InpExpectedBasketVersion,
                                                                       InpStrategyProfileHash,
                                                                       InpSymbol,
                                                                       expectedIntent,
                                                                       envelopeOut.Direction(),
                                                                       envelopeOut.Ticket(),
                                                                       envelopeOut.RequestedVolume(),
                                                                       envelopeOut.RequestedPrice(),
                                                                       envelopeOut.RequestedStopLoss(),
                                                                       envelopeOut.RequestedTakeProfit(),
                                                                       envelopeOut.PreparedAtUtc(),
                                                                       CCommandId("cmd-sprint8d-auth-issue"),
                                                                       "sprint8d-auth");
   if(envelopeOut.Fingerprint()!=CExecutionRequestFingerprint::Compute(reconstructed))
     {
      AppendReason(reasons,"Envelope fingerprint mismatch");
      ok=false;
     }
   return ok;
  }

string ComputeAuthorizationBindingFingerprint(void)
  {
   return CExecutionAuthorizationToken::ComputeBindingFingerprint(InpExecutionRequestId,
                                                                    CBasketId(InpBasketId),
                                                                    InpSymbol,
                                                                    BRE_EXEC_INTENT_OPEN_POSITION,
                                                                    InpRequestedVolume,
                                                                    InpExpectedBasketVersion,
                                                                    InpStrategyProfileHash);
  }

void PrintAuthReport(const SOpenSeedAuthReport &report,const bool includeToken)
  {
   PrintLine("sprint8d_open_seed_auth_mode="+report.authMode);
   PrintLine("basket_id="+report.basketId);
   PrintLine("execution_request_id="+report.executionRequestId);
   PrintLine("idempotency_key="+report.idempotencyKey);
   PrintLine("canonical_strategy_profile_hash="+report.canonicalStrategyProfileHash);
   PrintLine("authorization_binding_fingerprint="+report.bindingFingerprint);
   PrintLine("authorization_token_expiry_seconds="+report.tokenExpirySeconds);
   PrintLine("prepared_state_verified="+report.preparedStateVerified);
   PrintLine("token_issued="+report.tokenIssued);
   PrintLine("authorization_contract_result="+report.contractResult);
   PrintLine("authorization_contract_reason="+report.contractReason);
   if(includeToken)
     {
      PrintLine("authorization_token="+report.authorizationToken);
      PrintLine("authorization_token_expiry_unix="+report.authorizationTokenExpiryUnix);
     }
   PrintLine("next_safe_step="+report.nextSafeStep);
  }

void OnStart(void)
  {
   SOpenSeedAuthReport report;
   report.authMode=(InpIssueToken?"ISSUE_TOKEN":"DRY_RUN");
   report.basketId=InpBasketId;
   report.executionRequestId=InpExecutionRequestId;
   report.idempotencyKey=InpIdempotencyKey;
   report.canonicalStrategyProfileHash=InpStrategyProfileHash;
   report.bindingFingerprint="";
   report.tokenExpirySeconds=IntegerToString(InpAuthorizationTokenExpirySeconds);
   report.preparedStateVerified="false";
   report.tokenIssued="false";
   report.contractResult="FAIL";
   report.contractReason="";
   report.authorizationToken="";
   report.authorizationTokenExpiryUnix="";
   report.nextSafeStep="DO_NOT_ISSUE_TOKEN_OR_SUBMIT";

   string reasons="";
   string brokerWaitReason="";
   if(!WaitForD0EBrokerAuthorization(brokerWaitReason))
      AppendReason(reasons,brokerWaitReason);

   report.bindingFingerprint=ComputeAuthorizationBindingFingerprint();

   if(VerifyInputContract(reasons))
     {
      const bool canonicalOk=VerifyCanonicalProfile(reasons);
      const bool preflightOk=VerifyD0EPreflight(InpSymbol,reasons);
      const bool basketOk=VerifyPreparedBasket(reasons);
      CPendingExecutionEntry pendingEntry;
      CBrokerSubmissionEnvelope envelope;
      const bool pendingOk=VerifyPreparedPendingAndEnvelope(pendingEntry,envelope,reasons);
      if(basketOk && pendingOk)
        {
         if(pendingEntry.ExpectedBasketVersion()!=InpExpectedBasketVersion)
            AppendReason(reasons,"Basket version does not match pending expected basket version");
         if(pendingEntry.StrategyProfileHash()!=InpStrategyProfileHash)
            AppendReason(reasons,"Basket and pending profile hash mismatch");
        }
      if(canonicalOk && preflightOk && basketOk && pendingOk && reasons=="")
         report.preparedStateVerified="true";
     }

   if(reasons=="")
     {
      report.contractResult="PASS";
      report.contractReason="";
      if(InpIssueToken)
        {
         const datetime expiryUtc=TimeCurrent()+InpAuthorizationTokenExpirySeconds;
         report.authorizationToken=CExecutionAuthorizationToken::IssuePlaintextToken(report.bindingFingerprint,
                                                                                     expiryUtc);
         report.authorizationTokenExpiryUnix=IntegerToString((long)expiryUtc);
         report.tokenIssued="true";
         report.authMode="ISSUE_TOKEN";
         report.nextSafeStep="SET_PROFILE_B_AND_SUBMIT_WITHIN_TOKEN_TTL";
        }
      else
        {
         report.authMode="DRY_RUN";
         report.tokenIssued="false";
         report.nextSafeStep="ATTACH_EA_WITH_PROFILE_A_OBSERVER_ONLY";
        }
     }
   else
     {
      report.contractResult="FAIL";
      report.contractReason=reasons;
      report.preparedStateVerified="false";
      report.tokenIssued="false";
      report.nextSafeStep="DO_NOT_ISSUE_TOKEN_OR_SUBMIT";
     }

   PrintAuthReport(report,InpIssueToken && report.contractResult=="PASS");
  }
