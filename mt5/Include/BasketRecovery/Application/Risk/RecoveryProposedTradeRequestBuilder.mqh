#ifndef BRE_APP_RECOVERY_PROPOSED_TRADE_REQUEST_BUILDER_MQH
#define BRE_APP_RECOVERY_PROPOSED_TRADE_REQUEST_BUILDER_MQH

#include <BasketRecovery/Domain/Strategy/Decisions/OpenRecoveryPositionDecision.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>

class CRecoveryProposedTradeRequestBuilder
  {
public:
   static CTradeExecutionRequest Build(const CBasketAggregate &basket,
                                       const COpenRecoveryPositionDecision &decision,
                                       const string correlationKey,
                                       const datetime requestedAtUtc)
     {
      CSignalDetails details=basket.SignalDetails();
      return CTradeExecutionRequest::Create("recovery-gate:"+decision.IdempotencyKey(),
                                            decision.IdempotencyKey(),
                                            correlationKey,
                                            basket.Id(),
                                            basket.Version(),
                                            basket.StrategyProfileHash(),
                                            basket.Symbol(),
                                            BRE_EXEC_INTENT_OPEN_POSITION,
                                            basket.Direction(),
                                            0,
                                            decision.Lot(),
                                            decision.ExpectedEntryPrice(),
                                            details.StopLoss().Value(),
                                            0.0,
                                            requestedAtUtc,
                                            CCommandId(""),
                                            "recovery-risk-gate");
     }
  };

#endif
