#ifndef BASKET_RECOVERY_SHARED_NORMALIZED_TRADE_TRANSACTION_MQH
#define BASKET_RECOVERY_SHARED_NORMALIZED_TRADE_TRANSACTION_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>

class CNormalizedTradeTransaction
  {
private:
   long        m_transactionType;
   ulong       m_orderId;
   ulong       m_dealId;
   ulong       m_positionId;
   string      m_symbol;
   double      m_volume;
   double      m_price;
   double      m_bid;
   double      m_ask;
   string      m_comment;
   CBasketId   m_basketId;
   datetime    m_occurredAtUtc;

public:
                     CNormalizedTradeTransaction(void)
     {
      m_transactionType=0;
      m_orderId=0;
      m_dealId=0;
      m_positionId=0;
      m_symbol="";
      m_volume=0.0;
      m_price=0.0;
      m_bid=0.0;
      m_ask=0.0;
      m_comment="";
      m_occurredAtUtc=0;
     }

   long              TransactionType(void) const { return m_transactionType; }
   ulong             OrderId(void) const { return m_orderId; }
   ulong             DealId(void) const { return m_dealId; }
   ulong             PositionId(void) const { return m_positionId; }
   string            Symbol(void) const { return m_symbol; }
   double            Volume(void) const { return m_volume; }
   double            Price(void) const { return m_price; }
   double            Bid(void) const { return m_bid; }
   double            Ask(void) const { return m_ask; }
   string            Comment(void) const { return m_comment; }
   CBasketId         BasketId(void) const { return m_basketId; }
   datetime          OccurredAtUtc(void) const { return m_occurredAtUtc; }

   void              SetTransactionType(const long value) { m_transactionType=value; }
   void              SetOrderId(const ulong value) { m_orderId=value; }
   void              SetDealId(const ulong value) { m_dealId=value; }
   void              SetPositionId(const ulong value) { m_positionId=value; }
   void              SetSymbol(const string value) { m_symbol=value; }
   void              SetVolume(const double value) { m_volume=value; }
   void              SetPrice(const double value) { m_price=value; }
   void              SetBid(const double value) { m_bid=value; }
   void              SetAsk(const double value) { m_ask=value; }
   void              SetComment(const string value) { m_comment=value; }
   void              SetBasketId(const CBasketId &value) { m_basketId=value; }
   void              SetOccurredAtUtc(const datetime value) { m_occurredAtUtc=value; }
  };

#endif
