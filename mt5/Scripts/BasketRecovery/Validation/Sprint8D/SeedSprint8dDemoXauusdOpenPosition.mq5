#property script_show_inputs
#property description "Sprint 8D: DRY_RUN preflight and optional isolated write-mode seed for XAUUSD OPEN_POSITION 0.06. No broker submission."

#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Validation/Sprint8D/Sprint8dDemoM123StrategyProfile.mqh>
#include <BasketRecovery/Application/Services/ExecutionDryRunTestBasketSeedService.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationPolicy.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionTransitionGate.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRequestFingerprint.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Market/Mt5MarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5Clock.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5UniqueIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Domain/Execution/SubmissionPreparationResult.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>

const string REQUIRED_TERMINAL_DATA_ID="D0E8209F77C8CF37AD8BF550E51FF075";
const string PENDING_STORE_RELATIVE_PATH="BasketRecovery/pending_executions.dat";
const string RETIRED_BASKET_ID="sprint8c-demo-xauusd-002";
const ulong RETIRED_TICKET_A=1516350243;
const ulong RETIRED_TICKET_B=1516503131;
const double REQUIRED_SEED_VOLUME=0.06;
const double VOLUME_TOLERANCE=0.00000001;
const double EXPECTED_MIN_LOT=0.01;
const double EXPECTED_LOT_STEP=0.01;
const int ENVELOPE_VALIDITY_SECONDS=3600;

input bool   InpDryRunOnly=true;
input bool   InpWriteMode=false;
input string InpBasketId="";
input string InpExecutionRequestId="";
input string InpIdempotencyKey="";
input string InpSymbol="XAUUSD";
input string InpDirection="BUY";
input double InpRequestedVolume=0.06;
input long   InpExpectedBasketVersion=0;
input string InpStrategyProfileHash="";
input long   InpMagicNumber=202608401;
input ulong  InpQuoteSequence=0;

string CanonicalStrategyProfileHash(void)
  {
   return CSprint8dDemoM123StrategyProfile::ExpectedHash();
  }

bool ProfileHashInputMatchesCanonical(void)
  {
   if(InpStrategyProfileHash=="")
      return true;
   return InpStrategyProfileHash==CanonicalStrategyProfileHash();
  }

void PrintCanonicalProfileContext(void)
  {
   PrintLine("canonical_strategy_id="+CSprint8dDemoM123StrategyProfile::StrategyId());
   PrintLine("canonical_strategy_profile_hash="+CanonicalStrategyProfileHash());
   PrintLine("profile_hash_input_matches_canonical="+(ProfileHashInputMatchesCanonical()?"true":"false"));
  }

bool ValidateInputBasketVersionGuard(const long resolvedBasketVersion,string &reasonOut)
  {
   reasonOut="";
   if(InpExpectedBasketVersion==0)
      return true;
   if(InpExpectedBasketVersion!=resolvedBasketVersion)
     {
      reasonOut="Input expected basket version does not match resolved basket version";
      return false;
     }
   return true;
  }

void PrintBasketVersionBinding(const long resolvedBasketVersion)
  {
   PrintLine("input_expected_basket_version="+IntegerToString((int)InpExpectedBasketVersion));
   if(resolvedBasketVersion>0)
      PrintLine("resolved_basket_version="+IntegerToString((int)resolvedBasketVersion));
   else
      PrintLine("resolved_basket_version=UNRESOLVED");
  }

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

bool WaitForD0EBrokerAuthorization(string &failureReasonOut)
  {
   failureReasonOut="";
   if(!TerminalDataPathMatchesD0E(TerminalInfoString(TERMINAL_DATA_PATH)))
      return true;

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

CTradeExecutionRequest BuildSeedExecutionRequest(const CBasketId &basketId,
                                               const ENUM_BRE_TRADE_DIRECTION direction,
                                               const long expectedBasketVersion,
                                               const string strategyProfileHash,
                                               const CMt5Clock &clock)
  {
   return CTradeExecutionRequest::Create(InpExecutionRequestId,
                                         InpIdempotencyKey,
                                         "corr-"+InpExecutionRequestId,
                                         basketId,
                                         expectedBasketVersion,
                                         strategyProfileHash,
                                         InpSymbol,
                                         BRE_EXEC_INTENT_OPEN_POSITION,
                                         direction,
                                         0,
                                         InpRequestedVolume,
                                         0.0,
                                         0.0,
                                         0.0,
                                         clock.Now(),
                                         CCommandId("cmd-sprint8d-seed"),
                                         "sprint8d-seed");
  }

bool TryBuildVersionAwareSeedRequest(CFileBasketRepository &repository,
                                     const CBasketId &basketId,
                                     const ENUM_BRE_TRADE_DIRECTION direction,
                                     const CMt5Clock &clock,
                                     CTradeExecutionRequest &requestOut,
                                     long &resolvedBasketVersionOut,
                                     string &reasonOut)
  {
   resolvedBasketVersionOut=0;
   reasonOut="";
   if(repository.Exists(basketId))
     {
      CResult<CBasketAggregate> loaded=repository.Load(basketId);
      if(loaded.IsFail())
        {
         reasonOut="Basket exists but could not be loaded";
         return false;
        }
      CBasketAggregate basket;
      loaded.TryGetValue(basket);
      resolvedBasketVersionOut=(long)basket.Version();
      if(!ValidateInputBasketVersionGuard(resolvedBasketVersionOut,reasonOut))
         return false;
      string basketReason="";
      if(!BasketMatchesSeedContract(basket,direction,resolvedBasketVersionOut,basketReason))
        {
         reasonOut=basketReason;
         return false;
        }
      requestOut=BuildSeedExecutionRequest(basketId,
                                             direction,
                                             resolvedBasketVersionOut,
                                             basket.StrategyProfileHash(),
                                             clock);
      return true;
     }
   if(InpExpectedBasketVersion!=0)
     {
      reasonOut="Cannot validate input expected basket version before basket exists";
      return false;
     }
   requestOut=BuildSeedExecutionRequest(basketId,
                                        direction,
                                        0,
                                        CanonicalStrategyProfileHash(),
                                        clock);
   return true;
  }

bool BasketMatchesSeedContract(const CBasketAggregate &basket,
                               const ENUM_BRE_TRADE_DIRECTION direction,
                               const long expectedBasketVersion,
                               string &reasonOut)
  {
   reasonOut="";
   if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
     {
      reasonOut="Basket lifecycle is not ACTIVE";
      return false;
     }
   if(basket.Symbol()!=InpSymbol)
     {
      reasonOut="Basket symbol mismatch";
      return false;
     }
   if(basket.Direction()!=direction)
     {
      reasonOut="Basket direction mismatch";
      return false;
     }
   if((long)basket.Version()!=expectedBasketVersion)
     {
      reasonOut="Basket version mismatch";
      return false;
     }
   if(basket.StrategyProfileHash()!=CanonicalStrategyProfileHash())
     {
      reasonOut="Basket strategy profile hash mismatch";
      return false;
     }
   if(!basket.HasStrategyProfile())
     {
      reasonOut="Basket strategy profile is not bound";
      return false;
     }
   return true;
  }

bool PendingEntryMatchesRequest(const CPendingExecutionEntry &entry,
                                const CTradeExecutionRequest &request)
  {
   if(entry.ExecutionRequestId()!=request.ExecutionRequestId())
      return false;
   if(entry.IdempotencyKey()!=request.IdempotencyKey())
      return false;
   if(entry.BasketId().Value()!=request.BasketId().Value())
      return false;
   if(entry.ExpectedBasketVersion()!=(int)request.ExpectedBasketVersion())
      return false;
   if(entry.StrategyProfileHash()!=request.StrategyProfileHash())
      return false;
   if(entry.Symbol()!=request.Symbol())
      return false;
   if(entry.IntentType()!=request.IntentType())
      return false;
   if(!VolumeMatchesRequiredSeedVolume(entry.RequestedVolume()))
      return false;
   if(entry.Status()!=BRE_TRADE_EXEC_STATUS_QUEUED)
      return false;
   if(!entry.IsPreparedQueued())
      return false;
   return true;
  }

bool EnvelopeMatchesSeedRequest(const CBrokerSubmissionEnvelope &envelope,
                                const CTradeExecutionRequest &request,
                                const datetime nowUtc)
  {
   if(envelope.IsExpired(nowUtc))
      return false;
   if(envelope.ExecutionRequestId()!=request.ExecutionRequestId())
      return false;
   if(envelope.IdempotencyKey()!=request.IdempotencyKey())
      return false;
   if(envelope.BasketId().Value()!=request.BasketId().Value())
      return false;
   if(envelope.ExpectedBasketVersion()!=(int)request.ExpectedBasketVersion())
      return false;
   if(envelope.StrategyProfileHash()!=request.StrategyProfileHash())
      return false;
   if(envelope.Symbol()!=request.Symbol())
      return false;
   if(envelope.IntentType()!=request.IntentType())
      return false;
   if(envelope.Direction()!=request.Direction())
      return false;
   if(!VolumeMatchesRequiredSeedVolume(envelope.RequestedVolume()))
      return false;
   if(envelope.MagicNumber()!=InpMagicNumber)
      return false;
   if(MathAbs(envelope.RequestedStopLoss())>VOLUME_TOLERANCE)
      return false;
   if(MathAbs(envelope.RequestedTakeProfit())>VOLUME_TOLERANCE)
      return false;
   CExecutionRequestFingerprint current=CExecutionRequestFingerprint::Compute(request);
   if(envelope.Fingerprint()!=current)
      return false;
   return true;
  }

int CountUnrelatedPendingEntries(CFilePendingExecutionStore &store,
                                 const string executionRequestId,
                                 const string idempotencyKey)
  {
   CPendingExecutionEntry entries[];
   int count=store.RestoreEntries(entries);
   int unrelated=0;
   for(int i=0;i<count;i++)
     {
      if(entries[i].ExecutionRequestId()==executionRequestId)
         continue;
      if(entries[i].IdempotencyKey()==idempotencyKey)
         continue;
      unrelated++;
     }
   return unrelated;
  }

void HydrateRegistryFromStore(CPendingExecutionRegistry &registry,
                            CFilePendingExecutionStore &store)
  {
   CPendingExecutionEntry entries[];
   int count=store.RestoreEntries(entries);
   for(int i=0;i<count;i++)
      registry.Upsert(entries[i]);
  }

bool DetectPayloadIdentityMismatch(CPendingExecutionRegistry &registry,
                                   CFilePendingExecutionStore &store,
                                   const CTradeExecutionRequest &request,
                                   string &reasonOut)
  {
   reasonOut="";
   CPendingExecutionEntry byRequest;
   if(registry.TryGetByExecutionRequestId(request.ExecutionRequestId(),byRequest))
     {
      if(byRequest.IdempotencyKey()!=request.IdempotencyKey() ||
         byRequest.BasketId().Value()!=request.BasketId().Value() ||
         byRequest.ExpectedBasketVersion()!=(int)request.ExpectedBasketVersion() ||
         byRequest.StrategyProfileHash()!=request.StrategyProfileHash() ||
         byRequest.Symbol()!=request.Symbol() ||
         byRequest.IntentType()!=request.IntentType() ||
         !VolumeMatchesRequiredSeedVolume(byRequest.RequestedVolume()))
        {
         reasonOut="Execution request id exists with different payload";
         return true;
        }
     }

   CPendingExecutionEntry entries[];
   int count=store.RestoreEntries(entries);
   for(int i=0;i<count;i++)
     {
      if(entries[i].IdempotencyKey()==request.IdempotencyKey() &&
         entries[i].ExecutionRequestId()!=request.ExecutionRequestId())
        {
         reasonOut="Idempotency key exists with different execution request id";
         return true;
        }
     }

   CResult<CBrokerSubmissionEnvelope> envelopeResult=store.FindEnvelopeByIdempotencyKey(request.IdempotencyKey());
   CBrokerSubmissionEnvelope envelope;
   if(envelopeResult.TryGetValue(envelope))
     {
      if(envelope.ExecutionRequestId()!=request.ExecutionRequestId())
        {
         reasonOut="Envelope idempotency key is bound to a different execution request id";
         return true;
        }
      CExecutionRequestFingerprint current=CExecutionRequestFingerprint::Compute(request);
      if(envelope.Fingerprint()!=current)
        {
         reasonOut="Envelope fingerprint does not match requested payload";
         return true;
        }
     }
   return false;
  }

bool ClassifySeedState(CFileBasketRepository &repository,
                       CPendingExecutionRegistry &registry,
                       CFilePendingExecutionStore &store,
                       const CTradeExecutionRequest &request,
                       const ENUM_BRE_TRADE_DIRECTION direction,
                       const datetime nowUtc,
                       string &classificationOut,
                       string &reasonOut,
                       bool &basketExistsBeforeOut,
                       bool &pendingEntryExistsBeforeOut,
                       bool &pendingEnvelopeExistsBeforeOut)
  {
   classificationOut="UNKNOWN";
   reasonOut="";
   basketExistsBeforeOut=false;
   pendingEntryExistsBeforeOut=false;
   pendingEnvelopeExistsBeforeOut=false;

   const CBasketId basketId(request.BasketId());
   basketExistsBeforeOut=repository.Exists(basketId);

   CPendingExecutionEntry targetEntry;
   pendingEntryExistsBeforeOut=registry.TryGetByExecutionRequestId(request.ExecutionRequestId(),targetEntry);

   CResult<CBrokerSubmissionEnvelope> envelopeResult=store.FindEnvelopeByIdempotencyKey(request.IdempotencyKey());
   CBrokerSubmissionEnvelope targetEnvelope;
   pendingEnvelopeExistsBeforeOut=envelopeResult.TryGetValue(targetEnvelope);

   string mismatchReason="";
   if(DetectPayloadIdentityMismatch(registry,store,request,mismatchReason))
     {
      classificationOut="G_PAYLOAD_MISMATCH";
      reasonOut=mismatchReason;
      return false;
     }

   if(pendingEntryExistsBeforeOut &&
      !CBrokerSubmissionTransitionGate::PreparationMaySetStatus(targetEntry.Status()))
     {
      classificationOut="H_TERMINAL_PENDING";
      reasonOut="Target pending entry is not QUEUED";
      return false;
     }

   if((pendingEntryExistsBeforeOut || pendingEnvelopeExistsBeforeOut) && !basketExistsBeforeOut)
     {
      classificationOut="E_ORPHAN_PENDING";
      reasonOut="Target pending artifacts exist but basket file is missing";
      return false;
     }

   if(pendingEntryExistsBeforeOut && !pendingEnvelopeExistsBeforeOut)
     {
      classificationOut="C_ENTRY_NO_ENVELOPE";
      reasonOut="Target pending entry exists without matching envelope";
      return false;
     }

   if(basketExistsBeforeOut)
     {
      CResult<CBasketAggregate> loaded=repository.Load(basketId);
      if(loaded.IsFail())
        {
         classificationOut="F_BASKET_MISMATCH";
         reasonOut="Target basket file exists but could not be loaded";
         return false;
        }
      CBasketAggregate basket;
      loaded.TryGetValue(basket);
      string basketReason="";
      if(!BasketMatchesSeedContract(basket,direction,(long)basket.Version(),basketReason))
        {
         classificationOut="F_BASKET_MISMATCH";
         reasonOut=basketReason;
         return false;
        }

      if(pendingEntryExistsBeforeOut &&
         pendingEnvelopeExistsBeforeOut &&
         PendingEntryMatchesRequest(targetEntry,request) &&
         EnvelopeMatchesSeedRequest(targetEnvelope,request,nowUtc))
        {
         classificationOut="D_IDEMPOTENT_ALREADY_PREPARED";
         reasonOut="Exact matching ACTIVE basket and QUEUED pending already prepared";
         return true;
        }

      if(!pendingEntryExistsBeforeOut && !pendingEnvelopeExistsBeforeOut)
        {
         classificationOut="B_EXISTING_BASKET_ONLY";
         reasonOut="Exact matching ACTIVE basket exists without target pending artifacts";
         return true;
        }

      classificationOut="F_BASKET_MISMATCH";
      reasonOut="Basket exists but target pending state is not an exact queued match";
      return false;
     }

   if(!pendingEntryExistsBeforeOut && !pendingEnvelopeExistsBeforeOut)
     {
      classificationOut="A_FRESH";
      reasonOut="No target basket or pending artifacts exist";
      return true;
     }

   classificationOut="G_PAYLOAD_MISMATCH";
   reasonOut="Pending artifacts exist without target basket";
   return false;
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

   if(!InpWriteMode && !InpDryRunOnly)
     {
      failureReasonOut="InpDryRunOnly must remain true when InpWriteMode is false";
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
   if(InpExpectedBasketVersion<0)
     {
      failureReasonOut="Expected basket version must be zero or greater";
      return false;
     }
   if(!ProfileHashInputMatchesCanonical())
     {
      failureReasonOut="Strategy profile hash input does not match canonical profile";
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

void PrintCommonContext(const string directionLabel,
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
   PrintLine("input_expected_basket_version="+IntegerToString((int)InpExpectedBasketVersion));
   PrintCanonicalProfileContext();
   PrintLine("strategy_profile_hash="+CanonicalStrategyProfileHash());
   PrintLine("magic_number="+IntegerToString((int)InpMagicNumber));
   PrintLine("quote_sequence="+IntegerToString((long)InpQuoteSequence));
  }

void PrintDryRunSummary(const bool preflightOk,
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
                        const int openPositionCount,
                        const bool stateInspectionPerformed,
                        const string classification,
                        const string stateInspectionReason,
                        const string pendingRestoreOutcome,
                        const bool basketExistsBefore,
                        const bool pendingEntryExistsBefore,
                        const bool pendingEnvelopeExistsBefore,
                        const long resolvedBasketVersion)
  {
   PrintLine("sprint8d_seed_setup_mode=DRY_RUN");
   PrintCommonContext(directionLabel,
                      terminalDataPath,
                      accountTradeModeLabel,
                      accountMarginModeLabel,
                      accountTradeAllowed,
                      symbolTradeModeLabel,
                      minVolume,
                      volumeStep,
                      fillingModeLabel,
                      openPositionCount);
   PrintLine("old_sprint8c_state_reuse_detected="+(oldStateReuseDetected?"true":"false"));
   if(stateInspectionPerformed)
     {
      PrintBasketVersionBinding(resolvedBasketVersion);
      PrintLine("seed_state_classification="+classification);
      PrintLine("pending_restore_outcome="+pendingRestoreOutcome);
      PrintLine("basket_exists_before="+(basketExistsBefore?"true":"false"));
      PrintLine("pending_entry_exists_before="+(pendingEntryExistsBefore?"true":"false"));
      PrintLine("pending_envelope_exists_before="+(pendingEnvelopeExistsBefore?"true":"false"));
      PrintLine("seed_state_result="+(preflightOk && stateInspectionReason==""?"PASS":"FAIL"));
      PrintLine("seed_state_reason="+stateInspectionReason);
     }
   else
     {
      PrintLine("resolved_basket_version=NOT_INSPECTED");
      PrintLine("seed_state_classification=NOT_APPLICABLE");
      PrintLine("pending_restore_outcome=NOT_APPLICABLE");
      PrintLine("basket_exists_before=NOT_APPLICABLE");
      PrintLine("pending_entry_exists_before=NOT_APPLICABLE");
      PrintLine("pending_envelope_exists_before=NOT_APPLICABLE");
      PrintLine("seed_state_result="+(preflightOk?"PASS":"FAIL"));
      PrintLine("seed_state_reason="+failureReason);
     }
   PrintLine("write_performed=false");
   PrintLine("seed_setup_preflight_result="+(preflightOk?"PASS":"FAIL"));
   PrintLine("seed_setup_preflight_reason="+failureReason);
   if(preflightOk && stateInspectionPerformed && stateInspectionReason=="")
      PrintLine("next_safe_step=REVIEW_WRITE_MODE_DESIGN_WITHOUT_GLOBAL_STORE_CLEAR");
   else if(preflightOk)
      PrintLine("next_safe_step=REVIEW_STATE_BEFORE_WRITE_MODE");
   else
      PrintLine("next_safe_step=DO_NOT_SUBMIT_OR_OVERWRITE_STATE");
  }

bool RunDryRunStateInspection(const ENUM_BRE_TRADE_DIRECTION direction,
                              const string directionLabel,
                              const string terminalDataPath,
                              const string accountTradeModeLabel,
                              const string accountMarginModeLabel,
                              const bool accountTradeAllowed,
                              const string symbolTradeModeLabel,
                              const double minVolume,
                              const double volumeStep,
                              const string fillingModeLabel,
                              const int openPositionCount,
                              const bool oldStateReuseDetected)
  {
   CMt5Clock clock;
   CFileBasketRepository repository(BRE_PERSISTENCE_BASKET_SUBDIR);
   CFilePendingExecutionStore store(PENDING_STORE_RELATIVE_PATH);
   string pendingRestoreOutcome="NOT_EVALUATED";
   CVoidResult restoreResult=store.RestoreFromDisk();
   pendingRestoreOutcome=store.LastRestoreOutcome();
   if(restoreResult.IsFail())
     {
      PrintDryRunSummary(true,
                         "",
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
                         openPositionCount,
                         true,
                         "RESTORE_FAILED",
                         restoreResult.ErrorMessage(),
                         pendingRestoreOutcome,
                         false,
                         false,
                         false,
                         0);
      return false;
     }

   CPendingExecutionRegistry registry;
   HydrateRegistryFromStore(registry,store);

   const CBasketId basketId(InpBasketId);
   CTradeExecutionRequest request;
   long resolvedBasketVersion=0;
   string requestBuildReason="";
   if(!TryBuildVersionAwareSeedRequest(repository,
                                       basketId,
                                       direction,
                                       clock,
                                       request,
                                       resolvedBasketVersion,
                                       requestBuildReason))
     {
      PrintDryRunSummary(true,
                         "",
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
                         openPositionCount,
                         true,
                         "REQUEST_BUILD_FAILED",
                         requestBuildReason,
                         pendingRestoreOutcome,
                         repository.Exists(basketId),
                         false,
                         false,
                         resolvedBasketVersion);
      return false;
     }

   string classification="";
   string classifyReason="";
   bool basketExistsBefore=false;
   bool pendingEntryExistsBefore=false;
   bool pendingEnvelopeExistsBefore=false;
   const bool classifiable=ClassifySeedState(repository,
                                             registry,
                                             store,
                                             request,
                                             direction,
                                             clock.Now(),
                                             classification,
                                             classifyReason,
                                             basketExistsBefore,
                                             pendingEntryExistsBefore,
                                             pendingEnvelopeExistsBefore);
   if(!classifiable)
     {
      PrintDryRunSummary(true,
                         "",
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
                         openPositionCount,
                         true,
                         classification,
                         classifyReason,
                         pendingRestoreOutcome,
                         basketExistsBefore,
                         pendingEntryExistsBefore,
                         pendingEnvelopeExistsBefore,
                         resolvedBasketVersion);
      return false;
     }

   PrintDryRunSummary(true,
                      "",
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
                      openPositionCount,
                      true,
                      classification,
                      "",
                      pendingRestoreOutcome,
                      basketExistsBefore,
                      pendingEntryExistsBefore,
                      pendingEnvelopeExistsBefore,
                      resolvedBasketVersion);
   return true;
  }

void PrintWriteModeSummary(const string seedStateResult,
                           const string seedStateReason,
                           const string classification,
                           const string pendingRestoreOutcome,
                           const bool basketExistsBefore,
                           const bool pendingEntryExistsBefore,
                           const bool pendingEnvelopeExistsBefore,
                           const bool writePerformed,
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
   PrintLine("sprint8d_seed_setup_mode=WRITE_MODE");
   PrintCommonContext(directionLabel,
                      terminalDataPath,
                      accountTradeModeLabel,
                      accountMarginModeLabel,
                      accountTradeAllowed,
                      symbolTradeModeLabel,
                      minVolume,
                      volumeStep,
                      fillingModeLabel,
                      openPositionCount);
   PrintLine("seed_state_classification="+classification);
   PrintLine("pending_restore_outcome="+pendingRestoreOutcome);
   PrintLine("basket_exists_before="+(basketExistsBefore?"true":"false"));
   PrintLine("pending_entry_exists_before="+(pendingEntryExistsBefore?"true":"false"));
   PrintLine("pending_envelope_exists_before="+(pendingEnvelopeExistsBefore?"true":"false"));
   PrintLine("write_performed="+(writePerformed?"true":"false"));
   PrintLine("seed_state_result="+seedStateResult);
   PrintLine("seed_state_reason="+seedStateReason);
   if(seedStateResult=="PASS" || seedStateResult=="IDEMPOTENT_ALREADY_PREPARED")
      PrintLine("next_safe_step=REVIEW_PREPARED_STATE_BEFORE_ANY_SUBMISSION");
   else
      PrintLine("next_safe_step=DO_NOT_SUBMIT_OR_OVERWRITE_STATE");
  }

bool VerifyPostWriteState(CFileBasketRepository &repository,
                          const CTradeExecutionRequest &request,
                          const ENUM_BRE_TRADE_DIRECTION direction,
                          const datetime nowUtc,
                          const int unrelatedEntriesBefore,
                          string &reasonOut)
  {
   reasonOut="";
   CFilePendingExecutionStore verifyStore(PENDING_STORE_RELATIVE_PATH);
   CVoidResult restoreResult=verifyStore.RestoreFromDisk();
   if(restoreResult.IsFail())
     {
      reasonOut="Post-write pending restore failed: "+restoreResult.ErrorMessage();
      return false;
     }

   int unrelatedAfter=CountUnrelatedPendingEntries(verifyStore,
                                                   request.ExecutionRequestId(),
                                                   request.IdempotencyKey());
   if(unrelatedAfter<unrelatedEntriesBefore)
     {
      reasonOut="Post-write verification removed unrelated pending records";
      return false;
     }

   CResult<CBasketAggregate> basketResult=repository.Load(request.BasketId());
   if(basketResult.IsFail())
     {
      reasonOut="Post-write basket load failed";
      return false;
     }
   CBasketAggregate basket;
   basketResult.TryGetValue(basket);
   string basketReason="";
   if(!BasketMatchesSeedContract(basket,direction,(long)request.ExpectedBasketVersion(),basketReason))
     {
      reasonOut="Post-write basket contract mismatch: "+basketReason;
      return false;
     }

   CPendingExecutionRegistry verifyRegistry;
   HydrateRegistryFromStore(verifyRegistry,verifyStore);
   CPendingExecutionEntry entry;
   if(!verifyRegistry.TryGetByExecutionRequestId(request.ExecutionRequestId(),entry))
     {
      reasonOut="Post-write target pending entry missing";
      return false;
     }
   if(!PendingEntryMatchesRequest(entry,request))
     {
      reasonOut="Post-write target pending entry contract mismatch";
      return false;
     }

   CResult<CBrokerSubmissionEnvelope> envelopeResult=verifyStore.FindEnvelopeByIdempotencyKey(request.IdempotencyKey());
   CBrokerSubmissionEnvelope envelope;
   if(!envelopeResult.TryGetValue(envelope))
     {
      reasonOut="Post-write target envelope missing";
      return false;
     }
   if(!EnvelopeMatchesSeedRequest(envelope,request,nowUtc))
     {
      reasonOut="Post-write target envelope contract mismatch";
      return false;
     }
   return true;
  }

bool RunWriteMode(const ENUM_BRE_TRADE_DIRECTION direction,
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
   CMt5Clock clock;
   CMt5UniqueIdGenerator idGenerator;
   CFileBasketRepository repository(BRE_PERSISTENCE_BASKET_SUBDIR);
   CFilePendingExecutionStore store(PENDING_STORE_RELATIVE_PATH);

   CVoidResult restoreResult=store.RestoreFromDisk();
   string pendingRestoreOutcome=store.LastRestoreOutcome();
   if(restoreResult.IsFail())
     {
      PrintWriteModeSummary("FAIL",
                            restoreResult.ErrorMessage(),
                            "RESTORE_FAILED",
                            pendingRestoreOutcome,
                            false,
                            false,
                            false,
                            false,
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
      return false;
     }

   CPendingExecutionRegistry registry;
   HydrateRegistryFromStore(registry,store);

   const CBasketId basketId(InpBasketId);
   CTradeExecutionRequest request;
   long resolvedBasketVersion=0;
   string requestBuildReason="";
   if(!TryBuildVersionAwareSeedRequest(repository,
                                       basketId,
                                       direction,
                                       clock,
                                       request,
                                       resolvedBasketVersion,
                                       requestBuildReason))
     {
      PrintWriteModeSummary("FAIL",
                            requestBuildReason,
                            "REQUEST_BUILD_FAILED",
                            pendingRestoreOutcome,
                            repository.Exists(basketId),
                            false,
                            false,
                            false,
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
      return false;
     }
   const datetime nowUtc=clock.Now();

   string classification="";
   string classifyReason="";
   bool basketExistsBefore=false;
   bool pendingEntryExistsBefore=false;
   bool pendingEnvelopeExistsBefore=false;
   bool classifiable=ClassifySeedState(repository,
                                       registry,
                                       store,
                                       request,
                                       direction,
                                       nowUtc,
                                       classification,
                                       classifyReason,
                                       basketExistsBefore,
                                       pendingEntryExistsBefore,
                                       pendingEnvelopeExistsBefore);

   if(!classifiable)
     {
      PrintWriteModeSummary("FAIL",
                            classifyReason,
                            classification,
                            pendingRestoreOutcome,
                            basketExistsBefore,
                            pendingEntryExistsBefore,
                            pendingEnvelopeExistsBefore,
                            false,
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
      return false;
     }

   if(classification=="D_IDEMPOTENT_ALREADY_PREPARED")
     {
      PrintWriteModeSummary("IDEMPOTENT_ALREADY_PREPARED",
                            classifyReason,
                            classification,
                            pendingRestoreOutcome,
                            basketExistsBefore,
                            pendingEntryExistsBefore,
                            pendingEnvelopeExistsBefore,
                            false,
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
      return true;
     }

   const int unrelatedEntriesBefore=CountUnrelatedPendingEntries(store,
                                                                 request.ExecutionRequestId(),
                                                                 request.IdempotencyKey());

   CBasketAggregate basket;
   if(classification=="A_FRESH")
     {
      CExecutionDryRunTestBasketSeedService seedService;
      if(!seedService.Initialize(&repository,&clock,&idGenerator,"default"))
        {
         PrintWriteModeSummary("FAIL",
                               "Seed service init failed",
                               classification,
                               pendingRestoreOutcome,
                               basketExistsBefore,
                               pendingEntryExistsBefore,
                               pendingEnvelopeExistsBefore,
                               false,
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
         return false;
        }

      string strategyJson=CSprint8dDemoM123StrategyProfile::CanonicalJson();
      CResult<CBasketAggregate> seedResult=seedService.SeedActiveBasket(basketId,
                                                                        InpSymbol,
                                                                        direction,
                                                                        strategyJson);
      if(seedResult.IsFail())
        {
         PrintWriteModeSummary("FAIL",
                               seedResult.ErrorMessage(),
                               classification,
                               pendingRestoreOutcome,
                               basketExistsBefore,
                               pendingEntryExistsBefore,
                               pendingEnvelopeExistsBefore,
                               false,
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
         return false;
        }
      seedResult.TryGetValue(basket);
      CResult<CBasketAggregate> reloaded=repository.Load(basketId);
      if(reloaded.IsFail())
        {
         PrintWriteModeSummary("FAIL",
                               reloaded.ErrorMessage(),
                               classification,
                               pendingRestoreOutcome,
                               basketExistsBefore,
                               pendingEntryExistsBefore,
                               pendingEnvelopeExistsBefore,
                               false,
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
         return false;
        }
      reloaded.TryGetValue(basket);
     }
   else if(classification=="B_EXISTING_BASKET_ONLY")
     {
      CResult<CBasketAggregate> loaded=repository.Load(basketId);
      if(loaded.IsFail())
        {
         PrintWriteModeSummary("FAIL",
                               loaded.ErrorMessage(),
                               classification,
                               pendingRestoreOutcome,
                               basketExistsBefore,
                               pendingEntryExistsBefore,
                               pendingEnvelopeExistsBefore,
                               false,
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
         return false;
        }
      loaded.TryGetValue(basket);
     }
   else
     {
      PrintWriteModeSummary("FAIL",
                            "Unsupported writable classification: "+classification,
                            classification,
                            pendingRestoreOutcome,
                            basketExistsBefore,
                            pendingEntryExistsBefore,
                            pendingEnvelopeExistsBefore,
                            false,
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
      return false;
     }

   resolvedBasketVersion=(long)basket.Version();
   string versionGuardReason="";
   if(!ValidateInputBasketVersionGuard(resolvedBasketVersion,versionGuardReason))
     {
      PrintWriteModeSummary("FAIL",
                            versionGuardReason,
                            classification,
                            pendingRestoreOutcome,
                            basketExistsBefore,
                            pendingEntryExistsBefore,
                            pendingEnvelopeExistsBefore,
                            false,
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
      return false;
     }

   string basketReason="";
   if(!BasketMatchesSeedContract(basket,direction,resolvedBasketVersion,basketReason))
     {
      PrintWriteModeSummary("FAIL",
                            "Basket contract mismatch before pending prepare: "+basketReason,
                            classification,
                            pendingRestoreOutcome,
                            basketExistsBefore,
                            pendingEntryExistsBefore,
                            pendingEnvelopeExistsBefore,
                            false,
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
      return false;
     }

   request=BuildSeedExecutionRequest(basketId,
                                   direction,
                                   resolvedBasketVersion,
                                   basket.StrategyProfileHash(),
                                   clock);
   PrintBasketVersionBinding(resolvedBasketVersion);

   CMt5MarketDataProvider marketData(&clock);
   CMarketSafetyConfig marketSafety=CMarketSafetyConfig::Create(5000,500000,30000);
   CSubmissionPreparationValidator validator(&marketData,marketSafety);
   CSubmissionPreparationPolicy prepPolicy=CSubmissionPreparationPolicy(31,5000,ENVELOPE_VALIDITY_SECONDS);
   CExecutionSubmissionPreparer preparer(prepPolicy,validator,&registry,&store,&clock);

   CSubmissionPreparationResult prep=preparer.PrepareForValidationSeed(request,basket,InpMagicNumber);
   if(!prep.IsSuccess())
     {
      PrintWriteModeSummary("FAIL",
                            prep.FailureMessage(),
                            classification,
                            pendingRestoreOutcome,
                            basketExistsBefore,
                            pendingEntryExistsBefore,
                            pendingEnvelopeExistsBefore,
                            false,
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
      return false;
     }

   string verifyReason="";
   if(!VerifyPostWriteState(repository,request,direction,nowUtc,unrelatedEntriesBefore,verifyReason))
     {
      PrintWriteModeSummary("FAIL",
                            verifyReason,
                            classification,
                            pendingRestoreOutcome,
                            basketExistsBefore,
                            pendingEntryExistsBefore,
                            pendingEnvelopeExistsBefore,
                            true,
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
      return false;
     }

   PrintWriteModeSummary("PASS",
                         "Isolated basket and pending state prepared without broker submission",
                         classification,
                         pendingRestoreOutcome,
                         basketExistsBefore,
                         pendingEntryExistsBefore,
                         pendingEnvelopeExistsBefore,
                         true,
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
   return true;
  }

void OnStart(void)
  {
   const string symbol=InpSymbol;
   SymbolSelect(symbol,true);

   const string terminalDataPath=TerminalInfoString(TERMINAL_DATA_PATH);
   string brokerWaitReason="";
   if(!WaitForD0EBrokerAuthorization(brokerWaitReason))
     {
      if(InpWriteMode)
         PrintWriteModeSummary("FAIL",
                               brokerWaitReason,
                               "BROKER_AUTHORIZATION_TIMEOUT",
                               "NOT_EVALUATED",
                               false,
                               false,
                               false,
                               false,
                               InpDirection,
                               terminalDataPath,
                               "UNKNOWN",
                               "UNKNOWN",
                               false,
                               "UNKNOWN",
                               0.0,
                               0.0,
                               "NONE",
                               0);
      else
         PrintDryRunSummary(false,
                            brokerWaitReason,
                            false,
                            InpDirection,
                            terminalDataPath,
                            "UNKNOWN",
                            "UNKNOWN",
                            false,
                            "UNKNOWN",
                            0.0,
                            0.0,
                            "NONE",
                            0,
                            false,
                            "",
                            "",
                            "",
                            false,
                            false,
                            false,
                            0);
      return;
     }

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
   ENUM_BRE_TRADE_DIRECTION direction=BRE_DIRECTION_NONE;
   string parsedDirectionLabel="";
   bool preflightOk=RunSeedSetupPreflight(terminalDataPath,
                                          accountTradeModeLabel,
                                          accountMarginModeLabel,
                                          accountTradeAllowed,
                                          symbolTradeModeLabel,
                                          minVolume,
                                          volumeStep,
                                          fillingModeLabel,
                                          openPositionCount,
                                          parsedDirectionLabel,
                                          oldStateReuseDetected,
                                          matchedIdentifier,
                                          failureReason);
   if(parsedDirectionLabel!="")
      directionLabel=parsedDirectionLabel;
   else
      directionLabel=InpDirection;
   TryParseDirection(InpDirection,direction,directionLabel);

   if(!preflightOk)
     {
      if(InpWriteMode)
         PrintWriteModeSummary("FAIL",
                               failureReason,
                               "PREFLIGHT_FAILED",
                               "NOT_EVALUATED",
                               false,
                               false,
                               false,
                               false,
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
      else
         PrintDryRunSummary(preflightOk,
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
                            openPositionCount,
                            false,
                            "",
                            "",
                            "",
                            false,
                            false,
                            false,
                            0);
      return;
     }

   if(InpWriteMode)
     {
      RunWriteMode(direction,
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
      return;
     }

   RunDryRunStateInspection(direction,
                           directionLabel,
                           terminalDataPath,
                           accountTradeModeLabel,
                           accountMarginModeLabel,
                           accountTradeAllowed,
                           symbolTradeModeLabel,
                           minVolume,
                           volumeStep,
                           fillingModeLabel,
                           openPositionCount,
                           oldStateReuseDetected);
  }
