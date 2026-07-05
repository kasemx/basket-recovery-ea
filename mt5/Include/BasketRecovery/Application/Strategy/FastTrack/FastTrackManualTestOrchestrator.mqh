#ifndef BRE_APP_FAST_TRACK_MANUAL_TEST_ORCHESTRATOR_MQH
#define BRE_APP_FAST_TRACK_MANUAL_TEST_ORCHESTRATOR_MQH

#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackManualTestTypes.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackManualTestSecurityGate.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackSignalDetailsFactory.mqh>
#include <BasketRecovery/Domain/Strategy/FastTrack/FastTrackSignalParser.mqh>
#include <BasketRecovery/Domain/Strategy/FastTrack/FastTrackSignalTextUtils.mqh>
#include <BasketRecovery/Domain/Strategy/FastTrack/FastTrackSeedBasketMatcher.mqh>
#include <BasketRecovery/Domain/ValueObjects/SignalDetails.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

struct SFastTrackManualBasketRecord
  {
   string                    basket_id;
   string                    symbol;
   ENUM_BRE_TRADE_DIRECTION  direction;
   datetime                  seed_received_at;
   ENUM_BRE_FAST_TRACK_MANUAL_TEST_STAGE stage;
   CSignalDetails            signal_details;
   bool                      has_signal_details;
   string                    idempotency_fingerprint;
   bool                      seed_order_planned;
  };

class CFastTrackManualTestOrchestrator
  {
private:
   SFastTrackManualBasketRecord m_baskets[];
   string                       m_processed_fingerprints[];
   int                          m_seed_timeout_seconds;

   static string     NormalizeFingerprintPart(const string value)
     {
      string text=value;
      StringReplace(text,"\r\n","\n");
      StringReplace(text,"\r","");
      StringTrimLeft(text);
      StringTrimRight(text);
      return text;
     }

   static string     BuildFingerprint(const string seedText,const string detailsText)
     {
      return "fast-track-manual:"+NormalizeFingerprintPart(seedText)+"|"+NormalizeFingerprintPart(detailsText);
     }

   static string     BuildBasketId(const SFastTrackSignalParseResult &seed,const datetime nowUtc)
     {
      return "fast-track-"+seed.symbol+"-"+CTradeDirectionHelper::ToString(seed.direction)+"-"+IntegerToString((long)nowUtc);
     }

   bool              HasProcessedFingerprint(const string fingerprint) const
     {
      for(int i=0;i<ArraySize(m_processed_fingerprints);i++)
        {
         if(m_processed_fingerprints[i]==fingerprint)
            return true;
        }
      return false;
     }

   void              MarkProcessedFingerprint(const string fingerprint)
     {
      if(HasProcessedFingerprint(fingerprint))
         return;
      int size=ArraySize(m_processed_fingerprints);
      ArrayResize(m_processed_fingerprints,size+1);
      m_processed_fingerprints[size]=fingerprint;
     }

   int               FindOpenSeedIndex(const string symbol,const ENUM_BRE_TRADE_DIRECTION direction) const
     {
      for(int i=0;i<ArraySize(m_baskets);i++)
        {
         if(m_baskets[i].stage==BRE_FAST_TRACK_MANUAL_STAGE_WAIT_DETAILS &&
            m_baskets[i].symbol==symbol &&
            m_baskets[i].direction==direction)
            return i;
        }
      return -1;
     }

   int               RegisterSeedBasket(const SFastTrackSignalParseResult &seed,const datetime nowUtc)
     {
      int existing=FindOpenSeedIndex(seed.symbol,seed.direction);
      if(existing>=0)
         return existing;

      SFastTrackManualBasketRecord record;
      record.basket_id=BuildBasketId(seed,nowUtc);
      record.symbol=seed.symbol;
      record.direction=seed.direction;
      record.seed_received_at=nowUtc;
      record.stage=BRE_FAST_TRACK_MANUAL_STAGE_WAIT_DETAILS;
      record.has_signal_details=false;
      record.idempotency_fingerprint="";
      record.seed_order_planned=false;

      int size=ArraySize(m_baskets);
      ArrayResize(m_baskets,size+1);
      m_baskets[size]=record;
      return size;
     }

   void              BuildSeedRegistry(SFastTrackSeedBasketRecord &records[],int &recordCount,const datetime nowUtc) const
     {
      recordCount=0;
      for(int i=0;i<ArraySize(m_baskets);i++)
        {
         if(m_baskets[i].stage!=BRE_FAST_TRACK_MANUAL_STAGE_WAIT_DETAILS)
            continue;
         ArrayResize(records,recordCount+1);
         records[recordCount]=SFastTrackSeedBasketRecord::Create(m_baskets[i].basket_id,
                                                                 m_baskets[i].symbol,
                                                                 m_baskets[i].direction,
                                                                 m_baskets[i].seed_received_at);
         recordCount++;
        }
     }

   static void       FillRejected(SFastTrackManualTestOutcome &outcome,const string detail)
     {
      outcome.stage=BRE_FAST_TRACK_MANUAL_STAGE_REJECTED;
      outcome.order_plan_result=BRE_FAST_TRACK_ORDER_PLAN_BLOCKED;
      outcome.detail=detail;
     }

public:
                     CFastTrackManualTestOrchestrator(void)
     {
      m_seed_timeout_seconds=3600;
      ArrayResize(m_baskets,0);
      ArrayResize(m_processed_fingerprints,0);
     }

   void              Reset(void)
     {
      ArrayResize(m_baskets,0);
      ArrayResize(m_processed_fingerprints,0);
     }

   void              SetSeedTimeoutSeconds(const int seconds) { m_seed_timeout_seconds=seconds; }

   SFastTrackManualTestOutcome Process(const SFastTrackManualTestInputs &inputs,const datetime nowUtc)
     {
      SFastTrackManualTestOutcome outcome;
      outcome.Reset();

      if(!inputs.enabled)
        {
         outcome.detail="Manual test disabled";
         return outcome;
        }

      SFastTrackSignalParseResult seed=CFastTrackSignalParser::ParseSeed(inputs.seed_text);
      outcome.seed_parse_valid=seed.valid;
      if(!seed.valid)
        {
         FillRejected(outcome,CFastTrackSignalTypeText::ParseFailureToString(seed.failure_reason));
         return outcome;
        }

      if(seed.symbol!="XAUUSD")
        {
         FillRejected(outcome,"Symbol must be XAUUSD");
         return outcome;
        }

      string detailsText=CFastTrackSignalTextUtils::Trim(inputs.details_text);
      if(detailsText=="")
        {
         int basketIndex=RegisterSeedBasket(seed,nowUtc);
         outcome.stage=BRE_FAST_TRACK_MANUAL_STAGE_WAIT_DETAILS;
         outcome.basket_id=m_baskets[basketIndex].basket_id;
         outcome.detail="Seed registered; waiting for details";
         return outcome;
        }

      string fingerprint=BuildFingerprint(inputs.seed_text,detailsText);
      if(HasProcessedFingerprint(fingerprint))
        {
         outcome.stage=BRE_FAST_TRACK_MANUAL_STAGE_IDEMPOTENT_SKIP;
         outcome.order_plan_result=BRE_FAST_TRACK_ORDER_PLAN_IDEMPOTENT_SKIP;
         outcome.detail="Seed and details combination already processed";
         return outcome;
        }

      SFastTrackSignalParseResult details=CFastTrackSignalParser::ParseDetails(detailsText);
      outcome.details_parse_valid=details.valid;
      if(!details.valid)
        {
         FillRejected(outcome,CFastTrackSignalTypeText::ParseFailureToString(details.failure_reason));
         return outcome;
        }

      if(details.symbol!="XAUUSD")
        {
         FillRejected(outcome,"Details symbol must be XAUUSD");
         return outcome;
        }

      if(details.direction!=seed.direction)
        {
         FillRejected(outcome,"Seed and details direction mismatch");
         return outcome;
        }

      int basketIndex=RegisterSeedBasket(seed,nowUtc);
      SFastTrackSeedBasketRecord seedRecords[];
      int seedRecordCount=0;
      BuildSeedRegistry(seedRecords,seedRecordCount,nowUtc);
      SFastTrackDetailsMatchOutcome match=CFastTrackSeedBasketMatcher::MatchDetails(details,seedRecords,seedRecordCount,
                                                                                    nowUtc,m_seed_timeout_seconds);
      if(match.result!=BRE_FAST_TRACK_MATCH_OK)
        {
         FillRejected(outcome,CFastTrackSignalTypeText::MatchResultToString(match.result));
         return outcome;
        }

      m_baskets[basketIndex].stage=BRE_FAST_TRACK_MANUAL_STAGE_DETAILS_BOUND;
      m_baskets[basketIndex].signal_details=CFastTrackSignalDetailsFactory::FromParseResult(details);
      m_baskets[basketIndex].has_signal_details=true;
      m_baskets[basketIndex].idempotency_fingerprint=fingerprint;
      outcome.stage=BRE_FAST_TRACK_MANUAL_STAGE_DETAILS_BOUND;
      outcome.basket_id=m_baskets[basketIndex].basket_id;
      outcome.runner_enabled=details.runner_enabled;
      outcome.sl_apply_planned=true;

      string blockReason="";
      if(CFastTrackManualTestSecurityGate::AllowsSeedOrderExecution(inputs,blockReason))
        {
         outcome.order_plan_result=BRE_FAST_TRACK_ORDER_PLAN_ALLOWED;
         outcome.detail="Seed order plan allowed; SL apply planned; TP levels stored for audit only";
         m_baskets[basketIndex].seed_order_planned=true;
         MarkProcessedFingerprint(fingerprint);
         return outcome;
        }

      outcome.order_plan_result=BRE_FAST_TRACK_ORDER_PLAN_BLOCKED;
      outcome.block_reason=blockReason;
      outcome.detail="Audit only; seed order blocked by security gate";
      MarkProcessedFingerprint(fingerprint);
      return outcome;
     }

   static void       PrintAudit(const SFastTrackManualTestInputs &inputs,const SFastTrackManualTestOutcome &outcome)
     {
      Print("fast_track_manual_test_enabled=",inputs.enabled?"true":"false");
      Print("fast_track_seed_parse_valid=",outcome.seed_parse_valid?"true":"false");
      Print("fast_track_details_parse_valid=",outcome.details_parse_valid?"true":"false");
      Print("fast_track_basket_stage=",CFastTrackManualTestTypeText::StageToString(outcome.stage));
      Print("fast_track_basket_id=",outcome.basket_id);
      Print("fast_track_order_plan_result=",CFastTrackManualTestTypeText::OrderPlanToString(outcome.order_plan_result));
      Print("fast_track_order_plan_block_reason=",outcome.block_reason);
      Print("fast_track_sl_apply_planned=",outcome.sl_apply_planned?"true":"false");
      Print("fast_track_runner_enabled=",outcome.runner_enabled?"true":"false");
      Print("fast_track_recovery_execution_enabled=",inputs.enable_recovery?"true":"false");
      Print("fast_track_range_add_execution_enabled=",inputs.enable_range_add?"true":"false");
      Print("fast_track_de_risk_execution_enabled=",inputs.enable_de_risk?"true":"false");
      Print("fast_track_break_even_execution_enabled=",inputs.enable_break_even?"true":"false");
      Print("fast_track_detail=",outcome.detail);
     }
  };

#endif
