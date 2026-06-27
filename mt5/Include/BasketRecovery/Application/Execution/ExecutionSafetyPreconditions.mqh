#ifndef BRE_APP_EXECUTION_SAFETY_PRECONDITIONS_MQH
#define BRE_APP_EXECUTION_SAFETY_PRECONDITIONS_MQH

#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionResult.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionFailureReason.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class CExecutionSafetyPreconditions
  {
public:
   static bool       IsLiveExecutionEnabled(void) { return false; }

   static CResult<CTradeExecutionResult> CheckLiveQuoteFreshness(const CTradeExecutionRequest &request,
                                                                 const int quoteAgeMs,
                                                                 const int maxQuoteAgeMs)
     {
      if(!IsLiveExecutionEnabled())
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_DISABLED,"Live execution preconditions are not activated");
      if(quoteAgeMs>maxQuoteAgeMs)
         return CResult<CTradeExecutionResult>::Ok(CTradeExecutionResult::Rejected(BRE_EXEC_FAIL_LIVE_QUOTE_STALE,
                                                                                   "Live quote is stale"));
      CTradeExecutionResult ok;
      return CResult<CTradeExecutionResult>::Ok(ok);
     }

   static CResult<CTradeExecutionResult> CheckMaxSpread(const CTradeExecutionRequest &request,
                                                        const int spreadPoints,
                                                        const int maxSpreadPoints)
     {
      if(!IsLiveExecutionEnabled())
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_DISABLED,"Live execution preconditions are not activated");
      if(spreadPoints>maxSpreadPoints)
         return CResult<CTradeExecutionResult>::Ok(CTradeExecutionResult::Rejected(BRE_EXEC_FAIL_MAX_SPREAD,
                                                                                   "Spread exceeds configured maximum"));
      CTradeExecutionResult ok;
      return CResult<CTradeExecutionResult>::Ok(ok);
     }

   static CResult<CTradeExecutionResult> CheckBasketLifecycleActive(const CBasketAggregate &basket)
     {
      if(!IsLiveExecutionEnabled())
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_DISABLED,"Live execution preconditions are not activated");
      if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
         return CResult<CTradeExecutionResult>::Ok(CTradeExecutionResult::Rejected(BRE_EXEC_FAIL_BASKET_NOT_ACTIVE,
                                                                                   "Basket lifecycle is not ACTIVE"));
      CTradeExecutionResult ok;
      return CResult<CTradeExecutionResult>::Ok(ok);
     }

   static CResult<CTradeExecutionResult> CheckAccountTradePermission(const bool tradeAllowed)
     {
      if(!IsLiveExecutionEnabled())
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_DISABLED,"Live execution preconditions are not activated");
      if(!tradeAllowed)
         return CResult<CTradeExecutionResult>::Ok(CTradeExecutionResult::Rejected(BRE_EXEC_FAIL_ACCOUNT_TRADE_DISABLED,
                                                                                   "Account trade permission denied"));
      CTradeExecutionResult ok;
      return CResult<CTradeExecutionResult>::Ok(ok);
     }

   static CResult<CTradeExecutionResult> CheckTicketBelongsToBasket(const CBasketAggregate &basket,
                                                                    const ulong ticket,
                                                                    const bool belongs)
     {
      if(!IsLiveExecutionEnabled())
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_DISABLED,"Live execution preconditions are not activated");
      if(ticket>0 && !belongs)
         return CResult<CTradeExecutionResult>::Ok(CTradeExecutionResult::Rejected(BRE_EXEC_FAIL_TICKET_NOT_IN_BASKET,
                                                                                   "Position ticket does not belong to basket"));
      CTradeExecutionResult ok;
      return CResult<CTradeExecutionResult>::Ok(ok);
     }

   static CResult<CTradeExecutionResult> CheckVolumeConstraints(const CTradeExecutionRequest &request,
                                                                const double minVolume,
                                                                const double maxVolume,
                                                                const double stepVolume)
     {
      if(!IsLiveExecutionEnabled())
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_DISABLED,"Live execution preconditions are not activated");
      if(request.RequestedVolume()<minVolume || request.RequestedVolume()>maxVolume)
         return CResult<CTradeExecutionResult>::Ok(CTradeExecutionResult::Rejected(BRE_EXEC_FAIL_VOLUME_CONSTRAINT,
                                                                                   "Requested volume violates symbol constraints"));
      if(stepVolume>0.0)
        {
         double steps=request.RequestedVolume()/stepVolume;
         if(MathAbs(steps-MathRound(steps))>0.0000001)
            return CResult<CTradeExecutionResult>::Ok(CTradeExecutionResult::Rejected(BRE_EXEC_FAIL_VOLUME_CONSTRAINT,
                                                                                      "Requested volume step is invalid"));
        }
      CTradeExecutionResult ok;
      return CResult<CTradeExecutionResult>::Ok(ok);
     }
  };

#endif
