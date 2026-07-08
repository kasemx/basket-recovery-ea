#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackAuditSkippedLogThrottle.mqh>

void TestFirstFailureLogsImmediately(void)
  {
   CFastTrackAuditSkippedLogThrottle throttle;
   CTestAssert::True(throttle.ShouldLogSkipped("FILE_NOT_FOUND",1000,30),
                     "First FILE_NOT_FOUND must log");
  }

void TestRepeatedFailureSuppressedWithinWindow(void)
  {
   CFastTrackAuditSkippedLogThrottle throttle;
   CTestAssert::True(throttle.ShouldLogSkipped("FILE_NOT_FOUND",1000,30),
                     "Initial log required");
   CTestAssert::False(throttle.ShouldLogSkipped("FILE_NOT_FOUND",1005,30),
                      "5s repeat must be throttled");
   CTestAssert::False(throttle.ShouldLogSkipped("FILE_NOT_FOUND",1029,30),
                      "29s repeat must remain throttled");
  }

void TestRepeatedFailureLogsAfterThrottleWindow(void)
  {
   CFastTrackAuditSkippedLogThrottle throttle;
   CTestAssert::True(throttle.ShouldLogSkipped("FILE_NOT_FOUND",1000,30),
                     "Initial log required");
   CTestAssert::True(throttle.ShouldLogSkipped("FILE_NOT_FOUND",1030,30),
                     "30s window must allow next log");
   CTestAssert::False(throttle.ShouldLogSkipped("FILE_NOT_FOUND",1035,30),
                      "Subsequent repeat must throttle again");
  }

void TestReasonChangeLogsImmediately(void)
  {
   CFastTrackAuditSkippedLogThrottle throttle;
   CTestAssert::True(throttle.ShouldLogSkipped("FILE_NOT_FOUND",1000,30),
                     "Initial FILE_NOT_FOUND log required");
   CTestAssert::True(throttle.ShouldLogSkipped("EMPTY_SEED",1005,30),
                     "Reason change must log immediately");
  }

void TestReadSuccessResetsThrottle(void)
  {
   CFastTrackAuditSkippedLogThrottle throttle;
   CTestAssert::True(throttle.ShouldLogSkipped("FILE_NOT_FOUND",1000,30),
                     "Initial log required");
   CTestAssert::False(throttle.ShouldLogSkipped("FILE_NOT_FOUND",1005,30),
                      "Repeat must throttle before reset");
   throttle.NotifyReadSuccess();
   CTestAssert::True(throttle.ShouldLogSkipped("FILE_NOT_FOUND",1006,30),
                     "After read success missing file must log again");
  }

void TestPollingSimulationDoesNotSpam(void)
  {
   CFastTrackAuditSkippedLogThrottle throttle;
   int logCount=0;
   for(int second=0;second<60;second+=5)
     {
      if(throttle.ShouldLogSkipped("FILE_NOT_FOUND",1000+second,30))
         logCount++;
     }
   CTestAssert::EqualInt(2,logCount,"60s polling at 5s must produce two logs max");
  }

void OnStart(void)
  {
   TestFirstFailureLogsImmediately();
   TestRepeatedFailureSuppressedWithinWindow();
   TestRepeatedFailureLogsAfterThrottleWindow();
   TestReasonChangeLogsImmediately();
   TestReadSuccessResetsThrottle();
   TestPollingSimulationDoesNotSpam();
   Print("TestSprint9eFastTrackAuditFileNotFoundLogThrottle: PASS");
  }
