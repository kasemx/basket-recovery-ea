#ifndef BRE_APP_FAST_TRACK_AUDIT_SKIPPED_LOG_THROTTLE_MQH
#define BRE_APP_FAST_TRACK_AUDIT_SKIPPED_LOG_THROTTLE_MQH

class CFastTrackAuditSkippedLogThrottle
  {
private:
   string            m_lastReason;
   datetime          m_lastLoggedAtUtc;

public:
                     CFastTrackAuditSkippedLogThrottle(void)
     {
      m_lastReason="";
      m_lastLoggedAtUtc=0;
     }

   void              Reset(void)
     {
      m_lastReason="";
      m_lastLoggedAtUtc=0;
     }

   void              NotifyReadSuccess(void)
     {
      Reset();
     }

   bool              ShouldLogSkipped(const string reason,const datetime nowUtc,const int throttleSeconds)
     {
      if(reason=="")
         return false;
      if(throttleSeconds<=0)
         return true;
      if(reason!=m_lastReason)
        {
         m_lastReason=reason;
         m_lastLoggedAtUtc=nowUtc;
         return true;
        }
      if(m_lastLoggedAtUtc<=0 || (nowUtc-m_lastLoggedAtUtc)>=throttleSeconds)
        {
         m_lastLoggedAtUtc=nowUtc;
         return true;
        }
      return false;
     }
  };

#endif
