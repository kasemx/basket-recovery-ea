#ifndef BRE_DOMAIN_TRADE_EXECUTION_REQUEST_MQH
#define BRE_DOMAIN_TRADE_EXECUTION_REQUEST_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CTradeExecutionRequest
  {
private:
   string                        m_executionRequestId;
   string                        m_idempotencyKey;
   string                        m_correlationId;
   CBasketId                     m_basketId;
   long                          m_expectedBasketVersion;
   string                        m_strategyProfileHash;
   string                        m_symbol;
   ENUM_BRE_TRADE_EXECUTION_INTENT m_intentType;
   ENUM_BRE_TRADE_DIRECTION      m_direction;
   ulong                         m_ticket;
   double                        m_requestedVolume;
   double                        m_requestedPrice;
   double                        m_requestedStopLoss;
   double                        m_requestedTakeProfit;
   datetime                      m_requestedAtUtc;
   CCommandId                    m_sourceCommandId;
   string                        m_reason;
   bool                          m_isSealed;

public:
                     CTradeExecutionRequest(void)
     {
      m_executionRequestId="";
      m_idempotencyKey="";
      m_correlationId="";
      m_expectedBasketVersion=-1;
      m_strategyProfileHash="";
      m_symbol="";
      m_intentType=BRE_EXEC_INTENT_NONE;
      m_direction=BRE_DIRECTION_NONE;
      m_ticket=0;
      m_requestedVolume=0.0;
      m_requestedPrice=0.0;
      m_requestedStopLoss=0.0;
      m_requestedTakeProfit=0.0;
      m_requestedAtUtc=0;
      m_reason="";
      m_isSealed=false;
     }

public:
   string                        ExecutionRequestId(void) const { return m_executionRequestId; }
   string                        IdempotencyKey(void) const { return m_idempotencyKey; }
   string                        CorrelationId(void) const { return m_correlationId; }
   CBasketId                     BasketId(void) const { return m_basketId; }
   long                          ExpectedBasketVersion(void) const { return m_expectedBasketVersion; }
   string                        StrategyProfileHash(void) const { return m_strategyProfileHash; }
   string                        Symbol(void) const { return m_symbol; }
   ENUM_BRE_TRADE_EXECUTION_INTENT IntentType(void) const { return m_intentType; }
   ENUM_BRE_TRADE_DIRECTION      Direction(void) const { return m_direction; }
   ulong                         Ticket(void) const { return m_ticket; }
   double                        RequestedVolume(void) const { return m_requestedVolume; }
   double                        RequestedPrice(void) const { return m_requestedPrice; }
   double                        RequestedStopLoss(void) const { return m_requestedStopLoss; }
   double                        RequestedTakeProfit(void) const { return m_requestedTakeProfit; }
   datetime                      RequestedAtUtc(void) const { return m_requestedAtUtc; }
   CCommandId                    SourceCommandId(void) const { return m_sourceCommandId; }
   string                        Reason(void) const { return m_reason; }
   bool                          IsSealed(void) const { return m_isSealed; }

   void                          Seal(void) { m_isSealed=true; }

   static CTradeExecutionRequest Create(const string executionRequestId,
                                        const string idempotencyKey,
                                        const string correlationId,
                                        const CBasketId &basketId,
                                        const long expectedBasketVersion,
                                        const string strategyProfileHash,
                                        const string symbol,
                                        const ENUM_BRE_TRADE_EXECUTION_INTENT intentType,
                                        const ENUM_BRE_TRADE_DIRECTION direction,
                                        const ulong ticket,
                                        const double requestedVolume,
                                        const double requestedPrice,
                                        const double requestedStopLoss,
                                        const double requestedTakeProfit,
                                        const datetime requestedAtUtc,
                                        const CCommandId &sourceCommandId,
                                        const string reason)
     {
      CTradeExecutionRequest request;
      request.m_executionRequestId=executionRequestId;
      request.m_idempotencyKey=idempotencyKey;
      request.m_correlationId=correlationId;
      request.m_basketId=basketId;
      request.m_expectedBasketVersion=expectedBasketVersion;
      request.m_strategyProfileHash=strategyProfileHash;
      request.m_symbol=symbol;
      request.m_intentType=intentType;
      request.m_direction=direction;
      request.m_ticket=ticket;
      request.m_requestedVolume=requestedVolume;
      request.m_requestedPrice=requestedPrice;
      request.m_requestedStopLoss=requestedStopLoss;
      request.m_requestedTakeProfit=requestedTakeProfit;
      request.m_requestedAtUtc=requestedAtUtc;
      request.m_sourceCommandId=sourceCommandId;
      request.m_reason=reason;
      request.m_isSealed=true;
      return request;
     }
  };

#endif
