#ifndef BRE_APP_PROFIT_LEVEL_CLOSE_EXECUTION_TRACKER_MQH
#define BRE_APP_PROFIT_LEVEL_CLOSE_EXECUTION_TRACKER_MQH

class CProfitLevelCloseExecutionTracker
  {
private:
   struct SProfitLevelCloseState
     {
      string basketId;
      string profitLevelId;
      string executionRequestId;
      bool   submitted;
      bool   filled;
     };

   SProfitLevelCloseState m_states[];

   int               FindIndex(const string basketId,const string profitLevelId) const
     {
      for(int i=0;i<ArraySize(m_states);i++)
        {
         if(m_states[i].basketId==basketId && m_states[i].profitLevelId==profitLevelId)
            return i;
        }
      return -1;
     }

public:
   bool              IsLevelCompleted(const string basketId,const string profitLevelId) const
     {
      int index=FindIndex(basketId,profitLevelId);
      if(index<0)
         return false;
      return m_states[index].filled;
     }

   bool              IsLevelSubmitted(const string basketId,const string profitLevelId) const
     {
      int index=FindIndex(basketId,profitLevelId);
      if(index<0)
         return false;
      return m_states[index].submitted;
     }

   void              MarkSubmitted(const string basketId,
                                   const string profitLevelId,
                                   const string executionRequestId)
     {
      int index=FindIndex(basketId,profitLevelId);
      if(index<0)
        {
         int size=ArraySize(m_states);
         ArrayResize(m_states,size+1);
         m_states[size].basketId=basketId;
         m_states[size].profitLevelId=profitLevelId;
         m_states[size].executionRequestId=executionRequestId;
         m_states[size].submitted=true;
         m_states[size].filled=false;
         return;
        }
      m_states[index].executionRequestId=executionRequestId;
      m_states[index].submitted=true;
     }

   bool              TryMarkFilled(const string executionRequestId)
     {
      for(int i=0;i<ArraySize(m_states);i++)
        {
         if(m_states[i].executionRequestId!=executionRequestId)
            continue;
         if(m_states[i].filled)
            return false;
         m_states[i].filled=true;
         return true;
        }
      return false;
     }

   void              Clear(void) { ArrayResize(m_states,0); }
  };

#endif
