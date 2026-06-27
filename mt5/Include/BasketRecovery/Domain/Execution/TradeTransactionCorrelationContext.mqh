#ifndef BRE_DOMAIN_TRADE_TRANSACTION_CORRELATION_CONTEXT_MQH
#define BRE_DOMAIN_TRADE_TRANSACTION_CORRELATION_CONTEXT_MQH

#include <BasketRecovery/Shared/DTOs/NormalizedTradeTransaction.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionType.mqh>

enum ENUM_BRE_CORRELATION_MATCH_STRATEGY
  {
   BRE_CORRELATION_MATCH_NONE=0,
   BRE_CORRELATION_MATCH_BROKER_ORDER_ID=1,
   BRE_CORRELATION_MATCH_BROKER_DEAL_ID=2,
   BRE_CORRELATION_MATCH_POSITION_TICKET=3,
   BRE_CORRELATION_MATCH_MAGIC_SYMBOL_COMMENT=4,
   BRE_CORRELATION_MATCH_REQUEST_FINGERPRINT=5
  };

inline string CorrelationMatchStrategyLabel(const ENUM_BRE_CORRELATION_MATCH_STRATEGY strategy)
  {
   switch(strategy)
     {
      case BRE_CORRELATION_MATCH_BROKER_ORDER_ID: return "broker_order_id";
      case BRE_CORRELATION_MATCH_BROKER_DEAL_ID: return "broker_deal_id";
      case BRE_CORRELATION_MATCH_POSITION_TICKET: return "position_ticket";
      case BRE_CORRELATION_MATCH_MAGIC_SYMBOL_COMMENT: return "magic_symbol_comment";
      case BRE_CORRELATION_MATCH_REQUEST_FINGERPRINT: return "request_fingerprint";
      default: return "none";
     }
  }

class CTradeTransactionCorrelationContext
  {
private:
   ENUM_BRE_TRADE_TRANSACTION_TYPE m_transactionType;
   ulong                           m_orderId;
   ulong                           m_dealId;
   ulong                           m_positionId;
   long                            m_magicNumber;
   string                          m_symbol;
   string                          m_comment;
   string                          m_correlationToken;
   double                          m_volume;
   double                          m_price;
   datetime                        m_occurredAtUtc;
   string                          m_transactionKey;

public:
                     CTradeTransactionCorrelationContext(void)
     {
      m_transactionType=BRE_TRADE_TX_TYPE_NONE;
      m_orderId=0;
      m_dealId=0;
      m_positionId=0;
      m_magicNumber=0;
      m_symbol="";
      m_comment="";
      m_correlationToken="";
      m_volume=0.0;
      m_price=0.0;
      m_occurredAtUtc=0;
      m_transactionKey="";
     }

   static CTradeTransactionCorrelationContext FromNormalized(const CNormalizedTradeTransaction &transaction,
                                                             const ENUM_BRE_TRADE_TRANSACTION_TYPE transactionType,
                                                             const long magicNumber=0)
     {
      CTradeTransactionCorrelationContext context;
      context.m_transactionType=transactionType;
      context.m_orderId=transaction.OrderId();
      context.m_dealId=transaction.DealId();
      context.m_positionId=transaction.PositionId();
      context.m_magicNumber=magicNumber;
      context.m_symbol=transaction.Symbol();
      context.m_comment=transaction.Comment();
      context.m_volume=transaction.Volume();
      context.m_price=transaction.Price();
      context.m_occurredAtUtc=transaction.OccurredAtUtc();
      context.m_correlationToken=ExtractCorrelationToken(transaction.Comment());
      context.m_transactionKey=BuildTransactionKey(context);
      return context;
     }

   static string     ExtractCorrelationToken(const string comment)
     {
      int execIndex=StringFind(comment,"EXEC:");
      if(execIndex>=0)
         return StringSubstr(comment,execIndex+5);
      int brIndex=StringFind(comment,"BR:");
      if(brIndex>=0)
        {
         string remainder=StringSubstr(comment,brIndex+3);
         int sep=StringFind(remainder,":");
         if(sep>=0)
            return StringSubstr(remainder,sep+1);
        }
      return comment;
     }

   static string     BuildTransactionKey(const CTradeTransactionCorrelationContext &context)
     {
      return StringFormat("%d|%I64u|%I64u|%I64u|%s",
                          (int)context.m_transactionType,
                          context.m_orderId,
                          context.m_dealId,
                          context.m_positionId,
                          context.m_symbol);
     }

   ENUM_BRE_TRADE_TRANSACTION_TYPE TransactionType(void) const { return m_transactionType; }
   ulong             OrderId(void) const { return m_orderId; }
   ulong             DealId(void) const { return m_dealId; }
   ulong             PositionId(void) const { return m_positionId; }
   long              MagicNumber(void) const { return m_magicNumber; }
   string            Symbol(void) const { return m_symbol; }
   string            Comment(void) const { return m_comment; }
   string            CorrelationToken(void) const { return m_correlationToken; }
   double            Volume(void) const { return m_volume; }
   double            Price(void) const { return m_price; }
   datetime          OccurredAtUtc(void) const { return m_occurredAtUtc; }
   string            TransactionKey(void) const { return m_transactionKey; }
  };

#endif
