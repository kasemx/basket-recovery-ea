#ifndef BRE_APP_FAST_TRACK_DEMO_SUBMISSION_BRIDGE_MQH
#define BRE_APP_FAST_TRACK_DEMO_SUBMISSION_BRIDGE_MQH

#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackDemoSubmissionTypes.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackDemoSubmissionSltpNormalizer.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackDemoSubmissionCandidateRegistry.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackManualTestTypes.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackManualTestSecurityGate.mqh>
#include <BasketRecovery/Domain/Strategy/FastTrack/FastTrackSignalParser.mqh>
#include <BasketRecovery/Domain/Strategy/FastTrack/FastTrackSignalTextUtils.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Shared/Utils/Crc32.mqh>

class CFastTrackDemoSubmissionBridge
  {
private:
   static string     NormalizeFingerprintPart(const string value)
     {
      string text=value;
      StringReplace(text,"\r\n","\n");
      StringReplace(text,"\r","");
      StringTrimLeft(text);
      StringTrimRight(text);
      return text;
     }

   static string     BuildIdempotencyKey(const string seedText,const string detailsText)
     {
      return "fast-track-manual:"+NormalizeFingerprintPart(seedText)+"|"+NormalizeFingerprintPart(detailsText);
     }

   static string     BuildExecutionRequestId(const string idempotencyKey)
     {
      const string digest=StringSubstr(CCrc32::ToHex(CCrc32::Compute(idempotencyKey)),0,12);
      return "fasttrack-demo-open:"+digest;
     }

   static void       FillRejected(SFastTrackDemoSubmissionBridgeOutcome &outcome,
                                  const ENUM_BRE_FT_DEMO_SUB_STATUS status,
                                  const string blockReason,
                                  const string detail)
     {
      outcome.status=status;
      outcome.block_reason=blockReason;
      outcome.detail=detail;
      outcome.candidate_created=false;
     }

   static bool       PassesBridgeGates(const SFastTrackDemoSubmissionBridgeInputs &bridgeInputs,
                                       string &blockReasonOut)
     {
      blockReasonOut="";
      if(!bridgeInputs.enabled)
        {
         blockReasonOut="FAST_TRACK_BRIDGE_DISABLED";
         return false;
        }
      if(!bridgeInputs.require_manual_demo_authorization)
        {
         blockReasonOut="MANUAL_DEMO_AUTHORIZATION_NOT_REQUIRED";
         return false;
        }
      if(!bridgeInputs.audit_file_polling_enabled)
        {
         blockReasonOut="FAST_TRACK_AUDIT_FILE_POLLING_DISABLED";
         return false;
        }
      if(bridgeInputs.observer_only_startup_isolation)
        {
         blockReasonOut="OBSERVER_ONLY_STARTUP_ISOLATION";
         return false;
        }
      if(bridgeInputs.global_execution_kill_switch)
        {
         blockReasonOut="GLOBAL_EXECUTION_KILL_SWITCH";
         return false;
        }
      if(!bridgeInputs.enable_live_demo_execution)
        {
         blockReasonOut="LIVE_DEMO_EXECUTION_DISABLED";
         return false;
        }
      if(!bridgeInputs.allow_demo_seed_execution)
        {
         blockReasonOut="FAST_TRACK_DEMO_SEED_EXECUTION_DISABLED";
         return false;
        }
      if(bridgeInputs.execution_mode!=(int)BRE_EXEC_RUNTIME_DEMO_MANUAL_SUBMISSION)
        {
         blockReasonOut="EXECUTION_MODE_NOT_DEMO_MANUAL_SUBMISSION";
         return false;
        }
      if(bridgeInputs.seed_order_count!=1)
        {
         blockReasonOut="SEED_ORDER_COUNT_NOT_ONE";
         return false;
        }
      if(bridgeInputs.seed_lot<=0.0)
        {
         blockReasonOut="SEED_LOT_INVALID";
         return false;
        }
      if(bridgeInputs.enable_recovery || bridgeInputs.enable_range_add ||
         bridgeInputs.enable_de_risk || bridgeInputs.enable_break_even ||
         bridgeInputs.enable_re_entry || bridgeInputs.enable_partial_close ||
         bridgeInputs.enable_trailing)
        {
         blockReasonOut="FAST_TRACK_EXTENDED_EXECUTION_FLAGS_ENABLED";
         return false;
        }
      if(!bridgeInputs.environment.account_is_demo)
        {
         blockReasonOut="ACCOUNT_NOT_DEMO";
         return false;
        }
      if(bridgeInputs.environment.open_positions_for_symbol>0 ||
         bridgeInputs.environment.pending_orders_for_symbol>0)
        {
         blockReasonOut="OPEN_POSITION_OR_PENDING_EXISTS";
         return false;
        }
      return true;
     }

   static double     EstimateRiskUsd(const ENUM_BRE_TRADE_DIRECTION direction,
                                     const double entryPrice,
                                     const double stopLoss,
                                     const double volume,
                                     const SFastTrackDemoSubmissionEnvironment &environment)
     {
      if(entryPrice<=0.0 || stopLoss<=0.0 || volume<=0.0)
         return 0.0;
      const double tickSize=environment.symbol_tick_size>0.0 ? environment.symbol_tick_size : environment.symbol_point;
      const double tickValue=environment.symbol_tick_value>0.0 ? environment.symbol_tick_value : 1.0;
      if(tickSize<=0.0)
         return 0.0;
      const double distance=MathAbs(entryPrice-stopLoss);
      const double ticks=distance/tickSize;
      return ticks*tickValue*volume;
     }

   static double     RiskLimitUsd(const double equityUsd)
     {
      const double equityCap=equityUsd*0.001;
      return MathMin(10.0,equityCap);
     }

   static bool       VolumeMatchesBrokerMin(const double volume,
                                            const SFastTrackDemoSubmissionEnvironment &environment)
     {
      const double minLot=environment.symbol_min_lot>0.0 ? environment.symbol_min_lot : 0.01;
      const double step=environment.symbol_volume_step>0.0 ? environment.symbol_volume_step : 0.01;
      if(volume+1e-8<minLot)
         return false;
      const double steps=MathRound((volume-minLot)/step);
      const double normalized=minLot+steps*step;
      return MathAbs(normalized-volume)<=step*0.01+1e-8;
     }

public:
   static SFastTrackDemoSubmissionBridgeOutcome TryCreateCandidate(
      const SFastTrackManualTestInputs &manualInputs,
      const SFastTrackManualTestOutcome &manualOutcome,
      const SFastTrackDemoSubmissionBridgeInputs &bridgeInputs,
      CFastTrackDemoSubmissionCandidateRegistry &registry,
      const datetime nowUtc)
     {
      SFastTrackDemoSubmissionBridgeOutcome outcome;
      outcome.Reset();

      if(manualOutcome.order_plan_result!=BRE_FAST_TRACK_ORDER_PLAN_ALLOWED ||
         manualOutcome.stage!=BRE_FAST_TRACK_MANUAL_STAGE_DETAILS_BOUND)
        {
         FillRejected(outcome,BRE_FT_DEMO_SUB_REJECTED,"ORDER_PLAN_NOT_ALLOWED","FastTrack order plan is not allowed");
         return outcome;
        }

      outcome.status=BRE_FT_DEMO_SUB_PLAN_ALLOWED;

      string blockReason="";
      if(!PassesBridgeGates(bridgeInputs,blockReason))
        {
         FillRejected(outcome,BRE_FT_DEMO_SUB_REJECTED,blockReason,blockReason);
         return outcome;
        }

      SFastTrackManualTestInputs gateProbe=manualInputs;
      if(!CFastTrackManualTestSecurityGate::AllowsSeedOrderExecution(gateProbe,blockReason))
        {
         FillRejected(outcome,BRE_FT_DEMO_SUB_REJECTED,blockReason,blockReason);
         return outcome;
        }

      const string detailsText=CFastTrackSignalTextUtils::Trim(manualInputs.details_text);
      const string idempotencyKey=BuildIdempotencyKey(manualInputs.seed_text,detailsText);
      if(registry.HasProcessedIdempotencyKey(idempotencyKey))
        {
         FillRejected(outcome,BRE_FT_DEMO_SUB_DUP_BLOCKED,
                      "FASTTRACK_DUPLICATE_BLOCKED","Idempotency key already processed by demo submission bridge");
         return outcome;
        }

      SFastTrackSignalParseResult seed=CFastTrackSignalParser::ParseSeed(manualInputs.seed_text);
      SFastTrackSignalParseResult details=CFastTrackSignalParser::ParseDetails(detailsText);
      if(!seed.valid || !details.valid || seed.symbol!="XAUUSD" || details.symbol!="XAUUSD")
        {
         FillRejected(outcome,BRE_FT_DEMO_SUB_REJECTED,
                      "SIGNAL_PARSE_INVALID","FastTrack signal parse invalid for demo submission bridge");
         return outcome;
        }

      SFastTrackDemoSubmissionSltpOutcome sltp=CFastTrackDemoSubmissionSltpNormalizer::TryNormalize(
         details.direction,details.hard_stop_loss,details.take_profit_levels,details.take_profit_count,
         bridgeInputs.environment);
      if(!sltp.valid)
        {
         FillRejected(outcome,BRE_FT_DEMO_SUB_SLTP_INVALID,sltp.failure_detail,sltp.failure_detail);
         return outcome;
        }

      const double volume=manualInputs.seed_lot;
      if(!VolumeMatchesBrokerMin(volume,bridgeInputs.environment))
        {
         FillRejected(outcome,BRE_FT_DEMO_SUB_REJECTED,
                      "SEED_LOT_NOT_BROKER_MIN","Seed lot must match broker minimum lot and step");
         return outcome;
        }

      const double entryPrice=(details.direction==BRE_DIRECTION_BUY) ?
                              bridgeInputs.environment.symbol_ask :
                              bridgeInputs.environment.symbol_bid;
      const double riskEstimate=EstimateRiskUsd(details.direction,entryPrice,sltp.normalized_stop_loss,
                                                volume,bridgeInputs.environment);
      const double riskLimit=RiskLimitUsd(bridgeInputs.environment.account_equity_usd);
      if(riskEstimate>riskLimit+1e-8)
        {
         FillRejected(outcome,BRE_FT_DEMO_SUB_RISK_BLOCKED,
                      "FASTTRACK_RISK_BLOCKED",
                      StringFormat("Estimated risk %.4f exceeds limit %.4f",riskEstimate,riskLimit));
         return outcome;
        }

      const long magicNumber=bridgeInputs.magic_number_override;
      if(magicNumber<=0)
        {
         FillRejected(outcome,BRE_FT_DEMO_SUB_MAGIC_REQUIRED,
                      "MAGIC_CONFIGURATION_REQUIRED","FastTrack demo submission magic override is required");
         return outcome;
        }

      string basketId=bridgeInputs.manual_demo_authorization_basket_id;
      if(basketId=="")
         basketId=manualOutcome.basket_id;
      if(basketId=="")
        {
         FillRejected(outcome,BRE_FT_DEMO_SUB_REJECTED,
                      "BASKET_ID_REQUIRED","Manual demo authorization basket id is required");
         return outcome;
        }

      SFastTrackDemoSubmissionCandidate candidate;
      candidate.Reset();
      candidate.basket_id=basketId;
      candidate.execution_request_id=BuildExecutionRequestId(idempotencyKey);
      candidate.idempotency_key=idempotencyKey;
      candidate.symbol=details.symbol;
      candidate.direction=details.direction;
      candidate.volume=volume;
      candidate.entry_mode="MARKET";
      candidate.stop_loss=sltp.normalized_stop_loss;
      candidate.broker_take_profit=sltp.broker_take_profit;
      candidate.additional_tp_count=sltp.additional_tp_count;
      candidate.source=BRE_FT_DEMO_SUB_SRC_FILE_COMMON;
      candidate.route_label=bridgeInputs.route_label;
      candidate.target_label=bridgeInputs.target_label;
      candidate.requested_at_utc=nowUtc;
      candidate.magic_number=magicNumber;
      candidate.risk_estimate_usd=riskEstimate;
      candidate.status=BRE_FT_DEMO_SUB_AWAIT_AUTH;
      if(candidate.additional_tp_count>0)
         candidate.broker_tp_note="First TP used as broker target; additional targets are audit-only and not auto-managed.";

      registry.MarkProcessedIdempotencyKey(idempotencyKey);
      registry.RegisterActiveCandidate(candidate);

      outcome.status=BRE_FT_DEMO_SUB_CANDIDATE_CREATED;
      outcome.candidate_created=true;
      outcome.candidate=candidate;
      outcome.detail="Demo submission candidate created; awaiting explicit manual authorization";
      return outcome;
     }

   static void       PrintAudit(const SFastTrackDemoSubmissionBridgeOutcome &outcome)
     {
      Print("fasttrack_demo_submission_status=",CFastTrackDemoSubmissionTypeText::StatusToAuditCode(outcome.status));
      Print("fasttrack_demo_submission_block_reason=",outcome.block_reason);
      Print("fasttrack_demo_submission_detail=",outcome.detail);
      if(!outcome.candidate_created)
         return;

      const SFastTrackDemoSubmissionCandidate candidate=outcome.candidate;
      Print("fasttrack_demo_submission_candidate_status=",CFastTrackDemoSubmissionTypeText::StatusToAuditCode(candidate.status));
      Print("fasttrack_demo_submission_basket_id=",candidate.basket_id);
      Print("fasttrack_demo_submission_execution_request_id=",candidate.execution_request_id);
      Print("fasttrack_demo_submission_idempotency_key=",candidate.idempotency_key);
      Print("fasttrack_demo_submission_source=",CFastTrackDemoSubmissionTypeText::SourceToString(candidate.source));
      Print("fasttrack_demo_submission_target=",candidate.target_label);
      Print("fasttrack_demo_submission_route=",candidate.route_label);
      Print("fasttrack_demo_submission_symbol=",candidate.symbol);
      Print("fasttrack_demo_submission_side=",CTradeDirectionHelper::ToString(candidate.direction));
      Print("fasttrack_demo_submission_volume=",DoubleToString(candidate.volume,2));
      Print("fasttrack_demo_submission_stop_loss=",DoubleToString(candidate.stop_loss,5));
      Print("fasttrack_demo_submission_broker_take_profit=",DoubleToString(candidate.broker_take_profit,5));
      Print("fasttrack_demo_submission_additional_tp_count=",IntegerToString(candidate.additional_tp_count));
      Print("fasttrack_demo_submission_risk_estimate_usd=",DoubleToString(candidate.risk_estimate_usd,4));
      Print("fasttrack_demo_submission_magic=",IntegerToString((int)candidate.magic_number));
      Print("fasttrack_demo_submission_requested_at_utc=",IntegerToString((long)candidate.requested_at_utc));
      if(candidate.broker_tp_note!="")
         Print("fasttrack_demo_submission_broker_tp_note=",candidate.broker_tp_note);
      if(candidate.safe_error_code!="")
         Print("fasttrack_demo_submission_safe_error_code=",candidate.safe_error_code);
      if(candidate.safe_error_message!="")
         Print("fasttrack_demo_submission_safe_error_message=",candidate.safe_error_message);
     }
  };

#endif
