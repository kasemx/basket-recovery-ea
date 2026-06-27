#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Infrastructure/Idempotency/InMemoryIdempotencyStore.mqh>

void TestMarkAndLookup(void)
  {
   CInMemoryIdempotencyStore store;

   CTestAssert::False(store.IsProcessed("key-001"),"Fresh key must not be processed");
   CTestAssert::True(store.MarkProcessed("key-001").IsOk(),"MarkProcessed must succeed");
   CTestAssert::True(store.IsProcessed("key-001"),"Processed key must be found");
   CTestAssert::EqualInt(1,store.Count(),"Store count must be one");
  }

void TestDuplicateMarkIsIdempotent(void)
  {
   CInMemoryIdempotencyStore store;
   CTestAssert::True(store.MarkProcessed("key-dup").IsOk(),"First mark must succeed");
   CTestAssert::True(store.MarkProcessed("key-dup").IsOk(),"Duplicate mark must be idempotent");
   CTestAssert::EqualInt(1,store.Count(),"Duplicate mark must not increase count");
  }

void TestClear(void)
  {
   CInMemoryIdempotencyStore store;
   store.MarkProcessed("key-clear");
   CTestAssert::True(store.Clear().IsOk(),"Clear must succeed");
   CTestAssert::False(store.IsProcessed("key-clear"),"Cleared key must not be processed");
   CTestAssert::EqualInt(0,store.Count(),"Store must be empty after clear");
  }

void TestEmptyKeyRejected(void)
  {
   CInMemoryIdempotencyStore store;
   CTestAssert::True(store.MarkProcessed("").IsFail(),"Empty idempotency key must fail");
  }

void OnStart()
  {
   CTestAssert::Reset();

   TestMarkAndLookup();
   TestDuplicateMarkIsIdempotent();
   TestClear();
   TestEmptyKeyRejected();

   CTestAssert::Summary("TestIdempotencyStore");
   if(!CTestAssert::AllPassed())
      Print("TestIdempotencyStore FAILED");
  }
