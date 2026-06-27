#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Shared/Types/ResultValueTransfer.mqh>
#include <BasketRecovery/Shared/Types/DomainEventResult.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryStep.mqh>
#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Application/Commands/CreateBasketCommand.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

void TestResultSuccessExtraction(void)
  {
   CRecoveryStep step=CRecoveryStep::Create(1,10.0,0.01);

   CResult<CRecoveryStep> okResult=CResult<CRecoveryStep>::Ok(step);
   CTestAssert::True(okResult.IsOk(),"Ok result must succeed");
   CTestAssert::True(okResult.HasValue(),"Ok result must have value");

   CRecoveryStep extracted;
   CTestAssert::True(okResult.TryGetValue(extracted),"TryGetValue must succeed");
   CTestAssert::EqualInt(1,extracted.StepIndex(),"Extracted step index must match");

   CResult<int> failResult=CResult<int>::Fail(BRE_ERR_NONE,"expected failure");
   CTestAssert::True(failResult.IsFail(),"Fail result must fail");
   int unused=0;
   CTestAssert::False(failResult.TryGetValue(unused),"Fail result must not expose value");
  }

void TestImmutableValueObjectCopy(void)
  {
   CRecoveryStep original=CRecoveryStep::Create(3,15.0,0.05);

   CRecoveryStep copy(original);
   CTestAssert::EqualInt(3,copy.StepIndex(),"Copy ctor must preserve step index");
   CTestAssert::EqualDouble(0.05,copy.Lot(),0.0001,"Copy ctor must preserve lot size");

   CResult<CRecoveryStep> wrapped=CResult<CRecoveryStep>::Ok(original);
   CRecoveryStep fromResult;
   wrapped.TryGetValue(fromResult);
   CTestAssert::EqualInt(3,fromResult.StepIndex(),"Result copy path must preserve value object");
  }

void TestAdoptTransferNotCopy(void)
  {
   CEventHandlingResult source;
   CCreateBasketCommand *command=new CCreateBasketCommand();
   source.AddCommand(command);

   CResult<CEventHandlingResult> adopted=BreResultOkAdopting(source);
   CTestAssert::True(adopted.IsOk(),"Adopted result must succeed");
   CTestAssert::EqualInt(0,source.CommandCount(),"Source commands must be transferred out");

   CEventHandlingResult extracted;
   CTestAssert::True(BreResultTryAdoptValue(adopted,extracted),"Try adopt must succeed");
   CTestAssert::EqualInt(1,extracted.CommandCount(),"Extracted payload must retain command count");
   delete extracted.CommandAt(0);
  }

void TestPointerOwnershipResult(void)
  {
   CDomainEvent *event=new CDomainEvent();
   event.SetEventType(BRE_EVENT_STRATEGY_PROFILE_BOUND);

   CDomainEventResult result=CDomainEventResult::Ok(event);
   CTestAssert::True(result.HasValue(),"Pointer result must have value");

   CDomainEvent *extracted=NULL;
   CTestAssert::True(result.TryGetEvent(extracted),"TryGetEvent must succeed");
   CTestAssert::EqualInt((long)BRE_EVENT_STRATEGY_PROFILE_BOUND,(long)extracted.EventType(),"Event type must round-trip");
   delete extracted;
  }

void TestTemporaryToReferencePattern(void)
  {
   bool condition=true;
   string message="compile stabilization message "+IntegerToString(42);
   CTestAssert::True(condition,message);
  }

void OnStart()
  {
   CTestAssert::Reset();

   TestResultSuccessExtraction();
   TestImmutableValueObjectCopy();
   TestAdoptTransferNotCopy();
   TestPointerOwnershipResult();
   TestTemporaryToReferencePattern();

   CTestAssert::Summary("TestCompileStabilization");
   if(!CTestAssert::AllPassed())
      Print("TestCompileStabilization FAILED");
  }
