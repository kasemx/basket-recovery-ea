#ifndef BASKET_RECOVERY_INFRASTRUCTURE_MT5_TRADE_TRANSACTION_NORMALIZER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_MT5_TRADE_TRANSACTION_NORMALIZER_MQH

#include <BasketRecovery/Shared/DTOs/NormalizedTradeTransaction.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>

class CMt5TradeTransactionNormalizer
  {
private:
   IClock *m_clock;

   CBasketId ExtractBasketIdFromComment(const string comment) const
     {
      int prefixIndex=StringFind(comment,"BR:");
      if(prefixIndex<0)
         return CBasketId("");

      string remainder=StringSubstr(comment,prefixIndex+3);
      int separatorIndex=StringFind(remainder,":");
      if(separatorIndex>=0)
         remainder=StringSubstr(remainder,0,separatorIndex);

      return CBasketId(remainder);
     }

   string ResolveComment(const MqlTradeTransaction &transaction) const
     {
      string comment="";
      if(transaction.order>0)
        {
         if(OrderSelect(transaction.order))
            comment=OrderGetString(ORDER_COMMENT);
        }

      if(comment=="" && transaction.deal>0)
        {
         if(HistoryDealSelect(transaction.deal))
            comment=HistoryDealGetString(transaction.deal,DEAL_COMMENT);
        }

      return comment;
     }

public:
                     CMt5TradeTransactionNormalizer(IClock *clock)
     {
      m_clock=clock;
     }

   CNormalizedTradeTransaction Normalize(const MqlTradeTransaction &transaction,
                                         const MqlTradeRequest &request,
                                         const MqlTradeResult &result) const
     {
      CNormalizedTradeTransaction normalized;
      normalized.SetTransactionType(transaction.type);
      normalized.SetOrderId(transaction.order);
      normalized.SetDealId(transaction.deal);
      normalized.SetPositionId(transaction.position);
      normalized.SetSymbol(transaction.symbol);
      normalized.SetVolume(transaction.volume);
      normalized.SetPrice(transaction.price);
      normalized.SetBid(transaction.price);
      normalized.SetAsk(transaction.price);

      string comment=ResolveComment(transaction);
      normalized.SetComment(comment);

      CBasketId basketId=ExtractBasketIdFromComment(comment);
      if(basketId.IsEmpty())
         basketId=CBasketId("__unassigned__");
      normalized.SetBasketId(basketId);

      if(m_clock!=NULL)
         normalized.SetOccurredAtUtc(m_clock.Now());
      else
         normalized.SetOccurredAtUtc(TimeCurrent());

      return normalized;
     }
  };

#endif
