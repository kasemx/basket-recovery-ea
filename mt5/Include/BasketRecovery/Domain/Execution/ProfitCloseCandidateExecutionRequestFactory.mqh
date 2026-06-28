#ifndef BRE_DOMAIN_PROFIT_CLOSE_CANDIDATE_EXECUTION_REQUEST_FACTORY_MQH
#define BRE_DOMAIN_PROFIT_CLOSE_CANDIDATE_EXECUTION_REQUEST_FACTORY_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualProfitCloseCandidateEntry.mqh>
#include <BasketRecovery/Domain/Enums/TradeRole.mqh>

class CProfitCloseCandidateExecutionRequestFactory
  {
public:
   static CTradeExecutionRequest CreateCloseRequest(const CManualProfitCloseCandidateEntry &entry,
                                                    const datetime requestedAtUtc)
     {
      CTradeExecutionRequest request=CTradeExecutionRequest::Create(entry.ExecutionRequestId(),
                                                                    entry.IdempotencyKey(),
                                                                    entry.CandidateId(),
                                                                    entry.BasketId(),
                                                                    entry.BasketVersion(),
                                                                    entry.StrategyProfileHash(),
                                                                    entry.Symbol(),
                                                                    BRE_EXEC_INTENT_CLOSE_POSITION,
                                                                    entry.CloseDirection(),
                                                                    entry.PositionTicket(),
                                                                    entry.ProposedCloseVolume(),
                                                                    0.0,
                                                                    0.0,
                                                                    0.0,
                                                                    requestedAtUtc,
                                                                    CCommandId(""),
                                                                    CTradeRoleHelper::ToString(BRE_TRADE_ROLE_PROFIT_LEVEL_CLOSE));
      request.Seal();
      return request;
     }
  };

#endif
