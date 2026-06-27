#ifndef BASKET_RECOVERY_TESTS_AGGREGATE_TEST_FIXTURE_MQH
#define BASKET_RECOVERY_TESTS_AGGREGATE_TEST_FIXTURE_MQH

#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/TestSequentialIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Application/Kernel/TransitionRuleRegistry.mqh>
#include <BasketRecovery/Application/Kernel/DefaultTransitionRuleTable.mqh>
#include <BasketRecovery/Application/Kernel/TransitionEngine.mqh>
#include <BasketRecovery/Application/Handlers/StateTransitionHandler.mqh>
#include <BasketRecovery/Application/Handlers/Commands/CreateBasketCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/Commands/ActivateBasketCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/Commands/CloseBasketCommandHandler.mqh>
#include <BasketRecovery/Domain/StateMachine/AlwaysTrueTransitionGuard.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileBundle.mqh>
#include <BasketRecovery/Domain/Configuration/RiskProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/RecoveryProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/TakeProfitProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/BreakEvenProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/ExecutionProfileConfig.mqh>
#include <BasketRecovery/Application/Configuration/ProfileSnapshotFactory.mqh>
#include <BasketRecovery/Domain/Requests/TransitionRequest.mqh>
#include <BasketRecovery/Shared/Types/Price.mqh>

class CAggregateTestFixture
  {
private:
   CTestClock                    m_clock;
   CTestSequentialIdGenerator    m_idGenerator;
   CInMemoryBasketRepository     m_repository;
   CTransitionRuleRegistry       m_registry;
   CAlwaysTrueTransitionGuard    m_guard;
   CTransitionEngine            *m_engine;
   CStateTransitionHandler      *m_transitionHandler;
   CCreateBasketCommandHandler  *m_createHandler;
   CActivateBasketCommandHandler *m_activateHandler;
   CCloseBasketCommandHandler   *m_closeHandler;
   CProfileSnapshot              m_profileSnapshot;

public:
                     CAggregateTestFixture(void)
     {
      m_engine=NULL;
      m_transitionHandler=NULL;
      m_createHandler=NULL;
      m_activateHandler=NULL;
      m_closeHandler=NULL;
     }

                    ~CAggregateTestFixture(void)
     {
      if(m_closeHandler!=NULL) delete m_closeHandler;
      if(m_activateHandler!=NULL) delete m_activateHandler;
      if(m_createHandler!=NULL) delete m_createHandler;
      if(m_transitionHandler!=NULL) delete m_transitionHandler;
      if(m_engine!=NULL) delete m_engine;
     }

   bool              Initialize(void)
     {
      m_profileSnapshot=BuildProfileSnapshot();
      CDefaultTransitionRuleTable::RegisterDefaultRules(m_registry,&m_guard);
      if(m_registry.Validate().IsFail())
         return false;

      m_engine=new CTransitionEngine(&m_registry);
      m_transitionHandler=new CStateTransitionHandler(m_engine);
      m_createHandler=new CCreateBasketCommandHandler(&m_repository,&m_clock,&m_idGenerator,m_profileSnapshot);
      m_activateHandler=new CActivateBasketCommandHandler(&m_repository,m_transitionHandler,&m_clock,&m_idGenerator);
      m_closeHandler=new CCloseBasketCommandHandler(&m_repository,m_transitionHandler,&m_clock,&m_idGenerator);
      return true;
     }

   CTestClock                   *Clock(void) { return GetPointer(m_clock); }
   CInMemoryBasketRepository    *Repository(void) { return GetPointer(m_repository); }
   CStateTransitionHandler      *TransitionHandler(void) { return m_transitionHandler; }
   CCreateBasketCommandHandler  *CreateHandler(void) { return m_createHandler; }
   CActivateBasketCommandHandler *ActivateHandler(void) { return m_activateHandler; }
   CCloseBasketCommandHandler   *CloseHandler(void) { return m_closeHandler; }

   CProfileSnapshot              BuildProfileSnapshot(void)
     {
      CProfileBundle bundle;
      bundle.SetProfileName("default");
      CRiskProfileConfig risk;
      risk.SetProfileName("default");
      bundle.SetRisk(risk);
      CRecoveryProfileConfig recovery;
      recovery.SetProfileName("default");
      bundle.SetRecovery(recovery);
      CTakeProfitProfileConfig takeProfit;
      takeProfit.SetProfileName("default");
      bundle.SetTakeProfit(takeProfit);
      CBreakEvenProfileConfig breakEven;
      breakEven.SetProfileName("default");
      bundle.SetBreakEven(breakEven);
      CExecutionProfileConfig execution;
      execution.SetProfileName("default");
      bundle.SetExecution(execution);
      bundle.SetBoundAt(CUtcTime(m_clock.Now()));
      return CProfileSnapshotFactory::FromBundle(bundle,m_clock);
     }

   bool              MoveToWaitDetails(CBasketAggregate &aggregate)
     {
      CTransitionRequest request=CTransitionRequest::ForLifecycle(aggregate.Id(),
                                                                  CCommandId("cmd-wait-details"),
                                                                  CEventId("evt-wait-details"),
                                                                  BRE_EVENT_INITIAL_POSITIONS_OPENED);
      CResult<CCommandExecutionResult> result=m_transitionHandler.ProcessLifecycle(aggregate,request,CUtcTime(m_clock.Now()));
      if(result.IsFail())
         return false;
      return m_repository.Save(aggregate).IsOk();
     }

   CSignalDetails    BuildSignalDetails(void)
     {
      CSignalDetails details;
      details.SetHasDetails(true);
      details.SetStopLoss(CPrice(1900.0));
      details.SetTp1(CPrice(1950.0));
      details.SetTp2(CPrice(2000.0));
      details.SetTp3(CPrice(2050.0));
      return details;
     }
  };

#endif
