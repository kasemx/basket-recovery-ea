#ifndef BASKET_RECOVERY_SHARED_UTC_TIME_MQH
#define BASKET_RECOVERY_SHARED_UTC_TIME_MQH

class CUtcTime
  {
private:
   datetime m_value;

public:
                     CUtcTime(void) { m_value=0; }
                     CUtcTime(const datetime value) { m_value=value; }

   datetime          Value(void) const { return m_value; }
   bool              IsEmpty(void) const { return m_value==0; }
  };

#endif
