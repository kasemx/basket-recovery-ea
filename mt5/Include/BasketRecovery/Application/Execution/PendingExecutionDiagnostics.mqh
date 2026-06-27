#ifndef BRE_APP_PENDING_EXECUTION_DIAGNOSTICS_MQH
#define BRE_APP_PENDING_EXECUTION_DIAGNOSTICS_MQH

#include <BasketRecovery/Application/Ports/ILogger.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionCorrelationContext.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionResultCode.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>

class CPendingExecutionDiagnostics
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
      m_logger.Info("EXECUTION","PendingTx","",StringFormat("%s | %s",phase,detail));
      m_emittedLines++;
     }

public:
                     CPendingExecutionDiagnostics(ILogger *logger=NULL,const bool enabled=false,const int maxLinesPerSession=64)
     {
      m_logger=logger;
      m_enabled=enabled;
      m_maxLinesPerSession=maxLinesPerSession;
      m_emittedLines=0;
     }

   int               EmittedLineCount(void) const { return m_emittedLines; }

   void              OnTransactionNormalized(const string transactionKey,const string txTypeLabel)
     {
      Emit("tx_normalized",StringFormat("key=%s|type=%s",transactionKey,txTypeLabel));
     }

   void              OnCorrelationMatch(const string executionRequestId,
                                        const ENUM_BRE_CORRELATION_MATCH_STRATEGY strategy)
     {
      Emit("correlation_match",StringFormat("request=%s|strategy=%s",
                                            executionRequestId,
                                            CorrelationMatchStrategyLabel(strategy)));
     }

   void              OnTransitionAccepted(const string executionRequestId,
                                          const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus,
                                          const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus)
     {
      Emit("transition_ok",StringFormat("request=%s|from=%s|to=%s",
                                        executionRequestId,
                                        TradeExecutionStatusLabel(fromStatus),
                                        TradeExecutionStatusLabel(toStatus)));
     }

   void              OnTransitionRejected(const string executionRequestId,const string reason)
     {
      Emit("transition_reject",StringFormat("request=%s|reason=%s",executionRequestId,reason));
     }

   void              OnDuplicateTransaction(const string executionRequestId,const string transactionKey)
     {
      Emit("duplicate_tx",StringFormat("request=%s|key=%s",executionRequestId,transactionKey));
     }

   void              OnOutOfOrderTransaction(const string executionRequestId,const string transactionKey)
     {
      Emit("out_of_order_tx",StringFormat("request=%s|key=%s",executionRequestId,transactionKey));
     }

   void              OnTimeoutDetected(const string executionRequestId)
     {
      Emit("timeout",StringFormat("request=%s|action=reconciling_not_retry",executionRequestId));
     }

   void              OnReconciliationRequested(const string executionRequestId,const string reason)
     {
      Emit("reconciliation_requested",StringFormat("request=%s|reason=%s",executionRequestId,reason));
     }

   void              OnUnresolvedUnknown(const string executionRequestId)
     {
      Emit("unresolved_unknown",StringFormat("request=%s|blocks_blind_resend=true",executionRequestId));
     }

   void              OnUnrelatedTransaction(const string transactionKey)
     {
      Emit("unrelated_tx",StringFormat("key=%s",transactionKey));
     }

   void              OnRouteResult(const string executionRequestId,const ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE code)
     {
      Emit("route_result",StringFormat("request=%s|result=%s",
                                       executionRequestId,
                                       TradeTransactionResultCodeLabel(code)));
     }
  };

#endif
