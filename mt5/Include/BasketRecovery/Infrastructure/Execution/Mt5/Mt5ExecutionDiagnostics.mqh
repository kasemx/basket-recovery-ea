#ifndef BRE_INF_MT5_EXECUTION_DIAGNOSTICS_MQH
#define BRE_INF_MT5_EXECUTION_DIAGNOSTICS_MQH

#include <BasketRecovery/Application/Ports/ILogger.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionResult.mqh>

class CMt5ExecutionDiagnostics
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
      m_logger.Info("EXECUTION","Mt5DryRun","",StringFormat("%s | %s",phase,detail));
      m_emittedLines++;
     }

public:
                     CMt5ExecutionDiagnostics(ILogger *logger,const bool enabled,const int maxLinesPerSession=50)
     {
      m_logger=logger;
      m_enabled=enabled;
      m_maxLinesPerSession=maxLinesPerSession;
      m_emittedLines=0;
     }

   void              OnTranslationSucceeded(const CTradeExecutionRequest &request,const string summary)
     {
      Emit("translation_ok",StringFormat("request=%s|intent=%s|%s",
                                         request.ExecutionRequestId(),
                                         TradeExecutionIntentLabel(request.IntentType()),
                                         summary));
     }

   void              OnTranslationFailed(const CTradeExecutionRequest &request,const string reason)
     {
      Emit("translation_fail",StringFormat("request=%s|reason=%s",request.ExecutionRequestId(),reason));
     }

   void              OnLocalValidationSucceeded(const CTradeExecutionRequest &request)
     {
      Emit("local_validation_ok",StringFormat("request=%s|local_validation_ok=true|no_ordersend=true",
                                              request.ExecutionRequestId()));
     }

   void              OnOrderCheckInvoked(const CTradeExecutionRequest &request)
     {
      Emit("ordercheck_invoked",StringFormat("request=%s|order_check_invoked=true|no_ordersend=true",
                                             request.ExecutionRequestId()));
     }

   void              OnOrderCheckResult(const CTradeExecutionRequest &request,
                                        const uint retcode,
                                        const string retcodeText,
                                        const bool accepted)
     {
      Emit(accepted ? "ordercheck_ok" : "ordercheck_fail",
           StringFormat("request=%s|retcode=%u|text=%s|order_check_invoked=true|no_ordersend=true",
                        request.ExecutionRequestId(),retcode,retcodeText));
     }

   void              OnRejection(const CTradeExecutionRequest &request,const string reason)
     {
      Emit("rejected",StringFormat("request=%s|reason=%s|order_check_invoked=false|no_ordersend=true",
                                   request.ExecutionRequestId(),reason));
     }

   void              OnExecutionDisabled(const string reason)
     {
      Emit("execution_disabled",reason);
     }
  };

#endif
