#ifndef BASKET_RECOVERY_INFRASTRUCTURE_MOCK_TRADE_EXECUTOR_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_MOCK_TRADE_EXECUTOR_MQH

#include <BasketRecovery/Application/Ports/ITradeExecutor.mqh>
#include <BasketRecovery/Infrastructure/Execution/TradeResultMapper.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CMockTradeExecutor : public ITradeExecutor
  {
private:
   int    m_failCountBeforeSuccess;
   int    m_callCount;
   int    m_retryableFailuresRemaining;
   bool   m_simulateSuccess;
   ulong  m_nextTicket;

   CExecutionResult BuildSuccess(const string operation,const int attemptCount) const
     {
      CExecutionResult result;
      result.SetSuccess(true);
      result.SetStatus(BRE_EXECUTION_STATUS_SIMULATED);
      result.SetErrorCode(BRE_ERR_NONE);
      result.SetMessage(StringFormat("Mock %s success",operation));
      result.SetAttemptCount(attemptCount);
      result.SetTicket(m_nextTicket);
      result.SetPrice(1900.0);
      result.SetVolume(0.01);
      return result;
     }

   CExecutionResult BuildRetryableFailure(const int attemptCount) const
     {
      CExecutionResult result;
      result.SetSuccess(false);
      result.SetRetryable(true);
      result.SetStatus(BRE_EXECUTION_STATUS_REJECTED);
      result.SetErrorCode(BRE_ERR_EXEC_BROKER_ERROR);
      result.SetMessage("Mock retryable broker failure");
      result.SetRetcode(TRADE_RETCODE_REQUOTE);
      result.SetAttemptCount(attemptCount);
      return result;
     }

public:
                     CMockTradeExecutor(void)
     {
      m_failCountBeforeSuccess=0;
      m_callCount=0;
      m_retryableFailuresRemaining=0;
      m_simulateSuccess=true;
      m_nextTicket=100001;
     }

   void              SetFailCountBeforeSuccess(const int value) { m_failCountBeforeSuccess=value; }
   void              SetRetryableFailuresRemaining(const int value) { m_retryableFailuresRemaining=value; }
   void              SetSimulateSuccess(const bool value) { m_simulateSuccess=value; }
   void              SetNextTicket(const ulong value) { m_nextTicket=value; }
   int               CallCount(void) const { return m_callCount; }

   virtual CResult<CExecutionResult> OpenPosition(const CTradeContext &context,
                                                  const SOpenPositionParams &params,
                                                  const CTradeRequest &request)
     {
      m_callCount++;

      if(m_retryableFailuresRemaining>0)
        {
         m_retryableFailuresRemaining--;
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_BROKER_ERROR,"Mock retryable broker failure");
        }

      if(m_failCountBeforeSuccess>0)
        {
         m_failCountBeforeSuccess--;
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_REJECTED,"Mock open rejected");
        }

      if(!m_simulateSuccess)
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_REJECTED,"Mock open disabled");

      return CResult<CExecutionResult>::Ok(BuildSuccess("OpenPosition",1));
     }

   virtual CResult<CExecutionResult> ModifyPosition(const CTradeContext &context,
                                                      const SModifyPositionParams &params,
                                                      const CTradeRequest &request)
     {
      m_callCount++;
      if(!m_simulateSuccess)
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_REJECTED,"Mock modify rejected");
      return CResult<CExecutionResult>::Ok(BuildSuccess("ModifyPosition",1));
     }

   virtual CResult<CExecutionResult> ClosePosition(const CTradeContext &context,
                                                     const SClosePositionParams &params,
                                                     const CTradeRequest &request)
     {
      m_callCount++;
      if(!m_simulateSuccess)
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_REJECTED,"Mock close rejected");
      return CResult<CExecutionResult>::Ok(BuildSuccess("ClosePosition",1));
     }

   virtual CResult<CExecutionResult> ClosePartial(const CTradeContext &context,
                                                    const SClosePositionParams &params,
                                                    const CTradeRequest &request)
     {
      return ClosePosition(context,params,request);
     }

   virtual CResult<CExecutionResult> CloseBasket(const CTradeContext &context,
                                                   const ulong &tickets[],
                                                   const int ticketCount,
                                                   const CTradeRequest &request)
     {
      CExecutionResult lastResult;
      for(int i=0;i<ticketCount;i++)
        {
         SClosePositionParams params;
         params.ticket=tickets[i];
         CResult<CExecutionResult> closeResult=ClosePosition(context,params,request);
         if(closeResult.IsFail())
            return closeResult;
         closeResult.TryGetValue(lastResult);
        }
      return CResult<CExecutionResult>::Ok(lastResult);
     }

   virtual CResult<CExecutionResult> CancelPending(const CTradeContext &context,
                                                     const ulong orderTicket,
                                                     const CTradeRequest &request)
     {
      m_callCount++;
      if(!m_simulateSuccess)
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_REJECTED,"Mock cancel rejected");
      return CResult<CExecutionResult>::Ok(BuildSuccess("CancelPending",1));
     }
  };

#endif
