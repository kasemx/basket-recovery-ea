#ifndef BRE_APP_MANUAL_PROFIT_CLOSE_SUBMIT_DIAGNOSTICS_MQH
#define BRE_APP_MANUAL_PROFIT_CLOSE_SUBMIT_DIAGNOSTICS_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualProfitCloseCandidateEntry.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Domain/Execution/ProfitCloseAuthorizationBinding.mqh>
#include <BasketRecovery/Domain/Execution/ProfitCloseCandidateCloseVolumeCalculator.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionQuery.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/BrokerMarketDealFillingModeResolver.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5LivePositionTicketAuthority.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ProfitLevelCloseCandidateStatus.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ProfitLevelCloseReason.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Strategy/Context/ProfitLevelEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevelCloseCandidate.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevel.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitDistributionPlan.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Application/Execution/BasketTicketOwnershipHydrator.mqh>
#include <BasketRecovery/Domain/Execution/BrokerExecutionCommentFactory.mqh>
#include <BasketRecovery/Domain/Execution/BrokerCommentCollisionDiagnostic.mqh>

#define BRE_PENDING_PRECHECK_BUILD_MARKER "S8C_TICKET_SCOPED_PENDING_PRECHECK_V2"
#define BRE_AUTH_VALIDATE_RUNTIME_BUILD_MARKER "S8C_AUTH_VALIDATE_EA_V2"
#define BRE_BROKER_COMMENT_SUBMIT_BUILD_MARKER "S8C_BROKER_COMMENT_FACTORY_V1"
#define BRE_PROFIT_CLOSE_TRANSACTION_CORRELATION_BUILD_MARKER "S8C_PROFIT_CLOSE_TX_CORRELATION_V1"

class CManualProfitCloseSubmitDiagnostics
  {
public:
   static void       PrintRestoreOutcome(const bool attempted,
                                         const bool restored,
                                         const string failureReason,
                                         const string candidateId,
                                         const string executionRequestId,
                                         const ulong ticket,
                                         const double closeVolume)
     {
      Print("profit_close_restore_attempted=",attempted?"true":"false");
      Print("profit_close_restore_result=",restored?"OK":(attempted?"FAIL":"SKIPPED"));
      Print("profit_close_restore_failure_reason=",failureReason);
      if(restored || attempted)
        {
         Print("profit_close_restored_candidate_id=",candidateId);
         Print("profit_close_restored_execution_request_id=",executionRequestId);
         Print("profit_close_restored_ticket=",IntegerToString((long)ticket));
         Print("profit_close_restored_close_volume=",DoubleToString(closeVolume,8));
        }
     }

   static void       PrintBrokerFillCompletion(const string brokerComment,
                                                 const string executionRequestId,
                                                 const string profitLevelId,
                                                 const bool profitLevelCompleted,
                                                 const string completionPath)
     {
      Print("profit_close_transaction_correlation=OK");
      Print("profit_close_transaction_comment=",brokerComment);
      Print("profit_close_transaction_matched_execution_request_id=",executionRequestId);
      Print("pending_execution_transition=FILLED");
      Print("pending_execution_id=",executionRequestId);
      Print("profit_level_close_confirmation=OK");
      Print("profit_level_id=",profitLevelId);
      Print("profit_level_completed=",profitLevelCompleted?"true":"false");
      Print("profit_level_current_state=",profitLevelCompleted?"COMPLETED":"PENDING");
      if(completionPath!="")
         Print("profit_close_reconcile_completion_path=",completionPath);
     }

   static void       PrintAuthBindingDiagnostics(const string plaintextToken,
                                                 const CManualProfitCloseCandidateEntry &entry,
                                                 const datetime nowUtc,
                                                 const string bindingFingerprintFromToken,
                                                 const datetime tokenExpiry,
                                                 const string expectedBindingHash,
                                                 const string bindingFailureField)
     {
      string expectedToken=CExecutionAuthorizationToken::IssuePlaintextToken(expectedBindingHash,tokenExpiry>0?tokenExpiry:nowUtc+60);
      bool prefixMatch=(bindingFingerprintFromToken!="" &&
                        StringFind(plaintextToken,"BRE-DEMO-"+bindingFingerprintFromToken+"-")==0);
      Print("auth_input_token=",CProfitCloseAuthorizationBinding::MaskToken(plaintextToken));
      Print("auth_expected_token=",CProfitCloseAuthorizationBinding::MaskToken(expectedToken));
      Print("auth_token_prefix_match=",prefixMatch?"true":"false");
      Print("auth_token_expiry=",IntegerToString((long)tokenExpiry));
      Print("auth_now=",IntegerToString((long)nowUtc));
      Print("auth_candidate_id_expected=",entry.CandidateId());
      Print("auth_candidate_id_actual=",entry.CandidateId());
      Print("auth_execution_request_id_expected=",entry.ExecutionRequestId());
      Print("auth_execution_request_id_actual=",entry.ExecutionRequestId());
      Print("auth_basket_id_expected=",entry.BasketId().Value());
      Print("auth_basket_id_actual=",entry.BasketId().Value());
      Print("auth_ticket_expected=",IntegerToString((long)entry.PositionTicket()));
      Print("auth_ticket_actual=",IntegerToString((long)entry.PositionTicket()));
      Print("auth_close_volume_expected=",CProfitCloseAuthorizationBinding::FormatCloseVolume(entry.ProposedCloseVolume()));
      Print("auth_close_volume_actual=",CProfitCloseAuthorizationBinding::FormatCloseVolume(entry.ProposedCloseVolume()));
      Print("auth_binding_hash_expected=",expectedBindingHash);
      Print("auth_binding_hash_actual=",bindingFingerprintFromToken);
      Print("auth_binding_failure_field=",bindingFailureField);
      string canonicalBinding=CProfitCloseAuthorizationBinding::BuildCanonicalPayload(entry.BasketId().Value(),
                                                                                        entry.CandidateId(),
                                                                                        entry.ExecutionRequestId(),
                                                                                        entry.PositionTicket(),
                                                                                        entry.ProposedCloseVolume());
      Print("auth_validate_runtime_build_marker=",BRE_AUTH_VALIDATE_RUNTIME_BUILD_MARKER);
      Print("auth_validate_binding_serializer_class=",CProfitCloseAuthorizationBinding::SerializerClassName());
      Print("auth_validate_canonical_binding_string=",canonicalBinding);
      Print("auth_validate_binding_hash=",expectedBindingHash);
      Print("auth_binding_build_marker=",CProfitCloseAuthorizationBinding::BuildMarker());
     }

   static bool       PreviewAuthorizationToken(const string plaintextToken,
                                               const CManualProfitCloseCandidateEntry &entry,
                                               const datetime nowUtc,
                                               string &failureReason)
     {
      failureReason="";
      if(plaintextToken=="")
        {
         failureReason="Authorization token missing";
         PrintAuthBindingDiagnostics(plaintextToken,entry,nowUtc,"","",0,"token_missing");
         return false;
        }
      string bindingFingerprint="";
      datetime tokenExpiry=0;
      if(!CExecutionAuthorizationToken::TryParsePlaintextToken(plaintextToken,bindingFingerprint,tokenExpiry))
        {
         failureReason="Authorization token format invalid";
         PrintAuthBindingDiagnostics(plaintextToken,entry,nowUtc,"","",0,"token_format_invalid");
         return false;
        }
      if(tokenExpiry<=nowUtc)
        {
         failureReason="Authorization token expired";
         string expectedBindingHash=CProfitCloseAuthorizationBinding::ComputeBindingHashFromEntry(entry);
         PrintAuthBindingDiagnostics(plaintextToken,entry,nowUtc,bindingFingerprint,tokenExpiry,expectedBindingHash,"token_expired");
         return false;
        }
      string expectedBindingHash=CProfitCloseAuthorizationBinding::ComputeBindingHashFromEntry(entry);
      string bindingFailureField="";
      if(!CProfitCloseAuthorizationBinding::ValidateTokenFingerprintFromEntry(bindingFingerprint,entry,bindingFailureField))
        {
         failureReason=bindingFailureField=="legacy_auth_binding_version" ?
                       "Legacy authorization binding version is not accepted" :
                       "Authorization token binding mismatch";
         PrintAuthBindingDiagnostics(plaintextToken,entry,nowUtc,bindingFingerprint,tokenExpiry,expectedBindingHash,bindingFailureField);
         return false;
        }
      PrintAuthBindingDiagnostics(plaintextToken,entry,nowUtc,bindingFingerprint,tokenExpiry,expectedBindingHash,bindingFailureField);
      return true;
     }

   static string     ResolveCloseTypeFillingLabel(const string symbol)
     {
      MqlTradeRequest request;
      ZeroMemory(request);
      request.symbol=symbol;
      request.action=TRADE_ACTION_DEAL;
      request.type=ORDER_TYPE_SELL;
      request.volume=0.01;
      string errorMessage="";
      if(!CBrokerMarketDealFillingModeResolver::TryApplyToMarketDealRequest(symbol,request,errorMessage))
         return "UNRESOLVED";
      return CBrokerMarketDealFillingModeResolver::FormatOrderTypeFilling(request.type_filling);
     }

   static void       PrintDirectionValidation(const ulong ticket,
                                              const string validationResult,
                                              const string failureBranch="")
     {
      string liveSymbol="";
      long livePositionType=0;
      ENUM_BRE_TRADE_DIRECTION livePositionDirection=BRE_DIRECTION_NONE;
      double liveVolume=0.0;
      string liveLookupFailure="";
      bool liveResolved=CMt5LivePositionTicketAuthority::TryResolveByTicket(ticket,
                                                                          liveSymbol,
                                                                          livePositionType,
                                                                          livePositionDirection,
                                                                          liveVolume,
                                                                          liveLookupFailure);

      Print("submit_live_position_type=",liveResolved ? CMt5LivePositionTicketAuthority::PositionTypeLabel(livePositionType) : "UNRESOLVED");
      Print("submit_live_position_direction=",liveResolved ? CTradeDirectionHelper::ToString(livePositionDirection) : "UNRESOLVED");
      ENUM_ORDER_TYPE closeOrderType=liveResolved ?
         CMt5LivePositionTicketAuthority::CloseOrderTypeForPositionType(livePositionType) :
         (ENUM_ORDER_TYPE)-1;
      Print("submit_close_order_type=",closeOrderType!=(ENUM_ORDER_TYPE)-1 ?
            CMt5LivePositionTicketAuthority::OrderTypeLabel(closeOrderType) : "UNRESOLVED");
      ENUM_BRE_TRADE_DIRECTION expectedClose=liveResolved ?
         CManualProfitCloseCandidateEntry::CloseDirectionForPosition(livePositionDirection) :
         BRE_DIRECTION_NONE;
      ENUM_ORDER_TYPE expectedOrderType=expectedClose==BRE_DIRECTION_SELL ? ORDER_TYPE_SELL :
                                        expectedClose==BRE_DIRECTION_BUY ? ORDER_TYPE_BUY :
                                        (ENUM_ORDER_TYPE)-1;
      Print("submit_expected_close_order_type=",expectedOrderType!=(ENUM_ORDER_TYPE)-1 ?
            CMt5LivePositionTicketAuthority::OrderTypeLabel(expectedOrderType) : "UNRESOLVED");
      Print("submit_direction_validation=",validationResult);
      if(failureBranch!="")
         Print("failure_branch=",failureBranch);
      if(!liveResolved && liveLookupFailure!="")
         Print("submit_live_position_lookup_failure=",liveLookupFailure);
     }

   static void       PrintRejectionTerminal(const bool submitRejectionTerminal,
                                            const bool restoredCandidatePreserved,
                                            const bool singleSubmitGuard)
     {
      Print("submit_rejection_terminal=",submitRejectionTerminal?"true":"false");
      Print("restored_candidate_preserved=",restoredCandidatePreserved?"true":"false");
      Print("single_submit_guard=",singleSubmitGuard?"true":"false");
     }

   static void       PrintBoundsValidationRejection(const CMt5AsyncSubmissionGateway *gateway,
                                                    const CPendingExecutionRegistry *pendingRegistry,
                                                    const string executionRequestId)
     {
      PrintRejectionTerminal(true,true,false);
      PrintPostSubmit(gateway,pendingRegistry,executionRequestId,false);
     }

   static void       PrintSubmitValidatorContext(const string methodName,
                                                 const CManualProfitCloseCandidateEntry &entry,
                                                 const int loopIndex=-1)
     {
      Print("method_name=",methodName);
      Print("array_name=openTickets");
      Print("loop_index=",IntegerToString(loopIndex));
      Print("candidate_id=",entry.CandidateId());
      Print("basket_id=",entry.BasketId().Value());
      Print("ticket=",IntegerToString((long)entry.PositionTicket()));
      Print("execution_request_id=",entry.ExecutionRequestId());
     }

   static void       PrintSubmitValidatorArrayBounds(const string arrayName,
                                                     const int arraySize,
                                                     const int requestedIndex,
                                                     const bool boundsCheckOk,
                                                     const string missingDataReason)
     {
      Print("submit_validator_array_name=",arrayName);
      Print("submit_validator_array_size=",IntegerToString(arraySize));
      Print("submit_validator_requested_index=",IntegerToString(requestedIndex));
      Print("submit_validator_bounds_check=",boundsCheckOk?"true":"false");
      Print("submit_validator_missing_data_reason=",missingDataReason);
     }

   static void       PrintBrokerCommentSubmitDiagnostics(const CBrokerCommentSubmitDiagnostics &diagnostics)
     {
      Print("broker_comment_factory_build_marker=",diagnostics.FactoryBuildMarker());
      Print("submit_execution_request_id=",diagnostics.ExecutionRequestId());
      Print("submit_target_ticket=",IntegerToString((long)diagnostics.TargetTicket()));
      Print("submit_requested_volume=",DoubleToString(diagnostics.RequestedVolume(),8));
      Print("submit_broker_comment=",diagnostics.BrokerComment());
      Print("submit_broker_comment_length=",IntegerToString(StringLen(diagnostics.BrokerComment())));
      Print("submit_broker_comment_fingerprint=",diagnostics.BrokerCommentFingerprint());
      Print("comment_collision_check_result=",diagnostics.CollisionCheckResult());
      CBrokerCommentCollisionDiagnostic collision=diagnostics.CollisionDiagnostic();
      Print("comment_collision_source=",collision.Source());
      Print("comment_collision_matched_comment=",collision.MatchedComment());
      Print("comment_collision_matched_request_id=",collision.MatchedRequestId());
      Print("comment_collision_matched_ticket=",collision.MatchedTicket()>0 ?
            IntegerToString((long)collision.MatchedTicket()) : "");
      Print("comment_collision_matched_status=",collision.MatchedStatus());
      Print("comment_collision_is_same_authorized_request=",collision.IsSameAuthorizedRequest()?"true":"false");
      Print("comment_collision_resolution_attempted=",diagnostics.ResolutionAttempted()?"true":"false");
      Print("comment_collision_final_comment=",diagnostics.FinalComment());
      Print("broker_comment_submit_build_marker=",BRE_BROKER_COMMENT_SUBMIT_BUILD_MARKER);
     }

   static void       PrintPreSubmit(const CManualProfitCloseCandidateEntry &entry,
                                    const double currentPositionVolume,
                                    const bool singleSubmitGuard,
                                    const bool pendingExecutionPrecheckOk,
                                    const string pendingExecutionPrecheckDetail,
                                    const string authorizationValidation,
                                    const string authorizationFailureReason,
                                    const string typeFillingLabel)
     {
      Print("submit_authorization_validation=",authorizationValidation);
      Print("submit_authorization_failure_reason=",authorizationFailureReason);
      Print("submit_candidate_id=",entry.CandidateId());
      Print("submit_execution_request_id=",entry.ExecutionRequestId());
      Print("submit_ticket=",IntegerToString((long)entry.PositionTicket()));
      Print("submit_current_position_volume=",DoubleToString(currentPositionVolume,8));
      Print("submit_requested_close_volume=",DoubleToString(entry.ProposedCloseVolume(),8));
      Print("submit_type_filling=",typeFillingLabel);
      Print("single_submit_guard=",singleSubmitGuard?"true":"false");
      Print("pending_execution_precheck=",pendingExecutionPrecheckOk?"OK":"FAIL");
      if(!pendingExecutionPrecheckOk)
         Print("pending_execution_precheck_detail=",pendingExecutionPrecheckDetail);
      PrintDirectionValidation(entry.PositionTicket(),"PENDING");
     }

   static void       PrintPostSubmit(const CMt5AsyncSubmissionGateway *gateway,
                                     const CPendingExecutionRegistry *pendingRegistry,
                                     const string executionRequestId,
                                     const bool brokerMutationAttempted)
     {
      uint retcode=0;
      ulong orderTicket=0;
      string orderResult="NONE";
      if(gateway!=NULL && gateway.WasBrokerInvoked())
        {
         retcode=gateway.LastAsyncResult().Retcode();
         orderTicket=gateway.LastAsyncResult().BrokerOrderId();
         orderResult=gateway.LastAsyncResult().Detail();
        }

      string pendingExecutionId="";
      if(pendingRegistry!=NULL)
        {
         CPendingExecutionEntry pendingEntry;
         if(pendingRegistry.TryGetByExecutionRequestId(executionRequestId,pendingEntry))
            pendingExecutionId=pendingEntry.ExecutionRequestId();
        }

      Print("submit_order_retcode=",IntegerToString((long)retcode));
      Print("submit_order_result=",orderResult);
      Print("submit_order_ticket=",IntegerToString((long)orderTicket));
      Print("submit_deal_ticket=0");
      Print("pending_execution_id=",pendingExecutionId);
      Print("submit_broker_mutation_attempted=",brokerMutationAttempted?"true":"false");
     }

   static void       PrintPendingPrecheckDiagnostics(const CPendingExecutionRegistry *pendingRegistry,
                                                     const CBasketId &basketId,
                                                     const string executionRequestId,
                                                     const ulong authorizedTicket,
                                                     const bool pendingRecordFound,
                                                     const CPendingExecutionEntry &pendingRecord,
                                                     const bool isSameAuthorizedRequest,
                                                     const bool isTerminal,
                                                     const string pendingBlockReason,
                                                     const int currentTicketUnresolvedCount=0,
                                                     const int foreignTicketUnresolvedCount=0)
     {
      Print("pending_precheck_basket_id=",basketId.Value());
      Print("pending_precheck_execution_request_id=",executionRequestId);
      Print("pending_precheck_record_found=",pendingRecordFound?"true":"false");
      Print("pending_precheck_record_status=",pendingRecordFound ? TradeExecutionStatusLabel(pendingRecord.Status()) : "NONE");
      Print("pending_precheck_record_created_at=",pendingRecordFound ? IntegerToString((long)pendingRecord.CreatedAtUtc()) : "0");
      datetime lastUpdated=pendingRecordFound ? pendingRecord.PreparedAtUtc() : 0;
      if(pendingRecordFound && pendingRecord.SubmittedAtUtc()>lastUpdated)
         lastUpdated=pendingRecord.SubmittedAtUtc();
      if(pendingRecordFound && lastUpdated<=0)
         lastUpdated=pendingRecord.CreatedAtUtc();
      Print("pending_precheck_record_last_updated_at=",pendingRecordFound ? IntegerToString((long)lastUpdated) : "0");
      Print("pending_precheck_record_ticket=",authorizedTicket>0 ? IntegerToString((long)authorizedTicket) : "NONE");
      Print("pending_precheck_record_requested_volume=",pendingRecordFound ?
            CProfitCloseAuthorizationBinding::FormatCloseVolume(pendingRecord.RequestedVolume()) : "NONE");
      Print("pending_precheck_record_is_same_authorized_request=",isSameAuthorizedRequest?"true":"false");
      Print("pending_precheck_record_is_terminal=",isTerminal?"true":"false");
      Print("pending_precheck_block_reason=",pendingBlockReason);
      Print("pending_precheck_runtime_build_marker=",BRE_PENDING_PRECHECK_BUILD_MARKER);
      Print("pending_precheck_current_ticket_unresolved_count=",IntegerToString(currentTicketUnresolvedCount));
      Print("pending_precheck_foreign_ticket_unresolved_count=",IntegerToString(foreignTicketUnresolvedCount));
     }

   static bool       PendingExecutionPrecheck(const CPendingExecutionRegistry *pendingRegistry,
                                              const CBasketId &basketId,
                                              const string executionRequestId,
                                              const ulong authorizedTicket,
                                              string &detail)
     {
      detail="";
      if(pendingRegistry==NULL)
        {
         CPendingExecutionEntry empty;
         PrintPendingPrecheckDiagnostics(pendingRegistry,basketId,executionRequestId,authorizedTicket,false,empty,false,false,"",0,0);
         return true;
        }

      ulong openTickets[];
      int openTicketCount=0;
      if(authorizedTicket>0)
        {
         openTicketCount=1;
         ArrayResize(openTickets,1);
         openTickets[0]=authorizedTicket;
        }

      int rawUnresolved=0;
      int currentTicketUnresolved=0;
      int foreignTicketUnresolved=0;
      CRecoveryPendingExecutionChecker::CountTicketScopedUnresolved(*pendingRegistry,
                                                                    basketId,
                                                                    openTickets,
                                                                    openTicketCount,
                                                                    NULL,
                                                                    rawUnresolved,
                                                                    currentTicketUnresolved,
                                                                    foreignTicketUnresolved);

      CPendingExecutionEntry sameRecord;
      bool pendingRecordFound=pendingRegistry.TryGetByExecutionRequestId(executionRequestId,sameRecord);
      bool isSameAuthorizedRequest=pendingRecordFound && sameRecord.ExecutionRequestId()==executionRequestId;
      bool isTerminal=pendingRecordFound && CPendingExecutionQuery::IsTerminalStatus(sameRecord.Status());
      bool hasOtherBlocking=CRecoveryPendingExecutionChecker::HasOtherBlockingUnresolvedForOpenTickets(*pendingRegistry,
                                                                                                       basketId,
                                                                                                       executionRequestId,
                                                                                                       openTickets,
                                                                                                       openTicketCount);

      if(hasOtherBlocking)
        {
         detail="Unresolved pending execution blocks current ticket";
         PrintPendingPrecheckDiagnostics(pendingRegistry,basketId,executionRequestId,authorizedTicket,pendingRecordFound,sameRecord,
                                         isSameAuthorizedRequest,isTerminal,detail,currentTicketUnresolved,foreignTicketUnresolved);
         return false;
        }

      if(pendingRecordFound &&
         (sameRecord.Status()==BRE_TRADE_EXEC_STATUS_SUBMITTED ||
          sameRecord.Status()==BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED))
        {
         detail="Execution request already submitted";
         PrintPendingPrecheckDiagnostics(pendingRegistry,basketId,executionRequestId,authorizedTicket,true,sameRecord,
                                         isSameAuthorizedRequest,isTerminal,detail,currentTicketUnresolved,foreignTicketUnresolved);
         return false;
        }

      PrintPendingPrecheckDiagnostics(pendingRegistry,basketId,executionRequestId,authorizedTicket,pendingRecordFound,sameRecord,
                                      isSameAuthorizedRequest,isTerminal,"",currentTicketUnresolved,foreignTicketUnresolved);
      return true;
     }

   static void       PrintReplanDueRejection(const CManualProfitCloseCandidateEntry &entry,
                                             const CBasketAggregate &basket,
                                             const CProfitLevelEvaluationContext &planContext,
                                             const CProfitLevelCloseCandidate &replanned,
                                             const bool hasSnapshot,
                                             const CPositionSnapshotEntry &snapshotPosition,
                                             const bool hasLive,
                                             const long livePositionType,
                                             const double liveVolume)
     {
      CStrategyProfile profile=planContext.Profile();
      CProfitDistributionPlan distributionPlan=profile.ProfitDistributionPlan();
      double requiredThresholdUsd=entry.TriggerValue();
      for(int i=0;i<distributionPlan.LevelCount();i++)
        {
         CProfitLevel level=distributionPlan.LevelAt(i);
         if(level.LevelId()==entry.ProfitLevelId())
           {
            requiredThresholdUsd=level.TriggerValue();
            break;
           }
        }

      CBasketProfitLevelProgress levelProgress;
      bool hasLevelProgress=basket.FindProfitLevelProgress(entry.ProfitLevelId(),levelProgress);
      double remainingClosePercent=0.0;
      for(int i=0;i<distributionPlan.LevelCount();i++)
        {
         CProfitLevel level=distributionPlan.LevelAt(i);
         if(level.LevelId()==entry.ProfitLevelId())
           {
            remainingClosePercent=level.ClosePercent();
            break;
           }
        }

      Print("submit_current_floating_profit_usd=",DoubleToString(planContext.FloatingProfitUsd(),4));
      Print("submit_required_profit_threshold_usd=",DoubleToString(requiredThresholdUsd,4));
      Print("submit_require_floating_profit_positive=",distributionPlan.RequireFloatingProfitPositive()?"true":"false");
      Print("submit_position_ticket=",IntegerToString((long)entry.PositionTicket()));
      Print("submit_position_type=",hasLive ? CMt5LivePositionTicketAuthority::PositionTypeLabel(livePositionType) : "SNAPSHOT_ONLY");
      Print("submit_position_volume=",DoubleToString(hasLive ? liveVolume : (hasSnapshot ? snapshotPosition.Volume() : 0.0),8));
      Print("submit_snapshot_position_count=",IntegerToString(planContext.PositionCount()));
      Print("submit_snapshot_ticket=",hasSnapshot ? IntegerToString((long)snapshotPosition.Ticket()) : "NONE");
      Print("submit_snapshot_direction=",hasSnapshot ? CTradeDirectionHelper::ToString(snapshotPosition.Direction()) : "NONE");
      Print("submit_snapshot_volume=",hasSnapshot ? DoubleToString(snapshotPosition.Volume(),8) : "NONE");
      Print("submit_basket_lifecycle=",CBasketLifecycleStateHelper::ToString(basket.LifecycleState()));
      Print("submit_max_risk_lockout=",basket.ModeFlags().MaxRiskLockout()?"true":"false");
      Print("submit_profit_level_id=",entry.ProfitLevelId());
      Print("submit_profit_level_completed=",hasLevelProgress && levelProgress.CloseCompleted()?"true":"false");
      Print("submit_profit_level_requested=",hasLevelProgress && levelProgress.CloseRequested()?"true":"false");
      Print("submit_profit_level_remaining_close_percent=",DoubleToString(remainingClosePercent,2));
      Print("submit_replanned_candidate_due=",replanned.IsDue()?"true":"false");
      Print("submit_replanned_candidate_status=",CProfitLevelCloseCandidateStatusText::ToString(replanned.Status()));
      Print("submit_replanned_candidate_reason=",CProfitLevelCloseReasonText::ToString(replanned.Reason()));
      Print("failure_branch=pre_submit_validation");
     }

   static void       PrintVolumeMismatchRejection(const CManualProfitCloseCandidateEntry &entry,
                                                  const CBasketAggregate &basket,
                                                  const CStrategyProfile &profile,
                                                  const double profitLevelRemainingClosePercent,
                                                  const double artifactCloseVolume,
                                                  const double replannedCloseVolume,
                                                  const double livePositionVolume,
                                                  const double expectedCloseVolume,
                                                  const double normalizedReplannedCloseVolume,
                                                  const CSymbolTradingConstraints &constraints,
                                                  const string volumeMismatchReason)
     {
      Print("artifact_close_volume=",CProfitCloseAuthorizationBinding::FormatCloseVolume(artifactCloseVolume));
      Print("candidate_close_volume=",CProfitCloseAuthorizationBinding::FormatCloseVolume(entry.ProposedCloseVolume()));
      Print("replanned_close_volume=",CProfitCloseAuthorizationBinding::FormatCloseVolume(replannedCloseVolume));
      Print("live_position_volume=",DoubleToString(livePositionVolume,8));
      Print("profit_level_remaining_close_percent=",DoubleToString(profitLevelRemainingClosePercent,2));
      Print("profit_level_remaining_close_volume=",CProfitCloseAuthorizationBinding::FormatCloseVolume(expectedCloseVolume));
      Print("position_volume_step=",DoubleToString(constraints.VolumeStep(),8));
      Print("position_volume_min=",DoubleToString(constraints.VolumeMin(),8));
      Print("normalized_replanned_close_volume=",CProfitCloseAuthorizationBinding::FormatCloseVolume(normalizedReplannedCloseVolume));
      Print("volume_rounding_mode=",CProfitCloseCandidateCloseVolumeCalculator::VolumeRoundingModeLabel());
      Print("volume_mismatch_reason=",volumeMismatchReason);
      Print("strategy_profile_hash=",basket.StrategyProfileHash());
      Print("basket_version=",IntegerToString(basket.Version()));
      Print("profit_close_volume_calc_build_marker=",CProfitCloseCandidateCloseVolumeCalculator::BuildMarker());
      Print("failure_branch=replanned_close_volume_changed");
     }

   static void       PrintTicketOwnershipValidation(const SBasketTicketOwnershipDiagnostics &diagnostics,
                                                    const CTradeExecutionRequest &request)
     {
      Print("submit_basket_id=",diagnostics.basket_id);
      Print("submit_candidate_ticket=",IntegerToString((long)diagnostics.candidate_ticket));
      Print("submit_live_ticket=",IntegerToString((long)diagnostics.live_ticket));
      Print("submit_basket_position_count=",IntegerToString(diagnostics.basket_position_count));
      Print("submit_basket_position_ticket_list=",diagnostics.basket_position_ticket_list);
      Print("submit_basket_position_state_list=",diagnostics.basket_position_state_list);
      Print("submit_ticket_ownership_result=",diagnostics.ownership_result);
      Print("submit_ticket_ownership_failure_reason=",diagnostics.ownership_failure_reason);
      Print("submit_restore_registry_basket_found=",diagnostics.restore_registry_basket_found?"true":"false");
      Print("submit_restore_registry_candidate_found=",diagnostics.restore_registry_candidate_found?"true":"false");
      Print("submit_reconcile_basket_id=",diagnostics.reconcile_basket_id);
      Print("submit_reconcile_position_ticket_list=",diagnostics.reconcile_position_ticket_list);
      if(diagnostics.ownership_result=="OK")
        {
         Print("submit_request_position=",IntegerToString((long)request.Ticket()));
         Print("submit_request_symbol=",request.Symbol());
         Print("submit_request_volume=",DoubleToString(request.RequestedVolume(),8));
        }
     }
  };

#endif
