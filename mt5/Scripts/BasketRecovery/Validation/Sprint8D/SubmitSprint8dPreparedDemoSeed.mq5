#property script_show_inputs
#property description "Sprint 8D: isolated D0E async submission harness. Dry-run default; no broker unless explicitly armed."

#include <BasketRecovery/Validation/Sprint8D/Sprint8dDemoM123StrategyProfile.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionAuthorizationStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5AccountExecutionEligibilityProvider.mqh>
#include <BasketRecovery/Infrastructure/Market/Mt5MarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5Clock.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5EnvelopeTradeRequestTranslator.mqh>
#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationRegistry.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionTriggerRegistry.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/PreparedSubmissionValidator.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Application/Execution/SubmitPreparedExecutionUseCase.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRequestFingerprint.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionEnvelope.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>
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
const int    GATEWAY_SLIPPAGE_POINTS=10;
const string RETIRED_BASKET_ID="sprint8c-demo-xauusd-002";
const ulong RETIRED_TICKET_A=1516350243;
const ulong RETIRED_TICKET_B=1516503131;

input bool   InpDryRunOnly=true;
input bool   InpAuthorizeBrokerSubmit=false;
input string InpAuthorizationToken="";
input string InpTriggerToken="";

struct SSubmitReadinessReport
  {
   string submitMode;
   string preparedStateVerified;
   string authorizationTokenPresent;
   string triggerTokenPresent;
   string brokerSubmitAuthorized;
   string brokerInvoked;
   string submissionAttempted;
   string requestId;
   string basketId;
   string symbol;
   string direction;
   string volume;
   string ticket;
   string stopLoss;
   string takeProfit;
   string magicNumber;
   string fillingMode;
   string brokerComment;
   string readinessResult;
   string readinessReason;
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

string OrderFillingLabel(const ENUM_ORDER_TYPE_FILLING filling)
  {
   if(filling==ORDER_FILLING_IOC)
      return "IOC";
   if(filling==ORDER_FILLING_FOK)
      return "FOK";
   if(filling==ORDER_FILLING_RETURN)
      return "RETURN";
   return "UNKNOWN";
  }

string SideLabel(const ENUM_ORDER_TYPE orderType)
  {
   if(orderType==ORDER_TYPE_BUY)
      return "BUY";
   if(orderType==ORDER_TYPE_SELL)
      return "SELL";
   return "UNKNOWN";
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

void HydrateRegistryFromStore(CPendingExecutionRegistry &registry,
                              CFilePendingExecutionStore &store)
  {
   CPendingExecutionEntry entries[];
   const int count=store.RestoreEntries(entries);
   for(int i=0;i<count;i++)
      registry.Upsert(entries[i]);
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

CDemoExecutionAuthorizationConfig BuildD0EDemoAuthorizationConfig(void)
  {
   CDemoExecutionAuthorizationConfig config;
   config.SetExecutionRuntimeMode(BRE_EXEC_RUNTIME_DEMO_MANUAL_SUBMISSION);
   config.SetEnableLiveDemoExecution(true);
   config.SetRequireManualDemoAuthorization(true);
   config.SetMaxAuthorizedRequestsPerSession(1);
   config.SetAuthorizationTokenExpirySeconds(300);
   config.SetMaxManualDemoOpenVolume(TARGET_REQUESTED_VOLUME);
   return config;
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

bool VerifyCanonicalProfile(string &reasons)
  {
   const string computedHash=CStrategyProfileCanonicalSerializer::ComputeHash(CSprint8dDemoM123StrategyProfile::CanonicalJson());
   bool ok=true;
   if(CSprint8dDemoM123StrategyProfile::StrategyId()!="sprint-8d-demo-xauusd-m123-v1")
     {
      AppendReason(reasons,"Canonical strategy id mismatch");
      ok=false;
     }
   if(CSprint8dDemoM123StrategyProfile::ExpectedHash()!=TARGET_CANONICAL_HASH)
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

bool VerifyPreparedBasket(CFileBasketRepository &repository,
                          CBasketAggregate &basketOut,
                          string &reasons)
  {
   const CBasketId basketId(TARGET_BASKET_ID);
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
   loaded.TryGetValue(basketOut);
   bool ok=true;
   if(basketOut.LifecycleState()!=BRE_STATE_ACTIVE)
     {
      AppendReason(reasons,"Basket lifecycle is not ACTIVE");
      ok=false;
     }
   if((long)basketOut.Version()!=TARGET_BASKET_VERSION)
     {
      AppendReason(reasons,"Basket version mismatch");
      ok=false;
     }
   if(basketOut.StrategyProfileHash()!=TARGET_CANONICAL_HASH)
     {
      AppendReason(reasons,"Basket strategy profile hash mismatch");
      ok=false;
     }
   if(basketOut.StrategyId()!=CSprint8dDemoM123StrategyProfile::StrategyId())
     {
      AppendReason(reasons,"Basket strategy id mismatch");
      ok=false;
     }
   if(basketOut.Symbol()!=TARGET_SYMBOL)
     {
      AppendReason(reasons,"Basket symbol mismatch");
      ok=false;
     }
   if(basketOut.Direction()!=BRE_DIRECTION_BUY)
     {
      AppendReason(reasons,"Basket direction mismatch");
      ok=false;
     }
   string retiredMatch="";
   if(BasketContainsRetiredIdentity(basketOut,retiredMatch))
     {
      AppendReason(reasons,"Retired Sprint 8C identity detected in basket: "+retiredMatch);
      ok=false;
     }
   return ok;
  }

bool VerifyPreparedPendingAndEnvelope(CFilePendingExecutionStore &store,
                                      CPendingExecutionEntry &entryOut,
                                      CBrokerSubmissionEnvelope &envelopeOut,
                                      string &reasons)
  {
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
   if(!FindPendingEntryByRequestId(store,TARGET_EXECUTION_REQUEST_ID,entryOut))
     {
      AppendReason(reasons,"Target pending entry missing");
      return false;
     }
   CResult<CBrokerSubmissionEnvelope> envelopeResult=store.FindEnvelopeByIdempotencyKey(TARGET_IDEMPOTENCY_KEY);
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
   if(entryOut.IntentType()!=BRE_EXEC_INTENT_OPEN_POSITION)
     {
      AppendReason(reasons,"Pending intent is not OPEN_POSITION");
      ok=false;
     }
   if(entryOut.BasketId().Value()!=TARGET_BASKET_ID)
     {
      AppendReason(reasons,"Pending basket id mismatch");
      ok=false;
     }
   if(entryOut.ExecutionRequestId()!=TARGET_EXECUTION_REQUEST_ID)
     {
      AppendReason(reasons,"Pending execution request id mismatch");
      ok=false;
     }
   if(entryOut.IdempotencyKey()!=TARGET_IDEMPOTENCY_KEY)
     {
      AppendReason(reasons,"Pending idempotency key mismatch");
      ok=false;
     }
   if(entryOut.ExpectedBasketVersion()!=(int)TARGET_BASKET_VERSION)
     {
      AppendReason(reasons,"Pending expected basket version mismatch");
      ok=false;
     }
   if(entryOut.StrategyProfileHash()!=TARGET_CANONICAL_HASH)
     {
      AppendReason(reasons,"Pending strategy profile hash mismatch");
      ok=false;
     }
   if(entryOut.Symbol()!=TARGET_SYMBOL)
     {
      AppendReason(reasons,"Pending symbol mismatch");
      ok=false;
     }
   if(!MathIsValidNumber(entryOut.RequestedVolume()) ||
      MathAbs(entryOut.RequestedVolume()-TARGET_REQUESTED_VOLUME)>VOLUME_TOLERANCE)
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
   if(envelopeOut.MagicNumber()!=TARGET_MAGIC_NUMBER)
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
                                                                       envelopeOut.Direction(),
                                                                       envelopeOut.Ticket(),
                                                                       envelopeOut.RequestedVolume(),
                                                                       envelopeOut.RequestedPrice(),
                                                                       envelopeOut.RequestedStopLoss(),
                                                                       envelopeOut.RequestedTakeProfit(),
                                                                       envelopeOut.PreparedAtUtc(),
                                                                       CCommandId("cmd-sprint8d-submit-audit"),
                                                                       "sprint8d-submit");
   if(envelopeOut.Fingerprint()!=CExecutionRequestFingerprint::Compute(reconstructed))
     {
      AppendReason(reasons,"Envelope fingerprint mismatch");
      ok=false;
     }
   return ok;
  }

bool BuildBrokerPreview(const CBrokerSubmissionEnvelope &envelope,
                        CMt5MarketDataProvider &marketData,
                        MqlTradeRequest &requestOut,
                        string &sideOut,
                        string &fillingOut,
                        string &reasons)
  {
   CResult<CMarketQuote> quoteResult=marketData.TryGetQuote(envelope.Symbol());
   CMarketQuote quote;
   if(!quoteResult.TryGetValue(quote))
     {
      AppendReason(reasons,"Market quote unavailable for broker preview");
      return false;
     }
   CMt5EnvelopeTradeRequestTranslator translator;
   string translateError="";
   if(!translator.TryTranslateOpenMarketDeal(envelope,
                                            quote.Bid(),
                                            quote.Ask(),
                                            GATEWAY_SLIPPAGE_POINTS,
                                            requestOut,
                                            translateError))
     {
      AppendReason(reasons,"Broker preview translation failed: "+translateError);
      return false;
     }
   sideOut=SideLabel(requestOut.type);
   fillingOut=OrderFillingLabel(requestOut.type_filling);
   return true;
  }

void PopulatePreviewFields(SSubmitReadinessReport &report,
                           const CBrokerSubmissionEnvelope &envelope,
                           const MqlTradeRequest &request,
                           const string side,
                           const string fillingMode)
  {
   report.requestId=envelope.ExecutionRequestId();
   report.basketId=envelope.BasketId().Value();
   report.symbol=envelope.Symbol();
   report.direction=side;
   report.volume=DoubleToString(envelope.RequestedVolume(),8);
   report.ticket=IntegerToString((long)envelope.Ticket());
   report.stopLoss=DoubleToString(envelope.RequestedStopLoss(),8);
   report.takeProfit=DoubleToString(envelope.RequestedTakeProfit(),8);
   report.magicNumber=IntegerToString((int)envelope.MagicNumber());
   report.fillingMode=fillingMode;
   report.brokerComment=envelope.BrokerComment();
   if(request.comment!="")
      report.brokerComment=request.comment;
  }

bool ComputeBrokerSubmitAuthorized(const bool preflightOk,
                                   const bool preparedStateOk,
                                   const CPendingExecutionEntry &entry)
  {
   if(InpDryRunOnly)
      return false;
   if(!InpAuthorizeBrokerSubmit)
      return false;
   if(InpAuthorizationToken=="")
      return false;
   if(InpTriggerToken=="")
      return false;
   if(!preflightOk)
      return false;
   if(!preparedStateOk)
      return false;
   if(entry.Status()!=BRE_TRADE_EXEC_STATUS_QUEUED)
      return false;
   if(CountSymbolOpenPositions(TARGET_SYMBOL)!=0)
      return false;
   return true;
  }

void PrintSubmitReport(const SSubmitReadinessReport &report)
  {
   PrintLine("sprint8d_submit_mode="+report.submitMode);
   PrintLine("prepared_state_verified="+report.preparedStateVerified);
   PrintLine("authorization_token_present="+report.authorizationTokenPresent);
   PrintLine("trigger_token_present="+report.triggerTokenPresent);
   PrintLine("broker_submit_authorized="+report.brokerSubmitAuthorized);
   PrintLine("broker_invoked="+report.brokerInvoked);
   PrintLine("submission_attempted="+report.submissionAttempted);
   PrintLine("request_id="+report.requestId);
   PrintLine("basket_id="+report.basketId);
   PrintLine("symbol="+report.symbol);
   PrintLine("direction="+report.direction);
   PrintLine("volume="+report.volume);
   PrintLine("ticket="+report.ticket);
   PrintLine("stop_loss="+report.stopLoss);
   PrintLine("take_profit="+report.takeProfit);
   PrintLine("magic_number="+report.magicNumber);
   PrintLine("filling_mode="+report.fillingMode);
   PrintLine("broker_comment="+report.brokerComment);
   PrintLine("submit_readiness_result="+report.readinessResult);
   PrintLine("submit_readiness_reason="+report.readinessReason);
   PrintLine("next_safe_step="+report.nextSafeStep);
  }

void OnStart(void)
  {
   SSubmitReadinessReport report;
   report.submitMode="DRY_RUN";
   report.preparedStateVerified="false";
   report.authorizationTokenPresent=(InpAuthorizationToken!=""?"true":"false");
   report.triggerTokenPresent=(InpTriggerToken!=""?"true":"false");
   report.brokerSubmitAuthorized="false";
   report.brokerInvoked="false";
   report.submissionAttempted="false";
   report.requestId=TARGET_EXECUTION_REQUEST_ID;
   report.basketId=TARGET_BASKET_ID;
   report.symbol=TARGET_SYMBOL;
   report.direction="BUY";
   report.volume=DoubleToString(TARGET_REQUESTED_VOLUME,8);
   report.ticket="0";
   report.stopLoss="0";
   report.takeProfit="0";
   report.magicNumber=IntegerToString((int)TARGET_MAGIC_NUMBER);
   report.fillingMode="";
   report.brokerComment="";
   report.readinessResult="FAIL";
   report.readinessReason="";
   report.nextSafeStep="DO_NOT_SUBMIT_OR_OVERWRITE_STATE";

   string reasons="";
   string brokerWaitReason="";
   if(!WaitForD0EBrokerAuthorization(brokerWaitReason))
      AppendReason(reasons,brokerWaitReason);

   const bool preflightOk=VerifyD0EPreflight(TARGET_SYMBOL,reasons);
   const bool canonicalOk=VerifyCanonicalProfile(reasons);

   CFileBasketRepository repository(BRE_PERSISTENCE_BASKET_SUBDIR);
   CFilePendingExecutionStore pendingStore(PENDING_STORE_RELATIVE_PATH);
   CPendingExecutionRegistry registry;
   CVoidResult restoreResult=pendingStore.RestoreFromDisk();
   if(restoreResult.IsFail())
      AppendReason(reasons,"Pending restore failed before hydrate: "+restoreResult.ErrorMessage());
   else
      HydrateRegistryFromStore(registry,pendingStore);

   CBasketAggregate basket;
   const bool basketOk=VerifyPreparedBasket(repository,basket,reasons);

   CPendingExecutionEntry pendingEntry;
   CBrokerSubmissionEnvelope envelope;
   const bool pendingOk=VerifyPreparedPendingAndEnvelope(pendingStore,pendingEntry,envelope,reasons);

   if(basketOk && pendingOk)
     {
      if(IntegerToString((int)basket.Version())!=IntegerToString(pendingEntry.ExpectedBasketVersion()))
         AppendReason(reasons,"Basket version does not match pending expected basket version");
      if(basket.StrategyProfileHash()!=pendingEntry.StrategyProfileHash())
         AppendReason(reasons,"Basket and pending profile hash mismatch");
     }

   const bool preparedStateOk=preflightOk && canonicalOk && basketOk && pendingOk && reasons=="";
   report.preparedStateVerified=(preparedStateOk?"true":"false");

   CMt5Clock clock;
   CMt5MarketDataProvider marketData(&clock);
   CMarketSafetyConfig marketSafety=CMarketSafetyConfig::Create(5000,500000,30000);
   CSubmissionPreparationValidator preparationValidator(&marketData,marketSafety);

   CInMemoryExecutionAuthorizationStore authStore;
   CExecutionAuthorizationRegistry authRegistry(&authStore);
   authRegistry.RestoreFromStore();
   CDemoManualSubmissionTriggerRegistry triggerRegistry;
   CMt5AccountExecutionEligibilityProvider eligibilityProvider;
   CMt5LiveAsyncOrderSendTransport liveTransport;
   CMt5AsyncSubmissionGateway asyncGateway(&liveTransport,NULL,GATEWAY_SLIPPAGE_POINTS);
   CSubmitPreparedExecutionUseCase submitUseCase(&registry,&asyncGateway,&pendingStore,&clock,NULL);
   const CDemoExecutionAuthorizationConfig demoConfig=BuildD0EDemoAuthorizationConfig();
   CDemoManualSubmissionService demoService(demoConfig,
                                          &authRegistry,
                                          &triggerRegistry,
                                          &registry,
                                          &pendingStore,
                                          &eligibilityProvider,
                                          &clock,
                                          &submitUseCase,
                                          &asyncGateway,
                                          marketSafety);

   CPreparedSubmissionValidator preparedValidator(&registry,&pendingStore,&clock);
   CPendingExecutionEntry runtimeEntry;
   CBrokerSubmissionEnvelope runtimeEnvelope;
   ENUM_BRE_PREPARED_SUBMISSION_FAILURE_REASON prepReason=BRE_SUBMIT_FAIL_NONE;
   string prepMessage="";
   if(!preparedValidator.Validate(TARGET_EXECUTION_REQUEST_ID,
                                  runtimeEntry,
                                  runtimeEnvelope,
                                  prepReason,
                                  prepMessage))
      AppendReason(reasons,"Prepared submission validator failed: "+prepMessage);

   if(preparedStateOk)
     {
      MqlTradeRequest previewRequest;
      string previewSide="";
      string previewFilling="";
      if(!BuildBrokerPreview(runtimeEnvelope,marketData,previewRequest,previewSide,previewFilling,reasons))
         AppendReason(reasons,"Broker preview build failed");
      else
         PopulatePreviewFields(report,runtimeEnvelope,previewRequest,previewSide,previewFilling);
     }

   const bool brokerSubmitAuthorized=ComputeBrokerSubmitAuthorized(preparedStateOk && reasons=="",
                                                                 preparedStateOk,
                                                                 pendingEntry);
   report.brokerSubmitAuthorized=(brokerSubmitAuthorized?"true":"false");

   bool authorizationAttempted=false;
   if(brokerSubmitAuthorized)
     {
      report.submitMode="LIVE_GUARDED";
      CResult<CMarketQuote> quoteResult=marketData.TryGetQuote(TARGET_SYMBOL);
      CMarketQuote quote;
      if(!quoteResult.TryGetValue(quote))
         AppendReason(reasons,"Market quote unavailable for live submission");
      else
        {
         authorizationAttempted=true;
         report.submissionAttempted="true";
         CDemoManualSubmissionResult submitResult=demoService.TrySubmit(TARGET_EXECUTION_REQUEST_ID,
                                                                      InpAuthorizationToken,
                                                                      InpTriggerToken,
                                                                      basket,
                                                                      quote);
         report.brokerInvoked=(submitResult.BrokerInvoked()?"true":"false");
         if(!submitResult.IsSuccess())
            AppendReason(reasons,submitResult.Detail());
        }
     }
   else
     {
      report.submitMode="DRY_RUN";
      report.submissionAttempted="false";
      report.brokerInvoked="false";
      if(InpDryRunOnly && (InpAuthorizationToken!="" || InpTriggerToken!=""))
         AppendReason(reasons,"Dry-run mode rejects non-empty authorization or trigger tokens");
     }

   if(reasons=="")
     {
      report.readinessResult="PASS";
      report.readinessReason="";
      report.nextSafeStep="REVIEW_AND_EXPLICITLY_APPROVE_ONE_D0E_ASYNC_ORDER";
     }
   else
     {
      report.readinessResult="FAIL";
      report.readinessReason=reasons;
      report.nextSafeStep="DO_NOT_SUBMIT_OR_OVERWRITE_STATE";
     }

   PrintSubmitReport(report);
  }
