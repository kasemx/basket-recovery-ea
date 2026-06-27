#ifndef BASKET_RECOVERY_INFRASTRUCTURE_REST_CIRCUIT_BREAKER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_REST_CIRCUIT_BREAKER_MQH

class CRestCircuitBreaker
  {
private:
   int      m_failureCount;
   datetime m_lastFailureUtc;
   bool     m_isOpen;
   int      m_failureThreshold;
   int      m_windowSeconds;
   int      m_openDurationSeconds;

public:
                     CRestCircuitBreaker(const int failureThreshold=5,
                                         const int windowSeconds=60,
                                         const int openDurationSeconds=60)
     {
      m_failureCount=0;
      m_lastFailureUtc=0;
      m_isOpen=false;
      m_failureThreshold=failureThreshold;
      m_windowSeconds=windowSeconds;
      m_openDurationSeconds=openDurationSeconds;
     }

   bool              IsOpen(void) const { return m_isOpen; }

   bool              AllowRequest(void)
     {
      datetime now=TimeGMT();
      if(m_isOpen)
        {
         if((now-m_lastFailureUtc)>=m_openDurationSeconds)
           {
            m_isOpen=false;
            m_failureCount=0;
            return true;
           }
         return false;
        }
      return true;
     }

   void              RecordSuccess(void)
     {
      m_failureCount=0;
      m_isOpen=false;
     }

   void              RecordFailure(void)
     {
      datetime now=TimeGMT();
      if(m_lastFailureUtc>0 && (now-m_lastFailureUtc)>m_windowSeconds)
         m_failureCount=0;

      m_failureCount++;
      m_lastFailureUtc=now;
      if(m_failureCount>=m_failureThreshold)
         m_isOpen=true;
     }
  };

#endif
