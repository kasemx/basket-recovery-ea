#ifndef BRE_APP_SUBMISSION_DIAGNOSTICS_MQH
#define BRE_APP_SUBMISSION_DIAGNOSTICS_MQH

#include <BasketRecovery/Application/Ports/ILogger.mqh>
#include <BasketRecovery/Domain/Execution/PreparedSubmissionFailureReason.mqh>
#include <BasketRecovery/Domain/Execution/SubmissionGatewayStatus.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>

class CSubmissionDiagnostics
  {
private:
   ILogger *m_logger;
   bool     m_enabled;
   int      m_maxLinesPerSession;
   int      m_emittedLines;

   void              Emit(const string phase,const string detail)
     {
      if(!m_enabled || m_logger==NULL || m_emittedLines>=m_maxLinesPerSession)
         return;
      m_logger.Info("EXECUTION","Submission","",StringFormat("%s | %s",phase,detail));
      m_emittedLines++;
     }

public:
                     CSubmissionDiagnostics(ILogger *logger=NULL,const bool enabled=false,const int maxLinesPerSession=64)
     {
      m_logger=logger;
      m_enabled=enabled;
      m_maxLinesPerSession=maxLinesPerSession;
      m_emittedLines=0;
     }

   int               EmittedLineCount(void) const { return m_emittedLines; }

   void              OnSubmissionAttempted(const string executionRequestId)
     {
      Emit("submit_attempt",StringFormat("request=%s",executionRequestId));
     }

   void              OnEnvelopeValidation(const string executionRequestId,const bool passed,const string detail)
     {
      Emit("envelope_validation",StringFormat("request=%s|passed=%s|detail=%s",
                                              executionRequestId,
                                              passed ? "true" : "false",
                                              detail));
     }

   void              OnSimulatedSubmitAccepted(const string executionRequestId,const ulong brokerRequestId)
     {
      Emit("sim_submit_accepted",StringFormat("request=%s|brokerRequestId=%I64u",
                                              executionRequestId,
                                              brokerRequestId));
     }

   void              OnSimulatedSubmitRejected(const string executionRequestId,const string detail)
     {
      Emit("sim_submit_rejected",StringFormat("request=%s|detail=%s",executionRequestId,detail));
     }

   void              OnBrokerPlaceholderAssigned(const string executionRequestId,const ulong brokerRequestId)
     {
      Emit("broker_placeholder",StringFormat("request=%s|brokerRequestId=%I64u",
                                             executionRequestId,
                                             brokerRequestId));
     }

   void              OnAcknowledgementCorrelated(const string executionRequestId,const ulong brokerOrderId)
     {
      Emit("ack_correlated",StringFormat("request=%s|brokerOrderId=%I64u",executionRequestId,brokerOrderId));
     }

   void              OnStateTransition(const string executionRequestId,
                                       const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus,
                                       const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus,
                                       const bool accepted)
     {
      Emit("state_transition",StringFormat("request=%s|from=%s|to=%s|accepted=%s",
                                           executionRequestId,
                                           TradeExecutionStatusLabel(fromStatus),
                                           TradeExecutionStatusLabel(toStatus),
                                           accepted ? "true" : "false"));
     }

   void              OnDuplicateSubmissionBlocked(const string executionRequestId,const string idempotencyKey)
     {
      Emit("duplicate_blocked",StringFormat("request=%s|idempotency=%s",executionRequestId,idempotencyKey));
     }

   void              OnTimeoutReconciliationHandoff(const string executionRequestId)
     {
      Emit("timeout_reconciliation",StringFormat("request=%s|retry=false",executionRequestId));
     }

   void              OnGatewayResult(const string executionRequestId,const ENUM_BRE_SUBMISSION_GATEWAY_STATUS status)
     {
      Emit("gateway_result",StringFormat("request=%s|status=%s",
                                         executionRequestId,
                                         SubmissionGatewayStatusLabel(status)));
     }

   void              OnValidationFailure(const string executionRequestId,
                                         const ENUM_BRE_PREPARED_SUBMISSION_FAILURE_REASON reason)
     {
      Emit("validation_fail",StringFormat("request=%s|reason=%s",
                                          executionRequestId,
                                          PreparedSubmissionFailureReasonLabel(reason)));
     }
  };

#endif
