#ifndef BASKET_RECOVERY_TESTS_TRANSITION_TEST_FIXTURE_MQH
#define BASKET_RECOVERY_TESTS_TRANSITION_TEST_FIXTURE_MQH

#include <BasketRecovery/Application/Kernel/TransitionRuleRegistry.mqh>
#include <BasketRecovery/Application/Kernel/DefaultTransitionRuleTable.mqh>
#include <BasketRecovery/Application/Kernel/TransitionEngine.mqh>
#include <BasketRecovery/Domain/StateMachine/AlwaysTrueTransitionGuard.mqh>
#include <BasketRecovery/Tests/BasketReadModelStub.mqh>
#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Tests/TestAssert.mqh>

class CTransitionTestFixture
  {
private:
   CTransitionRuleRegistry      m_registry;
   CAlwaysTrueTransitionGuard   m_guard;
   CTransitionEngine           *m_engine;

public:
                     CTransitionTestFixture(void)
     {
      m_engine=NULL;
     }

                    ~CTransitionTestFixture(void)
     {
      if(m_engine!=NULL)
        {
         delete m_engine;
         m_engine=NULL;
        }
     }

   bool              Initialize(void)
     {
      CVoidResult populateResult=CDefaultTransitionRuleTable::RegisterDefaultRules(m_registry,&m_guard);
      if(populateResult.IsFail())
         return false;

      CVoidResult validateResult=m_registry.Validate();
      if(validateResult.IsFail())
         return false;

      m_engine=new CTransitionEngine(&m_registry);
      return m_engine!=NULL;
     }

   ITransitionRuleRegistry* Registry(void) { return &m_registry; }
   CTransitionEngine*       Engine(void) { return m_engine; }

   void              AssertRuleApplied(const ENUM_BRE_BASKET_LIFECYCLE_STATE currentState,
                                       const ENUM_BRE_EVENT_TYPE eventType,
                                       const ENUM_BRE_BASKET_LIFECYCLE_STATE expectedNextState)
     {
      CBasketReadModelStub basket;
      basket.SetLifecycleState(currentState);

      CDomainEvent event;
      event.SetEventType(eventType);

      CResult<CTransitionResult> result=m_engine.ApplyTransition(basket,event);
      CTestAssert::True(result.IsOk(),"ApplyTransition returned failure result");

      CTransitionResult transitionResult;
      CTestAssert::True(result.TryGetValue(transitionResult),"Transition result missing value");
      CTestAssert::True(transitionResult.Applied(),"Transition should be applied");
      CTestAssert::EqualInt(currentState,transitionResult.PreviousState(),"Previous state mismatch");
      CTestAssert::EqualInt(expectedNextState,transitionResult.NewState(),"Next state mismatch");
     }

   void              AssertRuleRejected(const ENUM_BRE_BASKET_LIFECYCLE_STATE currentState,
                                        const ENUM_BRE_EVENT_TYPE eventType)
     {
      CBasketReadModelStub basket;
      basket.SetLifecycleState(currentState);

      CDomainEvent event;
      event.SetEventType(eventType);

      CResult<CTransitionResult> result=m_engine.ApplyTransition(basket,event);
      CTestAssert::True(result.IsOk(),"ApplyTransition returned failure result");

      CTransitionResult transitionResult;
      CTestAssert::True(result.TryGetValue(transitionResult),"Transition result missing value");
      CTestAssert::False(transitionResult.Applied(),"Transition should be rejected");
      CTestAssert::EqualInt(currentState,transitionResult.NewState(),"State must remain unchanged");
     }
  };

#endif
