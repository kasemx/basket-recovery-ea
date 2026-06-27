#ifndef BRE_DOMAIN_TRADE_TRANSACTION_RESULT_CODE_MQH
#define BRE_DOMAIN_TRADE_TRANSACTION_RESULT_CODE_MQH

enum ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE
  {
   BRE_TRADE_TX_RESULT_NONE=0,
   BRE_TRADE_TX_RESULT_ACCEPTED=1,
   BRE_TRADE_TX_RESULT_REJECTED=2,
   BRE_TRADE_TX_RESULT_PARTIAL=3,
   BRE_TRADE_TX_RESULT_DUPLICATE=4,
   BRE_TRADE_TX_RESULT_OUT_OF_ORDER=5,
   BRE_TRADE_TX_RESULT_UNRELATED=6,
   BRE_TRADE_TX_RESULT_RECONCILED=7
  };

inline string TradeTransactionResultCodeLabel(const ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE code)
  {
   switch(code)
     {
      case BRE_TRADE_TX_RESULT_ACCEPTED: return "accepted";
      case BRE_TRADE_TX_RESULT_REJECTED: return "rejected";
      case BRE_TRADE_TX_RESULT_PARTIAL: return "partial";
      case BRE_TRADE_TX_RESULT_DUPLICATE: return "duplicate";
      case BRE_TRADE_TX_RESULT_OUT_OF_ORDER: return "out_of_order";
      case BRE_TRADE_TX_RESULT_UNRELATED: return "unrelated";
      case BRE_TRADE_TX_RESULT_RECONCILED: return "reconciled";
      default: return "none";
     }
  }

#endif
