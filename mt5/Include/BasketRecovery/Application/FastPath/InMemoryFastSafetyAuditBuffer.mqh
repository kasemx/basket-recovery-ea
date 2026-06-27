#ifndef BRE_APP_IN_MEMORY_FAST_SAFETY_AUDIT_MQH
#define BRE_APP_IN_MEMORY_FAST_SAFETY_AUDIT_MQH

class CInMemoryFastSafetyAuditBuffer
  {
private:
   string m_keys[];
   int    m_codes[];
   int    m_count;
   int    m_dedupeWindowMs;
   ulong  m_lastTickMs[];

   int               FindIndex(const string key) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_keys[i]==key)
            return i;
        }
      return -1;
     }

public:
                     CInMemoryFastSafetyAuditBuffer(const int dedupeWindowMs=30000)
     {
      m_count=0;
      m_dedupeWindowMs=dedupeWindowMs;
     }

   bool              RecordIfNew(const string key,const int errorCode)
     {
      if(key=="")
         return false;

      int index=FindIndex(key);
      ulong nowMs=GetTickCount64();
      if(index>=0 && m_dedupeWindowMs>0)
        {
         ulong elapsed=nowMs-m_lastTickMs[index];
         if(elapsed<(ulong)m_dedupeWindowMs)
            return false;
         m_codes[index]=errorCode;
         m_lastTickMs[index]=nowMs;
         return true;
        }

      ArrayResize(m_keys,m_count+1);
      ArrayResize(m_codes,m_count+1);
      ArrayResize(m_lastTickMs,m_count+1);
      m_keys[m_count]=key;
      m_codes[m_count]=errorCode;
      m_lastTickMs[m_count]=nowMs;
      m_count++;
      return true;
     }

   int               Count(void) const { return m_count; }

   int               CodeAt(const int index) const
     {
      if(index<0 || index>=m_count)
         return 0;
      return m_codes[index];
     }
  };

#endif
