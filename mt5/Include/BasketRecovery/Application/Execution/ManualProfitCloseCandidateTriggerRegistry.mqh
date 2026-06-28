#ifndef BRE_APP_MANUAL_PROFIT_CLOSE_CANDIDATE_TRIGGER_REGISTRY_MQH
#define BRE_APP_MANUAL_PROFIT_CLOSE_CANDIDATE_TRIGGER_REGISTRY_MQH

class CManualProfitCloseCandidateTriggerRegistry
  {
private:
   string m_consumedTokens[];

   bool              Contains(const string triggerToken) const
     {
      for(int i=0;i<ArraySize(m_consumedTokens);i++)
        {
         if(m_consumedTokens[i]==triggerToken)
            return true;
        }
      return false;
     }

public:
   bool              IsConsumed(const string triggerToken) const
     {
      if(triggerToken=="")
         return false;
      return Contains(triggerToken);
     }

   void              Consume(const string triggerToken)
     {
      if(triggerToken=="" || Contains(triggerToken))
         return;
      int size=ArraySize(m_consumedTokens);
      ArrayResize(m_consumedTokens,size+1);
      m_consumedTokens[size]=triggerToken;
     }

   void              Clear(void) { ArrayResize(m_consumedTokens,0); }
  };

#endif
