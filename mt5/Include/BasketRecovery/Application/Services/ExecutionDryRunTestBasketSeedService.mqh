#ifndef BRE_APP_EXECUTION_DRY_RUN_TEST_BASKET_SEED_SERVICE_MQH
#define BRE_APP_EXECUTION_DRY_RUN_TEST_BASKET_SEED_SERVICE_MQH

#include <BasketRecovery/Application/Handlers/Commands/CreateBasketCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/Commands/ActivateBasketCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/StateTransitionHandler.mqh>
#include <BasketRecovery/Application/UseCases/BindMigratedBasketStrategyUseCase.mqh>
#include <BasketRecovery/Application/Commands/CreateBasketCommand.mqh>
#include <BasketRecovery/Application/Commands/ActivateBasketCommand.mqh>
#include <BasketRecovery/Application/Configuration/ProfileSnapshotFactory.mqh>
#include <BasketRecovery/Application/Kernel/TransitionRuleRegistry.mqh>
#include <BasketRecovery/Application/Kernel/DefaultTransitionRuleTable.mqh>
#include <BasketRecovery/Application/Kernel/TransitionEngine.mqh>
#include <BasketRecovery/Domain/StateMachine/AlwaysTrueTransitionGuard.mqh>
#include <BasketRecovery/Domain/Requests/TransitionRequest.mqh>
#include <BasketRecovery/Infrastructure/Configuration/DefaultProfileLoader.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketSerializer.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CExecutionDryRunTestBasketSeedService
  {
private:
   IBasketRepository              *m_repository;
   IClock                         *m_clock;
   IUniqueIdGenerator             *m_idGenerator;
   CCreateBasketCommandHandler    *m_createHandler;
   CActivateBasketCommandHandler  *m_activateHandler;
   CBindMigratedBasketStrategyUseCase *m_bindMigrationUseCase;
   CStateTransitionHandler        *m_transitionHandler;
   CTransitionRuleRegistry        *m_transitionRegistry;
   CTransitionEngine              *m_transitionEngine;
   CAlwaysTrueTransitionGuard      m_transitionGuard;
   CProfileSnapshot                m_profileSnapshot;

   CSignalDetails BuildSignalDetailsForSymbol(const string symbol) const
     {
      double bid=SymbolInfoDouble(symbol,SYMBOL_BID);
      if(bid<=0.0)
         bid=100000.0;
      double spread=SymbolInfoDouble(symbol,SYMBOL_ASK)-bid;
      if(spread<=0.0)
         spread=bid*0.0001;

      CSignalDetails details;
      details.SetHasDetails(true);
      details.SetStopLoss(CPrice(bid-spread*50.0));
      details.SetTp1(CPrice(bid+spread*50.0));
      details.SetTp2(CPrice(bid+spread*100.0));
      details.SetTp3(CPrice(bid+spread*150.0));
      return details;
     }

   CVoidResult MoveToWaitDetails(CBasketAggregate &aggregate)
     {
      if(m_transitionHandler==NULL)
         return CVoidResult::Fail(BRE_ERR_SERVICE_NOT_REGISTERED,"Transition handler is not configured");

      CTransitionRequest request=CTransitionRequest::ForLifecycle(aggregate.Id(),
                                                                  CCommandId("cmd-seed-wait-details"),
                                                                  CEventId("evt-seed-wait-details"),
                                                                  BRE_EVENT_INITIAL_POSITIONS_OPENED);
      CUtcTime timestampUtc(m_clock!=NULL ? m_clock.Now() : 0);
      CResult<CCommandExecutionResult> result=m_transitionHandler.ProcessLifecycle(aggregate,request,timestampUtc);
      if(result.IsFail())
         return CVoidResult::Fail(result.ErrorCode(),result.ErrorMessage());
      return m_repository.Save(aggregate);
     }

public:
                     CExecutionDryRunTestBasketSeedService(void)
     {
      m_repository=NULL;
      m_clock=NULL;
      m_idGenerator=NULL;
      m_createHandler=NULL;
      m_activateHandler=NULL;
      m_bindMigrationUseCase=NULL;
      m_transitionHandler=NULL;
      m_transitionRegistry=NULL;
      m_transitionEngine=NULL;
     }

                    ~CExecutionDryRunTestBasketSeedService(void)
     {
      if(m_activateHandler!=NULL) delete m_activateHandler;
      if(m_createHandler!=NULL) delete m_createHandler;
      if(m_bindMigrationUseCase!=NULL) delete m_bindMigrationUseCase;
      if(m_transitionHandler!=NULL) delete m_transitionHandler;
      if(m_transitionEngine!=NULL) delete m_transitionEngine;
      if(m_transitionRegistry!=NULL) delete m_transitionRegistry;
     }

   bool              Initialize(IBasketRepository *repository,
                              IClock *clock,
                              IUniqueIdGenerator *idGenerator,
                              const string profileName="default")
     {
      if(repository==NULL || clock==NULL || idGenerator==NULL)
         return false;

      m_repository=repository;
      m_clock=clock;
      m_idGenerator=idGenerator;

      CDefaultProfileLoader profileLoader(clock);
      CResult<CProfileBundle> profileResult=profileLoader.LoadProfile(profileName);
      if(profileResult.IsFail())
         return false;
      CProfileBundle profileBundle;
      if(!profileResult.TryGetValue(profileBundle))
         return false;
      m_profileSnapshot=CProfileSnapshotFactory::FromBundle(profileBundle,*clock);

      m_transitionRegistry=new CTransitionRuleRegistry();
      if(CDefaultTransitionRuleTable::RegisterDefaultRules(*m_transitionRegistry,&m_transitionGuard).IsFail())
         return false;
      if(m_transitionRegistry.Validate().IsFail())
         return false;

      m_transitionEngine=new CTransitionEngine(m_transitionRegistry);
      m_transitionHandler=new CStateTransitionHandler(m_transitionEngine);
      m_createHandler=new CCreateBasketCommandHandler(m_repository,m_clock,m_idGenerator,m_profileSnapshot);
      m_activateHandler=new CActivateBasketCommandHandler(m_repository,m_transitionHandler,m_clock,m_idGenerator);
      m_bindMigrationUseCase=new CBindMigratedBasketStrategyUseCase(m_repository,m_clock,m_idGenerator);
      return true;
     }

   static string     PersistenceStoreLabel(void)
     {
      return "CFileBasketRepository via "+BRE_PERSISTENCE_BASKET_SUBDIR;
     }

   static string     SerializerLabel(void)
     {
      return "CBasketSerializer (atomic write via CJsonWriter CRC32)";
     }

   static string     UseCaseFlowLabel(void)
     {
      return "CCreateBasketCommandHandler -> INITIAL_POSITIONS_OPENED -> CBindMigratedBasketStrategyUseCase -> CActivateBasketCommandHandler";
     }

   CResult<CBasketAggregate> SeedActiveBasket(const CBasketId &basketId,
                                              const string symbol,
                                              const ENUM_BRE_TRADE_DIRECTION direction,
                                              const string strategyCanonicalJson)
     {
      if(m_repository==NULL || m_createHandler==NULL || m_activateHandler==NULL || m_bindMigrationUseCase==NULL)
         return CResult<CBasketAggregate>::Fail(BRE_ERR_SERVICE_NOT_REGISTERED,"Seed service is not initialized");

      if(basketId.IsEmpty())
         return CResult<CBasketAggregate>::Fail(BRE_ERR_BASKET_INVALID,"Basket id is required");
      if(symbol=="")
         return CResult<CBasketAggregate>::Fail(BRE_ERR_BASKET_INVALID,"Symbol is required");
      if(strategyCanonicalJson=="")
         return CResult<CBasketAggregate>::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Strategy canonical JSON is required");

      if(!SymbolSelect(symbol,true))
         return CResult<CBasketAggregate>::Fail(BRE_ERR_SYMBOL_UNAVAILABLE,"Symbol is not available: "+symbol);

      if(m_repository.Exists(basketId))
        {
         CResult<CBasketAggregate> existing=m_repository.Load(basketId);
         if(existing.IsOk())
           {
            CBasketAggregate aggregate;
            existing.TryGetValue(aggregate);
            if(aggregate.LifecycleState()==BRE_STATE_ACTIVE &&
               aggregate.Symbol()==symbol &&
               aggregate.HasStrategyProfile())
               return CResult<CBasketAggregate>::Ok(aggregate);
           }
         m_repository.Delete(basketId);
        }

      CCreateBasketCommand createCommand;
      createCommand.SetId(CCommandId("cmd-seed-create"));
      createCommand.SetBasketId(basketId);
      createCommand.SetSymbol(symbol);
      createCommand.SetDirection(direction);
      createCommand.SetSignalId(CSignalId("sig-"+basketId.Value()));
      createCommand.SetCorrelationKey("seed-"+basketId.Value());
      createCommand.SetIdempotencyKey("seed:create:"+basketId.Value());

      CResult<CCommandExecutionResult> createResult=m_createHandler.Execute(&createCommand);
      if(createResult.IsFail())
         return CResult<CBasketAggregate>::Fail(createResult.ErrorCode(),createResult.ErrorMessage());

      CResult<CBasketAggregate> loaded=m_repository.Load(basketId);
      if(loaded.IsFail())
         return loaded;

      CBasketAggregate aggregate;
      loaded.TryGetValue(aggregate);

      CVoidResult waitDetailsResult=MoveToWaitDetails(aggregate);
      if(waitDetailsResult.IsFail())
         return CResult<CBasketAggregate>::Fail(waitDetailsResult.ErrorCode(),waitDetailsResult.ErrorMessage());

      loaded=m_repository.Load(basketId);
      if(loaded.IsFail())
         return loaded;
      loaded.TryGetValue(aggregate);

      string strategyJson=strategyCanonicalJson;
      CStrategyProfileJsonParser parser;
      CResult<CStrategyProfile> profileResult=parser.Parse(strategyJson,CUtcTime(m_clock.Now()));
      if(profileResult.IsFail())
         return CResult<CBasketAggregate>::Fail(profileResult.ErrorCode(),profileResult.ErrorMessage());
      CStrategyProfile profile;
      profileResult.TryGetValue(profile);

      CDomainEventResult bindResult=m_bindMigrationUseCase.Execute(basketId,strategyJson,profile);
      if(bindResult.IsFail())
         return CResult<CBasketAggregate>::Fail(bindResult.ErrorCode(),bindResult.ErrorMessage());
      CDomainEvent *boundEvent=NULL;
      bindResult.TryGetEvent(boundEvent);
      if(boundEvent!=NULL)
         delete boundEvent;

      loaded=m_repository.Load(basketId);
      if(loaded.IsFail())
         return loaded;
      loaded.TryGetValue(aggregate);

      CActivateBasketCommand activateCommand;
      activateCommand.SetId(CCommandId("cmd-seed-activate"));
      activateCommand.SetBasketId(basketId);
      activateCommand.SetDetails(BuildSignalDetailsForSymbol(symbol));
      activateCommand.SetIdempotencyKey("seed:activate:"+basketId.Value());

      CResult<CCommandExecutionResult> activateResult=m_activateHandler.Execute(&activateCommand);
      if(activateResult.IsFail())
         return CResult<CBasketAggregate>::Fail(activateResult.ErrorCode(),activateResult.ErrorMessage());

      CResult<CBasketAggregate> activeLoaded=m_repository.Load(basketId);
      if(activeLoaded.IsFail())
         return activeLoaded;

      CBasketAggregate activeBasket;
      activeLoaded.TryGetValue(activeBasket);
      if(activeBasket.LifecycleState()!=BRE_STATE_ACTIVE)
         return CResult<CBasketAggregate>::Fail(BRE_ERR_BASKET_INVALID,"Seeded basket is not ACTIVE");
      if(!activeBasket.HasStrategyProfile())
         return CResult<CBasketAggregate>::Fail(BRE_ERR_STRATEGY_NOT_BOUND,"Seeded basket has no strategy snapshot");

      return CResult<CBasketAggregate>::Ok(activeBasket);
     }

   CResult<CBasketAggregate> VerifyPersistedRoundTrip(const CBasketId &basketId) const
     {
      if(m_repository==NULL)
         return CResult<CBasketAggregate>::Fail(BRE_ERR_SERVICE_NOT_REGISTERED,"Repository is not configured");
      return m_repository.Load(basketId);
     }
  };

#endif
