#ifndef BASKET_RECOVERY_TESTS_TEST_ASSERT_MQH
#define BASKET_RECOVERY_TESTS_TEST_ASSERT_MQH

class CTestAssert
  {
private:
   static int s_failedCount;
   static int s_passedCount;

public:
   static void       Reset(void)
     {
      s_failedCount=0;
      s_passedCount=0;
     }

   static void       True(const bool condition,const string &message)
     {
      if(condition)
        {
         s_passedCount++;
         return;
        }
      s_failedCount++;
      Print("ASSERT FAILED: ",message);
     }

   static void       False(const bool condition,const string &message)
     {
      True(!condition,message);
     }

   static void       EqualInt(const int expected,const int actual,const string &message)
     {
      True(expected==actual,StringFormat("%s | expected=%d actual=%d",message,expected,actual));
     }

   static void       EqualString(const string expected,const string actual,const string &message)
     {
      True(expected==actual,StringFormat("%s | expected=%s actual=%s",message,expected,actual));
     }

   static void       EqualDouble(const double expected,const double actual,const double epsilon,const string &message)
     {
      True(MathAbs(expected-actual)<=epsilon,StringFormat("%s | expected=%.4f actual=%.4f",message,expected,actual));
     }

   static int        FailedCount(void) { return s_failedCount; }
   static int        PassedCount(void) { return s_passedCount; }

   static bool       AllPassed(void) { return s_failedCount==0; }

   static void       Summary(const string &suiteName)
     {
      Print(StringFormat("%s | passed=%d failed=%d",suiteName,s_passedCount,s_failedCount));
     }
  };

int CTestAssert::s_failedCount=0;
int CTestAssert::s_passedCount=0;

#endif
