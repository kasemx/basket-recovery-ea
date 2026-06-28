#ifndef BRE_APP_RECOVERY_STEP_EXECUTION_TRACKER_MQH
#define BRE_APP_RECOVERY_STEP_EXECUTION_TRACKER_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>

class CRecoveryStepExecutionTracker
  {
private:
   struct SRecoveryStepKey
     {
      string   basketId;
      int      stepIndex;
     };

   struct SRecoveryStepState
     {
      string   basketId;
      int      stepIndex;
      string   executionRequestId;
      bool     submitted;
      bool     filled;
     };

   SRecoveryStepState m_states[];

   int               FindIndex(const string basketId,const int stepIndex) const
     {
      for(int i=0;i<ArraySize(m_states);i++)
        {
         if(m_states[i].basketId==basketId && m_states[i].stepIndex==stepIndex)
            return i;
        }
      return -1;
     }

public:
   bool              IsStepExecuted(const string basketId,const int stepIndex) const
     {
      int index=FindIndex(basketId,stepIndex);
      if(index<0)
         return false;
      return m_states[index].filled;
     }

   bool              IsStepSubmitted(const string basketId,const int stepIndex) const
     {
      int index=FindIndex(basketId,stepIndex);
      if(index<0)
         return false;
      return m_states[index].submitted;
     }

   void              MarkSubmitted(const string basketId,
                                   const int stepIndex,
                                   const string executionRequestId)
     {
      int index=FindIndex(basketId,stepIndex);
      if(index<0)
        {
         int size=ArraySize(m_states);
         ArrayResize(m_states,size+1);
         m_states[size].basketId=basketId;
         m_states[size].stepIndex=stepIndex;
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
