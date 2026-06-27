#ifndef BRE_DOMAIN_TRADE_EXECUTION_RECEIPT_MQH
#define BRE_DOMAIN_TRADE_EXECUTION_RECEIPT_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionResult.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionStatusTransition.mqh>

class CTradeExecutionReceipt
  {
private:
   CTradeExecutionRequest          m_request;
   ENUM_BRE_TRADE_EXECUTION_STATUS m_currentStatus;
   CTradeExecutionResult           m_result;
   CExecutionStatusTransition      m_transitions[];
   int                             m_retryCount;
   bool                            m_isDuplicateReplay;

public:
                     CTradeExecutionReceipt(void)
     {
      m_currentStatus=BRE_TRADE_EXEC_STATUS_NONE;
      m_retryCount=0;
      m_isDuplicateReplay=false;
     }

   CTradeExecutionRequest          Request(void) const { return m_request; }
   ENUM_BRE_TRADE_EXECUTION_STATUS CurrentStatus(void) const { return m_currentStatus; }
   CTradeExecutionResult           Result(void) const { return m_result; }
   int                             RetryCount(void) const { return m_retryCount; }
   bool                            IsDuplicateReplay(void) const { return m_isDuplicateReplay; }

   int                             TransitionCount(void) const { return ArraySize(m_transitions); }

   bool                            TryGetTransition(const int index,CExecutionStatusTransition &outTransition) const
     {
      if(index<0 || index>=ArraySize(m_transitions))
         return false;
      outTransition=m_transitions[index];
      return true;
     }

   void              SetRequest(const CTradeExecutionRequest &value) { m_request=value; }
   void              SetCurrentStatus(const ENUM_BRE_TRADE_EXECUTION_STATUS value) { m_currentStatus=value; }
   void              SetResult(const CTradeExecutionResult &value) { m_result=value; }
   void              SetRetryCount(const int value) { m_retryCount=value; }
   void              SetDuplicateReplay(const bool value) { m_isDuplicateReplay=value; }

   void              AppendTransition(const CExecutionStatusTransition &transition)
     {
      int count=ArraySize(m_transitions);
      ArrayResize(m_transitions,count+1);
      m_transitions[count]=transition;
     }
  };

#endif
