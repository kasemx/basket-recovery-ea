#ifndef BASKET_RECOVERY_INFRASTRUCTURE_TRADE_REQUEST_BUILDER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_TRADE_REQUEST_BUILDER_MQH

#include <BasketRecovery/Application/DTOs/TradeContext.mqh>
#include <BasketRecovery/Application/TradeRequests/TradeRequest.mqh>
#include <BasketRecovery/Infrastructure/Execution/ExecutionPolicy.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Enums/TradeRole.mqh>

class CTradeRequestBuilder
  {
private:
   CExecutionPolicy m_policy;

   string            BuildComment(const CTradeContext &context,const CTradeRequest &request) const
     {
      if(request.Comment()!="")
         return request.Comment();
      return StringFormat("BRE|%s|%s|step=%d",
                          context.BasketId().Value(),
                          CTradeRoleHelper::ToString(context.TradeRole()),
                          context.RecoveryStep());
     }

   ENUM_ORDER_TYPE_FILLING ResolveFillingMode(const string symbol) const
     {
      int filling=(int)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
         return ORDER_FILLING_IOC;
      if((filling & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
         return ORDER_FILLING_FOK;
      return ORDER_FILLING_RETURN;
     }

public:
                     CTradeRequestBuilder(const CExecutionPolicy &policy)
     {
      m_policy=policy;
     }

   bool              BuildOpenRequest(const CTradeContext &context,
                                      const CTradeRequest &request,
                                      MqlTradeRequest &outRequest) const
     {
      ZeroMemory(outRequest);
      string symbol=request.Symbol();
      outRequest.action=TRADE_ACTION_DEAL;
      outRequest.symbol=symbol;
      outRequest.volume=request.Lot();
      outRequest.deviation=(ulong)m_policy.SlippagePoints();
      outRequest.magic=(ulong)context.Magic();
      outRequest.comment=BuildComment(context,request);
      outRequest.type_filling=ResolveFillingMode(symbol);
      outRequest.type_time=ORDER_TIME_GTC;
      outRequest.expiration=0;

      if(request.Direction()==BRE_DIRECTION_BUY)
        {
         outRequest.type=ORDER_TYPE_BUY;
         outRequest.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
        }
      else
        {
         outRequest.type=ORDER_TYPE_SELL;
         outRequest.price=SymbolInfoDouble(symbol,SYMBOL_BID);
        }

      outRequest.sl=request.StopLoss();
      outRequest.tp=request.TakeProfit();
      return true;
     }

   bool              BuildModifyRequest(const CTradeContext &context,
                                          const ulong ticket,
                                          const string symbol,
                                          const double stopLoss,
                                          const double takeProfit,
                                          const CTradeRequest &request,
                                          MqlTradeRequest &outRequest) const
     {
      ZeroMemory(outRequest);
      outRequest.action=TRADE_ACTION_SLTP;
      outRequest.position=ticket;
      outRequest.symbol=symbol;
      outRequest.magic=(ulong)context.Magic();
      outRequest.comment=BuildComment(context,request);
      outRequest.sl=stopLoss;
      outRequest.tp=takeProfit;
      return true;
     }

   bool              BuildCloseRequest(const CTradeContext &context,
                                       const ulong ticket,
                                       const string symbol,
                                       const double volume,
                                       const ENUM_POSITION_TYPE positionType,
                                       const CTradeRequest &request,
                                       MqlTradeRequest &outRequest) const
     {
      ZeroMemory(outRequest);
      outRequest.action=TRADE_ACTION_DEAL;
      outRequest.position=ticket;
      outRequest.symbol=symbol;
      outRequest.volume=volume;
      outRequest.deviation=(ulong)m_policy.SlippagePoints();
      outRequest.magic=(ulong)context.Magic();
      outRequest.comment=BuildComment(context,request);
      outRequest.type_filling=ResolveFillingMode(symbol);
      outRequest.type_time=ORDER_TIME_GTC;
      outRequest.expiration=0;

      if(positionType==POSITION_TYPE_BUY)
        {
         outRequest.type=ORDER_TYPE_SELL;
         outRequest.price=SymbolInfoDouble(symbol,SYMBOL_BID);
        }
      else
        {
         outRequest.type=ORDER_TYPE_BUY;
         outRequest.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
        }
      return true;
     }

   bool              BuildCancelPendingRequest(const CTradeContext &context,
                                               const ulong orderTicket,
                                               const string symbol,
                                               const CTradeRequest &request,
                                               MqlTradeRequest &outRequest) const
     {
      ZeroMemory(outRequest);
      outRequest.action=TRADE_ACTION_REMOVE;
      outRequest.order=orderTicket;
      outRequest.symbol=symbol;
      outRequest.magic=(ulong)context.Magic();
      outRequest.comment=BuildComment(context,request);
      return true;
     }
  };

#endif
