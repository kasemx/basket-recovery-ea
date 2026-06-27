#ifndef BASKET_RECOVERY_APPLICATION_TRADE_REQUEST_MQH
#define BASKET_RECOVERY_APPLICATION_TRADE_REQUEST_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/TradeRequestType.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CTradeRequest
  {
private:
   CRequestId                    m_id;
   string                        m_idempotencyKey;
   ENUM_BRE_TRADE_REQUEST_TYPE   m_type;
   CBasketId                     m_basketId;
   ENUM_BRE_TRADE_REQUEST_STATUS m_status;
   string                        m_symbol;
   ENUM_BRE_TRADE_DIRECTION      m_direction;
   double                        m_lot;
   ulong                         m_ticket;
   double                        m_stopLoss;
   double                        m_takeProfit;
   string                        m_comment;
   datetime                      m_createdAt;
   int                           m_retryCount;
   int                           m_priority;

public:
                     CTradeRequest(void)
     {
      m_type=BRE_TRADE_REQUEST_NONE;
      m_status=BRE_TRADE_REQUEST_QUEUED;
      m_symbol="";
      m_direction=BRE_DIRECTION_NONE;
      m_lot=0.0;
      m_ticket=0;
      m_stopLoss=0.0;
      m_takeProfit=0.0;
      m_comment="";
      m_createdAt=0;
      m_retryCount=0;
      m_priority=10;
     }

   CRequestId                    Id(void) const { return m_id; }
   string                        IdempotencyKey(void) const { return m_idempotencyKey; }
   ENUM_BRE_TRADE_REQUEST_TYPE   Type(void) const { return m_type; }
   CBasketId                     BasketId(void) const { return m_basketId; }
   ENUM_BRE_TRADE_REQUEST_STATUS Status(void) const { return m_status; }
   string                        Symbol(void) const { return m_symbol; }
   ENUM_BRE_TRADE_DIRECTION      Direction(void) const { return m_direction; }
   double                        Lot(void) const { return m_lot; }
   ulong                         Ticket(void) const { return m_ticket; }
   double                        StopLoss(void) const { return m_stopLoss; }
   double                        TakeProfit(void) const { return m_takeProfit; }
   string                        Comment(void) const { return m_comment; }
   datetime                      CreatedAt(void) const { return m_createdAt; }
   int                           RetryCount(void) const { return m_retryCount; }
   int                           Priority(void) const { return m_priority; }

   void                          SetId(const CRequestId &value) { m_id=value; }
   void                          SetIdempotencyKey(const string value) { m_idempotencyKey=value; }
   void                          SetType(const ENUM_BRE_TRADE_REQUEST_TYPE value) { m_type=value; }
   void                          SetBasketId(const CBasketId &value) { m_basketId=value; }
   void                          SetStatus(const ENUM_BRE_TRADE_REQUEST_STATUS value) { m_status=value; }
   void                          SetSymbol(const string value) { m_symbol=value; }
   void                          SetDirection(const ENUM_BRE_TRADE_DIRECTION value) { m_direction=value; }
   void                          SetLot(const double value) { m_lot=value; }
   void                          SetTicket(const ulong value) { m_ticket=value; }
   void                          SetStopLoss(const double value) { m_stopLoss=value; }
   void                          SetTakeProfit(const double value) { m_takeProfit=value; }
   void                          SetComment(const string value) { m_comment=value; }
   void                          SetCreatedAt(const datetime value) { m_createdAt=value; }
   void                          SetRetryCount(const int value) { m_retryCount=value; }
   void                          SetPriority(const int value) { m_priority=value; }
  };

#endif
