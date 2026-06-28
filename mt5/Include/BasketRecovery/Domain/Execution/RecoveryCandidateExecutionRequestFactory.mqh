#ifndef BRE_DOMAIN_RECOVERY_CANDIDATE_EXECUTION_REQUEST_FACTORY_MQH
#define BRE_DOMAIN_RECOVERY_CANDIDATE_EXECUTION_REQUEST_FACTORY_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualRecoveryCandidateEntry.mqh>

class CRecoveryCandidateExecutionRequestFactory
  {
public:
   static CTradeExecutionRequest CreateOpenRecoveryRequest(const CManualRecoveryCandidateEntry &entry,
                                                             const datetime requestedAtUtc)
     {
      CTradeExecutionRequest request=CTradeExecutionRequest::Create(entry.ExecutionRequestId(),
                                                                    entry.IdempotencyKey(),
                                                                    entry.CandidateId(),
                                                                    entry.BasketId(),
                                                                    entry.BasketVersion(),
                                                                    entry.StrategyProfileHash(),
                                                                    entry.Symbol(),
                                                                    BRE_EXEC_INTENT_OPEN_POSITION,
                                                                    entry.Direction(),
                                                                    0,
                                                                    entry.ProposedVolume(),
                                                                    entry.ExecutablePrice(),
                                                                    entry.BasketStopLoss(),
                                                                    0.0,
                                                                    requestedAtUtc,
                                                                    CCommandId(""),
                                                                    "manual-recovery-candidate");
      request.Seal();
      return request;
     }
  };

#endif
