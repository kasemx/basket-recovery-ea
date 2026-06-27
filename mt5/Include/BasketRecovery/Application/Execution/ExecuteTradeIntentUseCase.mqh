#ifndef BRE_APP_EXECUTE_TRADE_INTENT_USE_CASE_MQH
#define BRE_APP_EXECUTE_TRADE_INTENT_USE_CASE_MQH

#include <BasketRecovery/Application/Execution/Ports/ITradeExecutor.mqh>
#include <BasketRecovery/Application/Execution/Ports/IExecutionJournal.mqh>
#include <BasketRecovery/Application/Execution/Ports/IExecutionRequestRepository.mqh>
#include <BasketRecovery/Application/Execution/ExecutionRequestFactory.mqh>
#include <BasketRecovery/Application/Execution/ExecutionRequestValidator.mqh>
#include <BasketRecovery/Application/Execution/ExecutionResultMapper.mqh>
#include <BasketRecovery/Application/Commands/StrategyCommandBase.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Domain/Basket/BasketRuntimeGuard.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionLifecycleRules.mqh>
#include <BasketRecovery/Domain/Events/ExecutionDomainEvent.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CExecuteTradeIntentUseCase
  {
private:
   IBasketRepository            *m_basketRepository;
   ITradeExecutor               *m_executor;
   IExecutionJournal            *m_journal;
   IExecutionRequestRepository  *m_repository;
   IClock                       *m_clock;

   void              AppendTransition(CTradeExecutionReceipt &receipt,
                                      const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus,
                                      const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus,
                                      const string detail) const
     {
      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : TimeCurrent();
      receipt.AppendTransition(CExecutionStatusTransition::Create(fromStatus,toStatus,nowUtc,detail));
      receipt.SetCurrentStatus(toStatus);
      if(m_journal!=NULL)
         m_journal.AppendTransition(receipt.Request().ExecutionRequestId(),
                                  CExecutionStatusTransition::Create(fromStatus,toStatus,nowUtc,detail));
     }

   CResult<CExecutionDomainEvent> BuildRejectionEvent(const CTradeExecutionRequest &request,
                                                      const CTradeExecutionResult &result,
                                                      const datetime occurredAtUtc) const
     {
      CTradeExecutionReceipt receipt;
      receipt.SetRequest(request);
      receipt.SetCurrentStatus(result.Status());
      receipt.SetResult(result);
      if(m_repository!=NULL)
         m_repository.Save(receipt);
      if(m_journal!=NULL)
         m_journal.RecordReceipt(receipt);
      return CResult<CExecutionDomainEvent>::Ok(CExecutionResultMapper::ToDomainEvent(receipt,occurredAtUtc));
     }

public:
                     CExecuteTradeIntentUseCase(IBasketRepository *basketRepository,
                                                  ITradeExecutor *executor,
                                                  IExecutionJournal *journal,
                                                  IExecutionRequestRepository *repository,
                                                  IClock *clock)
     {
      m_basketRepository=basketRepository;
      m_executor=executor;
      m_journal=journal;
      m_repository=repository;
      m_clock=clock;
     }

   CResult<CExecutionDomainEvent> Execute(const CStrategyCommandBase &command,
                                          const string executionRequestId,
                                          const string symbol,
                                          const ENUM_BRE_TRADE_DIRECTION direction,
                                          const ulong ticket,
                                          const double requestedVolume,
                                          const double requestedPrice,
                                          const double requestedStopLoss,
                                          const double requestedTakeProfit,
                                          const string reason)
     {
      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : TimeCurrent();

      if(m_repository!=NULL)
        {
         CResult<CTradeExecutionReceipt> duplicate=m_repository.FindByIdempotencyKey(command.IdempotencyKey());
         if(duplicate.IsOk())
           {
            CTradeExecutionReceipt existing;
            duplicate.TryGetValue(existing);
            existing.SetDuplicateReplay(true);
            return CResult<CExecutionDomainEvent>::Ok(CExecutionResultMapper::ToDomainEvent(existing,nowUtc));
           }
        }

      if(m_basketRepository==NULL)
         return CResult<CExecutionDomainEvent>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Basket repository is not configured");

      CResult<CBasketAggregate> loaded=m_basketRepository.Load(command.BasketId());
      if(loaded.IsFail())
         return CResult<CExecutionDomainEvent>::Fail(loaded.ErrorCode(),loaded.ErrorMessage());

      CBasketAggregate basket;
      loaded.TryGetValue(basket);

      if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
        {
         CTradeExecutionResult rejected=CTradeExecutionResult::Rejected(BRE_EXEC_FAIL_BASKET_NOT_ACTIVE,
                                                                        "Basket lifecycle is not ACTIVE");
         CTradeExecutionRequest stub=CTradeExecutionRequest::Create(executionRequestId,command.IdempotencyKey(),
                                                                    command.CorrelationKey(),command.BasketId(),
                                                                    command.ExpectedBasketVersion(),
                                                                    command.StrategyProfileHash(),symbol,
                                                                    BRE_EXEC_INTENT_OPEN_POSITION,direction,ticket,
                                                                    requestedVolume,requestedPrice,requestedStopLoss,
                                                                    requestedTakeProfit,nowUtc,command.Id(),reason);
         return BuildRejectionEvent(stub,rejected,nowUtc);
        }

      CVoidResult guardResult=CBasketRuntimeGuard::ValidateStrategyCommandContext(basket,
                                                                                   command.ExpectedBasketVersion(),
                                                                                   command.StrategyProfileHash());
      if(guardResult.IsFail())
        {
         ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON failReason=BRE_EXEC_FAIL_VALIDATION;
         if(guardResult.ErrorCode()==BRE_ERR_BASKET_VERSION_STALE)
            failReason=BRE_EXEC_FAIL_STALE_BASKET_VERSION;
         else if(guardResult.ErrorCode()==BRE_ERR_STRATEGY_HASH_MISMATCH)
            failReason=BRE_EXEC_FAIL_PROFILE_HASH_MISMATCH;

         CTradeExecutionResult rejected=CTradeExecutionResult::Rejected(failReason,guardResult.ErrorMessage());
         CTradeExecutionRequest stub=CTradeExecutionRequest::Create(executionRequestId,command.IdempotencyKey(),
                                                                    command.CorrelationKey(),command.BasketId(),
                                                                    command.ExpectedBasketVersion(),
                                                                    command.StrategyProfileHash(),symbol,
                                                                    BRE_EXEC_INTENT_OPEN_POSITION,direction,ticket,
                                                                    requestedVolume,requestedPrice,requestedStopLoss,
                                                                    requestedTakeProfit,nowUtc,command.Id(),reason);
         return BuildRejectionEvent(stub,rejected,nowUtc);
        }

      CResult<CTradeExecutionRequest> built=CExecutionRequestFactory::FromStrategyCommand(command,executionRequestId,
                                                                                          symbol,direction,ticket,
                                                                                          requestedVolume,requestedPrice,
                                                                                          requestedStopLoss,requestedTakeProfit,
                                                                                          nowUtc,reason);
      if(built.IsFail())
         return CResult<CExecutionDomainEvent>::Fail(built.ErrorCode(),built.ErrorMessage());

      CTradeExecutionRequest request;
      built.TryGetValue(request);

      CResult<CTradeExecutionResult> validation=CExecutionRequestValidator::ValidateForDispatch(request);
      if(validation.IsFail())
         return CResult<CExecutionDomainEvent>::Fail(validation.ErrorCode(),validation.ErrorMessage());
      CTradeExecutionResult validationValue;
      validation.TryGetValue(validationValue);
      if(validationValue.Status()==BRE_TRADE_EXEC_STATUS_REJECTED)
         return BuildRejectionEvent(request,validationValue,nowUtc);

      CTradeExecutionReceipt receipt;
      receipt.SetRequest(request);
      receipt.SetCurrentStatus(BRE_TRADE_EXEC_STATUS_CREATED);
      AppendTransition(receipt,BRE_TRADE_EXEC_STATUS_NONE,BRE_TRADE_EXEC_STATUS_CREATED,"created");
      AppendTransition(receipt,BRE_TRADE_EXEC_STATUS_CREATED,BRE_TRADE_EXEC_STATUS_QUEUED,"queued");
      if(m_repository!=NULL)
         m_repository.Save(receipt);
      if(m_journal!=NULL)
         m_journal.RecordReceipt(receipt);

      if(m_executor==NULL)
         return CResult<CExecutionDomainEvent>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Trade executor is not configured");

      if(!CExecutionLifecycleRules::CanSubmit(receipt.CurrentStatus()))
         return CResult<CExecutionDomainEvent>::Fail(BRE_ERR_EXEC_TERMINAL_STATE,"Execution request is not submittable");

      CResult<CTradeExecutionReceipt> executed=m_executor.Execute(request);
      if(executed.IsFail())
         return CResult<CExecutionDomainEvent>::Fail(executed.ErrorCode(),executed.ErrorMessage());

      CTradeExecutionReceipt finalReceipt;
      executed.TryGetValue(finalReceipt);
      if(m_repository!=NULL)
         m_repository.Save(finalReceipt);
      if(m_journal!=NULL)
         m_journal.RecordReceipt(finalReceipt);

      return CResult<CExecutionDomainEvent>::Ok(CExecutionResultMapper::ToDomainEvent(finalReceipt,nowUtc));
     }
  };

#endif
