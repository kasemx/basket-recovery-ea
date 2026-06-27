#ifndef BASKET_RECOVERY_INFRASTRUCTURE_EXECUTION_AUDIT_LOGGER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_EXECUTION_AUDIT_LOGGER_MQH

#include <BasketRecovery/Application/Ports/ILogger.mqh>
#include <BasketRecovery/Application/DTOs/TradeContext.mqh>
#include <BasketRecovery/Application/DTOs/ExecutionResult.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CExecutionAuditLogger
  {
private:
   ILogger *m_logger;

public:
                     CExecutionAuditLogger(ILogger *logger=NULL)
     {
      m_logger=logger;
     }

   void              LogRequest(const CTradeContext &context,
                                const string operation,
                                const MqlTradeRequest &request,
                                const int attemptIndex) const
     {
      if(m_logger==NULL)
         return;

      string details=StringFormat("op=%s attempt=%d idempotency=%s action=%d type=%d symbol=%s volume=%.2f price=%.5f sl=%.5f tp=%.5f magic=%I64u deviation=%I64u",
                                  operation,
                                  attemptIndex+1,
                                  context.IdempotencyKey(),
                                  request.action,
                                  request.type,
                                  request.symbol,
                                  request.volume,
                                  request.price,
                                  request.sl,
                                  request.tp,
                                  request.magic,
                                  request.deviation);
      m_logger.Info("EXECUTION","Request",context.BasketId().Value(),details);
     }

   void              LogResponse(const CTradeContext &context,
                                 const string operation,
                                 const CExecutionResult &result) const
     {
      if(m_logger==NULL)
         return;

      string details=StringFormat("op=%s success=%s status=%d retcode=%u ticket=%I64u order=%I64u price=%.5f volume=%.2f latency_ms=%d attempts=%d message=%s",
                                  operation,
                                  result.Success() ? "true" : "false",
                                  result.Status(),
                                  result.Retcode(),
                                  result.Ticket(),
                                  result.Order(),
                                  result.Price(),
                                  result.Volume(),
                                  result.LatencyMs(),
                                  result.AttemptCount(),
                                  result.Message());
      if(result.Success())
         m_logger.Info("EXECUTION","Response",context.BasketId().Value(),details);
      else
         m_logger.Warn("EXECUTION","Response",context.BasketId().Value(),details,result.ErrorCode());
     }

   void              LogRetry(const CTradeContext &context,
                            const string operation,
                            const int attemptIndex,
                            const uint retcode) const
     {
      if(m_logger==NULL)
         return;

      string details=StringFormat("op=%s attempt=%d retcode=%u action=retry",
                                  operation,
                                  attemptIndex+1,
                                  retcode);
      m_logger.Warn("EXECUTION","Retry",context.BasketId().Value(),details,BRE_ERR_EXEC_BROKER_ERROR);
     }

   void              LogRejection(const CTradeContext &context,
                                  const string operation,
                                  const string reason,
                                  const int errorCode) const
     {
      if(m_logger==NULL)
         return;

      string details=StringFormat("op=%s reason=%s",operation,reason);
      m_logger.Warn("EXECUTION","Rejected",context.BasketId().Value(),details,errorCode);
     }
  };

#endif
