#ifndef BRE_INF_MT5_TRADE_TRANSACTION_ADAPTER_MQH
#define BRE_INF_MT5_TRADE_TRANSACTION_ADAPTER_MQH

#include <BasketRecovery/Shared/DTOs/NormalizedTradeTransaction.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionType.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionCorrelationContext.mqh>

class CMt5TradeTransactionAdapter
  {
public:
   static ENUM_BRE_TRADE_TRANSACTION_TYPE MapMt5Type(const long mt5Type)
     {
      switch((ENUM_TRADE_TRANSACTION_TYPE)mt5Type)
        {
         case TRADE_TRANSACTION_ORDER_ADD: return BRE_TRADE_TX_TYPE_ORDER_ADD;
         case TRADE_TRANSACTION_ORDER_UPDATE: return BRE_TRADE_TX_TYPE_ORDER_UPDATE;
         case TRADE_TRANSACTION_ORDER_DELETE: return BRE_TRADE_TX_TYPE_ORDER_DELETE;
         case TRADE_TRANSACTION_DEAL_ADD: return BRE_TRADE_TX_TYPE_DEAL_ADD;
         case TRADE_TRANSACTION_DEAL_UPDATE: return BRE_TRADE_TX_TYPE_DEAL_UPDATE;
         case TRADE_TRANSACTION_HISTORY_ADD: return BRE_TRADE_TX_TYPE_HISTORY_ADD;
         case TRADE_TRANSACTION_REQUEST: return BRE_TRADE_TX_TYPE_REQUEST;
         case TRADE_TRANSACTION_POSITION: return BRE_TRADE_TX_TYPE_POSITION;
         default: return BRE_TRADE_TX_TYPE_OTHER;
        }
     }

   static CTradeTransactionCorrelationContext BuildContext(const CNormalizedTradeTransaction &transaction,
                                                           const long magicNumber)
     {
      ENUM_BRE_TRADE_TRANSACTION_TYPE domainType=MapMt5Type(transaction.TransactionType());
      return CTradeTransactionCorrelationContext::FromNormalized(transaction,domainType,magicNumber);
     }
  };

#endif
