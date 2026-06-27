#ifndef BASKET_RECOVERY_DOMAIN_BREAK_EVEN_PROFILE_CONFIG_MQH
#define BASKET_RECOVERY_DOMAIN_BREAK_EVEN_PROFILE_CONFIG_MQH

class CBreakEvenProfileConfig
  {
private:
   string m_profileName;
   double m_safetyBufferPips;
   bool   m_includeSpread;
   int    m_syncRetryCount;

public:
                     CBreakEvenProfileConfig(void)
     {
      m_profileName="default";
      m_safetyBufferPips=0.5;
      m_includeSpread=true;
      m_syncRetryCount=3;
     }

   string            ProfileName(void) const { return m_profileName; }
   double            SafetyBufferPips(void) const { return m_safetyBufferPips; }
   bool              IncludeSpread(void) const { return m_includeSpread; }
   int               SyncRetryCount(void) const { return m_syncRetryCount; }

   void              SetProfileName(const string value) { m_profileName=value; }
   void              SetSafetyBufferPips(const double value) { m_safetyBufferPips=value; }
   void              SetIncludeSpread(const bool value) { m_includeSpread=value; }
   void              SetSyncRetryCount(const int value) { m_syncRetryCount=value; }
  };

#endif
