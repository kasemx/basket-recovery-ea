#ifndef BRE_INF_MT5_TRADE_REQUEST_TRANSLATOR_MQH
#define BRE_INF_MT5_TRADE_REQUEST_TRANSLATOR_MQH

#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5RequestTranslationResult.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5BasketPositionLookup.mqh>
#include <BasketRecovery/Infrastructure/Execution/ExecutionPolicy.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CMt5TradeRequestTranslator
  {
private:
   CExecutionPolicy m_policy;

   ENUM_ORDER_TYPE_FILLING ResolveFillingMode(const string symbol) const
     {
      int filling=(int)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
         return ORDER_FILLING_IOC;
      if((filling & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
         return ORDER_FILLING_FOK;
      return ORDER_FILLING_RETURN;
     }

   string            BuildSummary(const MqlTradeRequest &request,const ENUM_BRE_TRADE_EXECUTION_INTENT intent) const
     {
      return StringFormat("intent=%s|action=%d|symbol=%s|type=%d|volume=%.4f|price=%.5f|sl=%.5f|tp=%.5f|position=%I64u|order=%I64u",
                          TradeExecutionIntentLabel(intent),
                          request.action,
                          request.symbol,
                          request.type,
                          request.volume,
                          request.price,
                          request.sl,
                          request.tp,
                          request.position,
                          request.order);
     }

   ENUM_POSITION_TYPE ResolvePositionType(const CPositionSnapshotEntry &entry) const
     {
      return (entry.Direction()==BRE_DIRECTION_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
     }

   bool              BuildOpen(const CTradeExecutionRequest &request,
                               const long magic,
                               const double ask,
                               const double bid,
                               CMt5RequestTranslationResult &outResult) const
     {
      if(request.Direction()==BRE_DIRECTION_NONE)
        {
         outResult.SetFailure(BRE_EXEC_FAIL_VALIDATION,"Direction is required for open");
         return false;
        }
      if(request.RequestedVolume()<=0.0)
        {
         outResult.SetFailure(BRE_EXEC_FAIL_VALIDATION,"Requested volume is required for open");
         return false;
        }

      MqlTradeRequest mt5Request;
      ZeroMemory(mt5Request);
      mt5Request.action=TRADE_ACTION_DEAL;
      mt5Request.symbol=request.Symbol();
      mt5Request.volume=request.RequestedVolume();
      mt5Request.deviation=(ulong)m_policy.SlippagePoints();
      mt5Request.magic=(ulong)magic;
      mt5Request.comment=StringFormat("BRE|dry-run|%s",request.ExecutionRequestId());
      mt5Request.type_filling=ResolveFillingMode(request.Symbol());
      mt5Request.type_time=ORDER_TIME_GTC;

      if(request.Direction()==BRE_DIRECTION_BUY)
        {
         mt5Request.type=ORDER_TYPE_BUY;
         mt5Request.price=(request.RequestedPrice()>0.0) ? request.RequestedPrice() : ask;
        }
      else
        {
         mt5Request.type=ORDER_TYPE_SELL;
         mt5Request.price=(request.RequestedPrice()>0.0) ? request.RequestedPrice() : bid;
        }

      mt5Request.sl=request.RequestedStopLoss();
      mt5Request.tp=request.RequestedTakeProfit();
      outResult.SetSuccess(mt5Request,BuildSummary(mt5Request,request.IntentType()));
      return true;
     }

   bool              BuildCloseOrReduce(const CTradeExecutionRequest &request,
                                        const long magic,
                                        const CPositionSnapshotEntry &entry,
                                        const double ask,
                                        const double bid,
                                        const bool isReduce,
                                        CMt5RequestTranslationResult &outResult) const
     {
      if(request.Ticket()==0)
        {
         outResult.SetFailure(BRE_EXEC_FAIL_VALIDATION,"Ticket is required for close/reduce");
         return false;
        }

      double volume=isReduce ? request.RequestedVolume() : entry.Volume();
      if(volume<=0.0)
        {
         outResult.SetFailure(BRE_EXEC_FAIL_VALIDATION,"Close/reduce volume must be positive");
         return false;
        }

      ENUM_POSITION_TYPE positionType=ResolvePositionType(entry);
      MqlTradeRequest mt5Request;
      ZeroMemory(mt5Request);
      mt5Request.action=TRADE_ACTION_DEAL;
      mt5Request.position=request.Ticket();
      mt5Request.symbol=request.Symbol();
      mt5Request.volume=volume;
      mt5Request.deviation=(ulong)m_policy.SlippagePoints();
      mt5Request.magic=(ulong)magic;
      mt5Request.comment=StringFormat("BRE|dry-run|%s",request.ExecutionRequestId());
      mt5Request.type_filling=ResolveFillingMode(request.Symbol());
      mt5Request.type_time=ORDER_TIME_GTC;

      if(positionType==POSITION_TYPE_BUY)
        {
         mt5Request.type=ORDER_TYPE_SELL;
         mt5Request.price=(request.RequestedPrice()>0.0) ? request.RequestedPrice() : bid;
        }
      else
        {
         mt5Request.type=ORDER_TYPE_BUY;
         mt5Request.price=(request.RequestedPrice()>0.0) ? request.RequestedPrice() : ask;
        }

      outResult.SetSuccess(mt5Request,BuildSummary(mt5Request,request.IntentType()));
      return true;
     }

   bool              BuildModifySltp(const CTradeExecutionRequest &request,
                                   const long magic,
                                   const CPositionSnapshotEntry &entry,
                                   const bool modifySl,
                                   CMt5RequestTranslationResult &outResult) const
     {
      if(request.Ticket()==0)
        {
         outResult.SetFailure(BRE_EXEC_FAIL_VALIDATION,"Ticket is required for modify");
         return false;
        }

      double sl=modifySl ? request.RequestedStopLoss() : entry.StopLoss();
      double tp=modifySl ? entry.TakeProfit() : request.RequestedTakeProfit();
      if(modifySl && request.RequestedStopLoss()<=0.0)
        {
         outResult.SetFailure(BRE_EXEC_FAIL_VALIDATION,"Requested stop loss is required");
         return false;
        }
      if(!modifySl && request.RequestedTakeProfit()<=0.0)
        {
         outResult.SetFailure(BRE_EXEC_FAIL_VALIDATION,"Requested take profit is required");
         return false;
        }

      MqlTradeRequest mt5Request;
      ZeroMemory(mt5Request);
      mt5Request.action=TRADE_ACTION_SLTP;
      mt5Request.position=request.Ticket();
      mt5Request.symbol=request.Symbol();
      mt5Request.magic=(ulong)magic;
      mt5Request.comment=StringFormat("BRE|dry-run|%s",request.ExecutionRequestId());
      mt5Request.sl=sl;
      mt5Request.tp=tp;
      outResult.SetSuccess(mt5Request,BuildSummary(mt5Request,request.IntentType()));
      return true;
     }

   bool              BuildCancelPending(const CTradeExecutionRequest &request,
                                        const long magic,
                                        CMt5RequestTranslationResult &outResult) const
     {
      if(request.Ticket()==0)
        {
         outResult.SetFailure(BRE_EXEC_FAIL_VALIDATION,"Ticket is required for cancel pending");
         return false;
        }

      MqlTradeRequest mt5Request;
      ZeroMemory(mt5Request);
      mt5Request.action=TRADE_ACTION_REMOVE;
      mt5Request.order=request.Ticket();
      mt5Request.symbol=request.Symbol();
      mt5Request.magic=(ulong)magic;
      mt5Request.comment=StringFormat("BRE|dry-run|%s",request.ExecutionRequestId());
      outResult.SetSuccess(mt5Request,BuildSummary(mt5Request,request.IntentType()));
      return true;
     }

public:
                     CMt5TradeRequestTranslator(void)
     {
      m_policy=CExecutionPolicy();
     }

                     CMt5TradeRequestTranslator(const CExecutionPolicy &policy)
     {
      m_policy=policy;
     }

   bool              TryTranslate(const CTradeExecutionRequest &request,
                                  const CBasketAggregate &basket,
                                  const long magic,
                                  const double bid,
                                  const double ask,
                                  CMt5RequestTranslationResult &outResult) const
     {
      switch(request.IntentType())
        {
         case BRE_EXEC_INTENT_OPEN_POSITION:
            return BuildOpen(request,magic,ask,bid,outResult);
         case BRE_EXEC_INTENT_CLOSE_POSITION:
         case BRE_EXEC_INTENT_REDUCE_POSITION:
           {
            CPositionSnapshotEntry entry;
            if(!CMt5BasketPositionLookup::TryFindEntry(basket,request.Ticket(),entry))
              {
               outResult.SetFailure(BRE_EXEC_FAIL_TICKET_NOT_IN_BASKET,"Ticket not found in basket snapshot");
               return false;
              }
            return BuildCloseOrReduce(request,magic,entry,ask,bid,
                                      request.IntentType()==BRE_EXEC_INTENT_REDUCE_POSITION,outResult);
           }
         case BRE_EXEC_INTENT_MODIFY_STOP_LOSS:
           {
            CPositionSnapshotEntry entry;
            if(!CMt5BasketPositionLookup::TryFindEntry(basket,request.Ticket(),entry))
              {
               outResult.SetFailure(BRE_EXEC_FAIL_TICKET_NOT_IN_BASKET,"Ticket not found in basket snapshot");
               return false;
              }
            return BuildModifySltp(request,magic,entry,true,outResult);
           }
         case BRE_EXEC_INTENT_MODIFY_TAKE_PROFIT:
           {
            CPositionSnapshotEntry entry;
            if(!CMt5BasketPositionLookup::TryFindEntry(basket,request.Ticket(),entry))
              {
               outResult.SetFailure(BRE_EXEC_FAIL_TICKET_NOT_IN_BASKET,"Ticket not found in basket snapshot");
               return false;
              }
            return BuildModifySltp(request,magic,entry,false,outResult);
           }
         case BRE_EXEC_INTENT_CANCEL_PENDING_REQUEST:
            return BuildCancelPending(request,magic,outResult);
         default:
            outResult.SetFailure(BRE_EXEC_FAIL_UNSUPPORTED_INTENT,"Unsupported or ambiguous execution intent");
            return false;
        }
     }
  };

#endif
