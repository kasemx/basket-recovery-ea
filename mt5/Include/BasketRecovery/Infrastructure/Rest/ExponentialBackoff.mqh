#ifndef BASKET_RECOVERY_INFRASTRUCTURE_EXPONENTIAL_BACKOFF_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_EXPONENTIAL_BACKOFF_MQH

class CExponentialBackoff
  {
private:
   int m_delaysMs[];
   int m_maxAttempts;

public:
                     CExponentialBackoff(const int maxAttempts=3)
     {
      m_maxAttempts=maxAttempts;
      ArrayResize(m_delaysMs,0);
     }

   void              SetDelaysMs(const int &delaysMs[],const int count)
     {
      ArrayResize(m_delaysMs,count);
      for(int i=0;i<count;i++)
         m_delaysMs[i]=delaysMs[i];
     }

   void              UseDefaultGetDelays(void)
     {
      int delays[]={1000,2000,4000};
      SetDelaysMs(delays,3);
     }

   void              UseDefaultPostDelays(void)
     {
      int delays[]={1000,2000,4000,8000,16000};
      SetDelaysMs(delays,5);
     }

   int               MaxAttempts(void) const
     {
      int configured=ArraySize(m_delaysMs);
      if(configured<=0)
         return m_maxAttempts;
      return configured;
     }

   int               DelayMsForAttempt(const int attemptIndex) const
     {
      if(attemptIndex<0)
         return 0;
      if(ArraySize(m_delaysMs)==0)
         return (int)(1000*MathPow(2.0,attemptIndex));
      if(attemptIndex>=ArraySize(m_delaysMs))
         return m_delaysMs[ArraySize(m_delaysMs)-1];
      return m_delaysMs[attemptIndex];
     }

   void              WaitBeforeRetry(const int attemptIndex) const
     {
      int delayMs=DelayMsForAttempt(attemptIndex);
      if(delayMs>0)
         Sleep(delayMs);
     }
  };

#endif
