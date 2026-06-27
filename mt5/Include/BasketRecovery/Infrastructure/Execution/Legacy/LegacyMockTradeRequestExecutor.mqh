#ifndef BRE_INF_LEGACY_MOCK_TRADE_REQUEST_EXECUTOR_MQH
#define BRE_INF_LEGACY_MOCK_TRADE_REQUEST_EXECUTOR_MQH

// Sprint 5 test double for per-operation broker port. Superseded by CSimulatedTradeExecutor.

#include <BasketRecovery/Infrastructure/Execution/Legacy/ITradeRequestExecutor.mqh>
#include <BasketRecovery/Infrastructure/Execution/TradeResultMapper.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CLegacyMockTradeRequestExecutor : public ITradeRequestExecutor
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

public:
                     CLegacyMockTradeRequestExecutor(void)
     {
      m_failCountBeforeSuccess=0;
      m_callCount=0;
      m_retryableFailuresRemaining=0;
      m_simulateSuccess=true;
      m_nextTicket=100001;
     }

   void              SetSimulateSuccess(const bool value) { m_simulateSuccess=value; }
   int               CallCount(void) const { return m_callCount; }

   virtual CResult<CExecutionResult> OpenPosition(const CTradeContext &context,
                                                  const SOpenPositionParams &params,
                                                  const CTradeRequest &request)
     {
      m_callCount++;
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
