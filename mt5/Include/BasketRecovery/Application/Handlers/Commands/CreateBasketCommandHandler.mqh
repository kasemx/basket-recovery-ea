#ifndef BASKET_RECOVERY_APPLICATION_CREATE_BASKET_COMMAND_HANDLER_MQH
#define BASKET_RECOVERY_APPLICATION_CREATE_BASKET_COMMAND_HANDLER_MQH

#include <BasketRecovery/Application/Ports/ICommandHandler.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Commands/CreateBasketCommand.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Validation/BasketValidator.mqh>
#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CCreateBasketCommandHandler : public ICommandHandler
  {
private:
   IBasketRepository    *m_repository;
   IClock               *m_clock;
   IUniqueIdGenerator   *m_idGenerator;
   CProfileSnapshot      m_profileSnapshot;

public:
                     CCreateBasketCommandHandler(IBasketRepository *repository,
                                                   IClock *clock,
                                                   IUniqueIdGenerator *idGenerator,
                                                   const CProfileSnapshot &profileSnapshot)
     {
      m_repository=repository;
      m_clock=clock;
      m_idGenerator=idGenerator;
      m_profileSnapshot=profileSnapshot;
     }

   virtual          ~CCreateBasketCommandHandler(void) {}

   virtual bool      CanHandle(const ICommand *command) const
     {
      return command!=NULL && command.Type()==BRE_COMMAND_CREATE_BASKET;
     }

   virtual CResult<CCommandExecutionResult> Execute(ICommand *command)
     {
      CCreateBasketCommand *createCommand=(CCreateBasketCommand*)command;
      if(createCommand==NULL)
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_COMMAND_INVALID,"Create basket command is required");

      CBasketId basketId(createCommand.BasketId().IsEmpty() ? m_idGenerator.NewGuid() : createCommand.BasketId().Value());
      if(m_repository!=NULL && m_repository.Exists(basketId))
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_BASKET_ALREADY_EXISTS,"Basket already exists");

      CCommandId commandId=createCommand.Id().IsEmpty() ? CCommandId(m_idGenerator.NewGuid()) : createCommand.Id();
      CEventId eventId(m_idGenerator.NewGuid());
      CUtcTime timestampUtc(m_clock!=NULL ? m_clock.Now() : 0);

      CResult<CBasketAggregate> aggregateResult=CBasketFactory::Create(basketId,
                                                                     m_profileSnapshot,
                                                                     createCommand.CorrelationKey(),
                                                                     createCommand.Direction(),
                                                                     createCommand.Symbol(),
                                                                     createCommand.SignalId(),
                                                                     timestampUtc,
                                                                     commandId,
                                                                     eventId);
      if(aggregateResult.IsFail())
         return CResult<CCommandExecutionResult>::Fail(aggregateResult.ErrorCode(),aggregateResult.ErrorMessage());

      CBasketAggregate aggregate;
      if(!aggregateResult.TryGetValue(aggregate))
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_BASKET_INVALID,"Aggregate missing after factory create");

      CVoidResult validation=CBasketValidator::Validate(aggregate);
      if(validation.IsFail())
         return CResult<CCommandExecutionResult>::Fail(validation.ErrorCode(),validation.ErrorMessage());

      if(m_repository!=NULL)
        {
         CVoidResult saveResult=m_repository.Save(aggregate);
         if(saveResult.IsFail())
            return CResult<CCommandExecutionResult>::Fail(saveResult.ErrorCode(),saveResult.ErrorMessage());
        }

      CCommandExecutionResult executionResult;
      CDomainEvent *event=new CDomainEvent();
      event.SetEventType(BRE_EVENT_BASKET_CREATED);
      event.SetBasketId(aggregate.Id());
      event.SetCorrelationId(aggregate.CorrelationKey());
      event.SetOccurredAt(timestampUtc.Value());
      executionResult.AddEvent(event);
      return CResult<CCommandExecutionResult>::Ok(executionResult);
     }
  };

#endif
