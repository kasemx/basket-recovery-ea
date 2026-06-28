#ifndef BRE_INF_MT5_ASYNC_SUBMISSION_DIAGNOSTICS_MQH
#define BRE_INF_MT5_ASYNC_SUBMISSION_DIAGNOSTICS_MQH

#include <BasketRecovery/Application/Ports/ILogger.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionEnvelope.mqh>
#include <BasketRecovery/Domain/Execution/LiveSubmissionSafetyRejectionReason.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionResult.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Shared/Utils/Crc32.mqh>

class CMt5AsyncSubmissionDiagnostics
  {
private:
   ILogger          *m_logger;
   bool              m_enabled;
   int               m_maxLines;
   int               m_lineCount;

   void              Emit(const string message)
     {
      if(!m_enabled || m_logger==NULL || m_lineCount>=m_maxLines)
         return;
      m_logger.Info("EXEC_SUBMIT",message,"","");
      m_lineCount++;
     }

public:
                     CMt5AsyncSubmissionDiagnostics(ILogger *logger=NULL,const bool enabled=false,const int maxLines=64)
     {
      m_logger=logger;
      m_enabled=enabled;
      m_maxLines=maxLines;
      m_lineCount=0;
     }

   void              OnSafetyGateBlocked(const string executionRequestId,
                                         const ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON reason,
                                         const string detail)
     {
      Emit(StringFormat("safety_blocked|request=%s|reason=%s|detail=%s",
                        executionRequestId,
                        LiveSubmissionSafetyRejectionReasonLabel(reason),
                        detail));
     }

   void              OnOrderSendAsyncAttempt(const CBrokerSubmissionEnvelope &envelope,
                                             const bool accepted,
                                             const CMt5AsyncSubmissionResult &asyncResult)
     {
      string brokerComment=envelope.BrokerComment();
      string commentHash=CCrc32::ToHex(CCrc32::Compute(brokerComment));
      Emit(StringFormat("ordersend_async|request=%s|basket=%s|symbol=%s|intent=%s|volume=%.4f|accepted=%s|retcode=%u|last_error=%d|submitted=%s|comment_hash=%s",
                        envelope.ExecutionRequestId(),
                        envelope.BasketId().Value(),
                        envelope.Symbol(),
                        TradeExecutionIntentLabel(envelope.IntentType()),
                        envelope.RequestedVolume(),
                        accepted?"true":"false",
                        asyncResult.Retcode(),
                        asyncResult.LastError(),
                        accepted?"true":"false",
                        commentHash));
     }

   void              Clear(void) { m_lineCount=0; }
  };

#endif
