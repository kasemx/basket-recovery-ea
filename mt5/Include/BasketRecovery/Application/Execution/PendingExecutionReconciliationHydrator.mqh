#ifndef BRE_APP_PENDING_EXECUTION_RECONCILIATION_HYDRATOR_MQH
#define BRE_APP_PENDING_EXECUTION_RECONCILIATION_HYDRATOR_MQH

#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionEnvelope.mqh>
#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>

class CPendingExecutionReconciliationHydrator
  {
public:
   static bool       TryHydrate(CPendingExecutionEntry &entry,IPendingExecutionStore *store)
     {
      if(store==NULL || entry.IdempotencyKey()=="")
         return false;

      CResult<CBrokerSubmissionEnvelope> envelopeResult=store.FindEnvelopeByIdempotencyKey(entry.IdempotencyKey());
      if(envelopeResult.IsFail())
         return false;

      CBrokerSubmissionEnvelope envelope;
      if(!envelopeResult.TryGetValue(envelope))
         return false;

      CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
      if(envelope.MagicNumber()>0)
         broker.SetMagicNumber(envelope.MagicNumber());
      if(envelope.Symbol()!="")
         broker.SetSymbol(envelope.Symbol());
      if(envelope.Ticket()>0)
         broker.SetPositionTicket(envelope.Ticket());
      entry.SetBrokerCorrelation(broker);

      if(entry.SubmittedAtUtc()<=0)
        {
         if(entry.PreparedAtUtc()>0)
            entry.SetSubmittedAtUtc(entry.PreparedAtUtc());
         else if(envelope.PreparedAtUtc()>0)
            entry.SetSubmittedAtUtc(envelope.PreparedAtUtc());
        }

      if(entry.CreatedAtUtc()<=0 && entry.PreparedAtUtc()>0)
         entry.SetCreatedAtUtc(entry.PreparedAtUtc());

      return true;
     }
  };

#endif
