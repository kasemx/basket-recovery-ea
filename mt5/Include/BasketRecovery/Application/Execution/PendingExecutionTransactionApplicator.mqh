#ifndef BRE_APP_PENDING_EXECUTION_TRANSACTION_APPLICATOR_MQH
#define BRE_APP_PENDING_EXECUTION_TRANSACTION_APPLICATOR_MQH

#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionTransitionRules.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionCorrelationContext.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionType.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionResultCode.mqh>

class CPendingExecutionTransactionApplicator
  {
public:
   static ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE Apply(CPendingExecutionEntry &entry,
                                                       const CTradeTransactionCorrelationContext &context,
                                                       ENUM_BRE_TRADE_EXECUTION_STATUS &proposedStatus)
     {
      proposedStatus=entry.Status();

      if(CPendingExecutionTransitionRules::AllowsLateTransaction(entry.Status()))
        {
         return ApplyReconciliation(entry,context,proposedStatus);
        }

      switch(context.TransactionType())
        {
         case BRE_TRADE_TX_TYPE_ORDER_ADD:
         case BRE_TRADE_TX_TYPE_REQUEST:
            proposedStatus=BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED;
            break;
         case BRE_TRADE_TX_TYPE_DEAL_ADD:
            entry.AccumulateFill(context.Volume());
            if(entry.RequestedVolume()>0.0 && entry.FilledVolume()+0.0000001>=entry.RequestedVolume())
               proposedStatus=BRE_TRADE_EXEC_STATUS_FILLED;
            else
               proposedStatus=BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED;
            break;
         case BRE_TRADE_TX_TYPE_ORDER_DELETE:
            proposedStatus=BRE_TRADE_EXEC_STATUS_REJECTED;
            break;
         default:
            return BRE_TRADE_TX_RESULT_OUT_OF_ORDER;
        }

      if(!CPendingExecutionTransitionRules::CanTransition(entry.Status(),proposedStatus))
         return BRE_TRADE_TX_RESULT_OUT_OF_ORDER;

      if(context.OrderId()>0 && entry.BrokerCorrelation().BrokerOrderId()==0)
        {
         CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
         broker.SetBrokerOrderId(context.OrderId());
         entry.SetBrokerCorrelation(broker);
        }
      if(context.DealId()>0)
        {
         CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
         broker.SetBrokerDealId(context.DealId());
         entry.SetBrokerCorrelation(broker);
        }
      if(context.PositionId()>0)
        {
         CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
         broker.SetPositionTicket(context.PositionId());
         entry.SetBrokerCorrelation(broker);
        }

      entry.SetStatus(proposedStatus);
      entry.SetLastTransactionKey(context.TransactionKey());
      entry.IncrementSeenTransactionCount();
      return BRE_TRADE_TX_RESULT_ACCEPTED;
     }

private:
   static ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE ApplyReconciliation(CPendingExecutionEntry &entry,
                                                                     const CTradeTransactionCorrelationContext &context,
                                                                     ENUM_BRE_TRADE_EXECUTION_STATUS &proposedStatus)
     {
      if(context.TransactionType()==BRE_TRADE_TX_TYPE_DEAL_ADD)
        {
         entry.AccumulateFill(context.Volume());
         if(entry.RequestedVolume()>0.0 && entry.FilledVolume()+0.0000001>=entry.RequestedVolume())
            proposedStatus=BRE_TRADE_EXEC_STATUS_FILLED;
         else if(entry.FilledVolume()>0.0)
            proposedStatus=BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED;
         else
            proposedStatus=BRE_TRADE_EXEC_STATUS_UNKNOWN;
        }
      else if(context.TransactionType()==BRE_TRADE_TX_TYPE_ORDER_DELETE)
        {
         proposedStatus=BRE_TRADE_EXEC_STATUS_REJECTED;
        }
      else
        {
         return BRE_TRADE_TX_RESULT_OUT_OF_ORDER;
        }

      if(!CPendingExecutionTransitionRules::CanTransition(entry.Status(),proposedStatus))
         return BRE_TRADE_TX_RESULT_OUT_OF_ORDER;

      entry.SetStatus(proposedStatus);
      entry.SetLastTransactionKey(context.TransactionKey());
      entry.IncrementSeenTransactionCount();
      entry.SetCorrelationState(BRE_PENDING_CORRELATION_RECONCILED);
      return BRE_TRADE_TX_RESULT_RECONCILED;
     }
  };

#endif
