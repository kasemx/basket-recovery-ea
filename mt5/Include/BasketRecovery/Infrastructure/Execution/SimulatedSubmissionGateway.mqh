#ifndef BRE_INF_SIMULATED_SUBMISSION_GATEWAY_MQH
#define BRE_INF_SIMULATED_SUBMISSION_GATEWAY_MQH

#include <BasketRecovery/Application/Execution/Ports/ISubmissionGateway.mqh>
#include <BasketRecovery/Domain/Execution/SimulatedBrokerSubmissionScenario.mqh>

class CSimulatedSubmissionGateway : public ISubmissionGateway
  {
private:
   ENUM_BRE_SIMULATED_BROKER_SUBMISSION_SCENARIO m_defaultScenario;
   string                                        m_idempotencyKeys[];
   ENUM_BRE_SIMULATED_BROKER_SUBMISSION_SCENARIO m_scenarios[];
   int                                           m_submitCounts[];
   CSubmissionGatewayResult                      m_lastResults[];
   ulong                                         m_nextBrokerRequestId;

   int               FindIndex(const string idempotencyKey) const
     {
      for(int i=0;i<ArraySize(m_idempotencyKeys);i++)
        {
         if(m_idempotencyKeys[i]==idempotencyKey)
            return i;
        }
      return -1;
     }

   ENUM_BRE_SIMULATED_BROKER_SUBMISSION_SCENARIO ResolveScenario(const string idempotencyKey) const
     {
      int index=FindIndex(idempotencyKey);
      if(index<0)
         return m_defaultScenario;
      return m_scenarios[index];
     }

   void              RememberResult(const string idempotencyKey,const CSubmissionGatewayResult &result)
     {
      int index=FindIndex(idempotencyKey);
      if(index<0)
        {
         int size=ArraySize(m_idempotencyKeys);
         ArrayResize(m_idempotencyKeys,size+1);
         ArrayResize(m_scenarios,size+1);
         ArrayResize(m_submitCounts,size+1);
         ArrayResize(m_lastResults,size+1);
         m_idempotencyKeys[size]=idempotencyKey;
         m_scenarios[size]=m_defaultScenario;
         m_submitCounts[size]=0;
         m_lastResults[size]=result;
         index=size;
        }
      else
        {
         m_lastResults[index]=result;
        }
      m_submitCounts[index]++;
     }

   ulong             AllocateBrokerRequestId(void)
     {
      m_nextBrokerRequestId++;
      return m_nextBrokerRequestId;
     }

public:
                     CSimulatedSubmissionGateway(void)
     {
      m_defaultScenario=BRE_SIM_SUBMIT_ACCEPT_ACK;
      m_nextBrokerRequestId=900000;
     }

   void              SetDefaultScenario(const ENUM_BRE_SIMULATED_BROKER_SUBMISSION_SCENARIO scenario)
     {
      m_defaultScenario=scenario;
     }

   void              SetScenario(const string idempotencyKey,
                                 const ENUM_BRE_SIMULATED_BROKER_SUBMISSION_SCENARIO scenario)
     {
      int index=FindIndex(idempotencyKey);
      if(index<0)
        {
         int size=ArraySize(m_idempotencyKeys);
         ArrayResize(m_idempotencyKeys,size+1);
         ArrayResize(m_scenarios,size+1);
         ArrayResize(m_submitCounts,size+1);
         ArrayResize(m_lastResults,size+1);
         m_idempotencyKeys[size]=idempotencyKey;
         m_scenarios[size]=scenario;
         m_submitCounts[size]=0;
         index=size;
        }
      else
        {
         m_scenarios[index]=scenario;
        }
     }

   int               GetSubmitCallCount(const string idempotencyKey) const
     {
      int index=FindIndex(idempotencyKey);
      if(index<0)
         return 0;
      return m_submitCounts[index];
     }

   virtual bool      IsSimulated(void) const { return true; }

   virtual CSubmissionGatewayResult Submit(const CBrokerSubmissionEnvelope &envelope)
     {
      string idempotencyKey=envelope.IdempotencyKey();
      ENUM_BRE_SIMULATED_BROKER_SUBMISSION_SCENARIO scenario=ResolveScenario(idempotencyKey);
      int priorCount=GetSubmitCallCount(idempotencyKey);

      if(scenario==BRE_SIM_SUBMIT_DUPLICATE_ATTEMPT && priorCount>0)
        {
         int index=FindIndex(idempotencyKey);
         return CSubmissionGatewayResult::DuplicateReplay(m_lastResults[index]);
        }

      if(priorCount>0)
        {
         int index=FindIndex(idempotencyKey);
         return CSubmissionGatewayResult::DuplicateReplay(m_lastResults[index]);
        }

      switch(scenario)
        {
         case BRE_SIM_SUBMIT_REJECT_BEFORE_ACK:
           {
            CSubmissionGatewayResult rejected=CSubmissionGatewayResult::Rejected("simulated broker rejected before acknowledgement");
            RememberResult(idempotencyKey,rejected);
            return rejected;
           }
         case BRE_SIM_SUBMIT_ACCEPT_UNKNOWN:
           {
            CSubmissionGatewayResult unknown=CSubmissionGatewayResult::Unknown("simulated broker returned unknown outcome");
            RememberResult(idempotencyKey,unknown);
            return unknown;
           }
         case BRE_SIM_SUBMIT_STALE_ENVELOPE:
           {
            CSubmissionGatewayResult rejected=CSubmissionGatewayResult::Rejected("simulated stale envelope rejection");
            RememberResult(idempotencyKey,rejected);
            return rejected;
           }
         case BRE_SIM_SUBMIT_EXPIRED_ENVELOPE:
           {
            CSubmissionGatewayResult rejected=CSubmissionGatewayResult::Rejected("simulated expired envelope rejection");
            RememberResult(idempotencyKey,rejected);
            return rejected;
           }
         default:
           {
            ulong brokerRequestId=AllocateBrokerRequestId();
            CSubmissionGatewayResult accepted=CSubmissionGatewayResult::Accepted(brokerRequestId,"simulated submit accepted");
            RememberResult(idempotencyKey,accepted);
            return accepted;
           }
        }
     }

   void              Clear(void)
     {
      ArrayResize(m_idempotencyKeys,0);
      ArrayResize(m_scenarios,0);
      ArrayResize(m_submitCounts,0);
      ArrayResize(m_lastResults,0);
      m_nextBrokerRequestId=900000;
     }
  };

#endif
