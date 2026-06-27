#ifndef BRE_APP_PENDING_EXECUTION_CORRELATION_MATCHER_MQH
#define BRE_APP_PENDING_EXECUTION_CORRELATION_MATCHER_MQH

#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionCorrelationContext.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionCorrelationState.mqh>

class CPendingExecutionCorrelationMatcher
  {
public:
   static bool       TryMatch(const CPendingExecutionEntry &entry,
                              const CTradeTransactionCorrelationContext &context,
                              ENUM_BRE_CORRELATION_MATCH_STRATEGY &strategyUsed)
     {
      strategyUsed=BRE_CORRELATION_MATCH_NONE;
      CBrokerRequestCorrelation broker=entry.BrokerCorrelation();

      if(context.OrderId()>0 && broker.HasBrokerOrderId() && context.OrderId()==broker.BrokerOrderId())
        {
         strategyUsed=BRE_CORRELATION_MATCH_BROKER_ORDER_ID;
         return true;
        }
      if(context.OrderId()>0 && broker.BrokerOrderId()==0 && context.OrderId()>0 &&
         entry.Status()==BRE_TRADE_EXEC_STATUS_SUBMITTED)
        {
         strategyUsed=BRE_CORRELATION_MATCH_BROKER_ORDER_ID;
         return true;
        }

      if(context.DealId()>0 && broker.HasBrokerDealId() && context.DealId()==broker.BrokerDealId())
        {
         strategyUsed=BRE_CORRELATION_MATCH_BROKER_DEAL_ID;
         return true;
        }
      if(context.DealId()>0 && broker.BrokerDealId()==0 && entry.Status()>=BRE_TRADE_EXEC_STATUS_SUBMITTED)
        {
         strategyUsed=BRE_CORRELATION_MATCH_BROKER_DEAL_ID;
         return true;
        }

      if(context.PositionId()>0 && broker.HasPositionTicket() && context.PositionId()==broker.PositionTicket())
        {
         strategyUsed=BRE_CORRELATION_MATCH_POSITION_TICKET;
         return true;
        }
      if(context.PositionId()>0 && broker.PositionTicket()==0 && entry.Symbol()==context.Symbol())
        {
         strategyUsed=BRE_CORRELATION_MATCH_POSITION_TICKET;
         return true;
        }

      if(broker.MagicNumber()!=0 &&
         context.MagicNumber()==broker.MagicNumber() &&
         entry.Symbol()==context.Symbol() &&
         broker.CommentToken()!="" &&
         StringFind(context.CorrelationToken(),broker.CommentToken())>=0)
        {
         strategyUsed=BRE_CORRELATION_MATCH_MAGIC_SYMBOL_COMMENT;
         return true;
        }

      if(broker.RequestFingerprint()!="" &&
         broker.RequestFingerprint()==BuildFingerprint(entry,context))
        {
         strategyUsed=BRE_CORRELATION_MATCH_REQUEST_FINGERPRINT;
         return true;
        }

      return false;
     }

   static bool       MatchesPriceOnly(const CPendingExecutionEntry &entry,
                                      const CTradeTransactionCorrelationContext &context)
     {
      if(context.Price()<=0.0)
         return false;
      return entry.Symbol()==context.Symbol() &&
             entry.RequestedVolume()==context.Volume() &&
             context.OrderId()==0 &&
             context.DealId()==0 &&
             context.PositionId()==0;
     }

   static string     BuildFingerprint(const CPendingExecutionEntry &entry,
                                      const CTradeTransactionCorrelationContext &context)
     {
      return StringFormat("%s|%s|%d|%.4f",
                          entry.ExecutionRequestId(),
                          entry.Symbol(),
                          (int)entry.IntentType(),
                          entry.RequestedVolume());
     }

   static ENUM_BRE_PENDING_EXECUTION_CORRELATION_STATE ToCorrelationState(const ENUM_BRE_CORRELATION_MATCH_STRATEGY strategy)
     {
      switch(strategy)
        {
         case BRE_CORRELATION_MATCH_BROKER_ORDER_ID: return BRE_PENDING_CORRELATION_ORDER_ID;
         case BRE_CORRELATION_MATCH_BROKER_DEAL_ID: return BRE_PENDING_CORRELATION_DEAL_ID;
         case BRE_CORRELATION_MATCH_POSITION_TICKET: return BRE_PENDING_CORRELATION_TICKET;
         case BRE_CORRELATION_MATCH_MAGIC_SYMBOL_COMMENT: return BRE_PENDING_CORRELATION_MAGIC_COMMENT;
         case BRE_CORRELATION_MATCH_REQUEST_FINGERPRINT: return BRE_PENDING_CORRELATION_FINGERPRINT;
         default: return BRE_PENDING_CORRELATION_UNMATCHED;
        }
     }
  };

#endif
