#ifndef BASKET_RECOVERY_APPLICATION_ITRADE_EXECUTOR_MQH
#define BASKET_RECOVERY_APPLICATION_ITRADE_EXECUTOR_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Application/DTOs/TradeContext.mqh>
#include <BasketRecovery/Application/DTOs/ExecutionResult.mqh>
#include <BasketRecovery/Application/TradeRequests/TradeRequest.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

struct SOpenPositionParams
  {
   string                   symbol;
   ENUM_BRE_TRADE_DIRECTION direction;
   double                   volume;
   double                   price;
   double                   stopLoss;
   double                   takeProfit;
  };

struct SModifyPositionParams
  {
   ulong  ticket;
   double stopLoss;
   double takeProfit;
  };

struct SClosePositionParams
  {
   ulong  ticket;
   double volume;
   string symbol;
  };

class ITradeExecutor
  {
public:
   virtual          ~ITradeExecutor(void) {}
   virtual CResult<CExecutionResult> OpenPosition(const CTradeContext &context,
                                                  const SOpenPositionParams &params,
                                                  const CTradeRequest &request)=0;
   virtual CResult<CExecutionResult> ModifyPosition(const CTradeContext &context,
                                                      const SModifyPositionParams &params,
                                                      const CTradeRequest &request)=0;
   virtual CResult<CExecutionResult> ClosePosition(const CTradeContext &context,
                                                     const SClosePositionParams &params,
                                                     const CTradeRequest &request)=0;
   virtual CResult<CExecutionResult> ClosePartial(const CTradeContext &context,
                                                    const SClosePositionParams &params,
                                                    const CTradeRequest &request)=0;
   virtual CResult<CExecutionResult> CloseBasket(const CTradeContext &context,
                                                   const ulong &tickets[],
                                                   const int ticketCount,
                                                   const CTradeRequest &request)=0;
   virtual CResult<CExecutionResult> CancelPending(const CTradeContext &context,
                                                     const ulong orderTicket,
                                                     const CTradeRequest &request)=0;
  };

#endif
