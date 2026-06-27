#ifndef BRE_INF_IN_MEMORY_PENDING_EXECUTION_STORE_MQH
#define BRE_INF_IN_MEMORY_PENDING_EXECUTION_STORE_MQH

#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionPersistenceCodec.mqh>

class CInMemoryPendingExecutionStore : public IPendingExecutionStore
  {
private:
   CPendingExecutionEntry      m_entries[];
   CBrokerSubmissionEnvelope   m_envelopes[];
   string                      m_idempotencyKeys[];

   int               FindEnvelopeIndex(const string idempotencyKey) const
     {
      for(int i=0;i<ArraySize(m_idempotencyKeys);i++)
        {
         if(m_idempotencyKeys[i]==idempotencyKey)
            return i;
        }
      return -1;
     }

   int               FindEntryIndex(const string executionRequestId) const
     {
      for(int i=0;i<ArraySize(m_entries);i++)
        {
         if(m_entries[i].ExecutionRequestId()==executionRequestId)
            return i;
        }
      return -1;
     }

public:
   virtual CVoidResult SavePreparedState(const CPendingExecutionEntry &entry,
                                         const CBrokerSubmissionEnvelope &envelope)
     {
      int entryIndex=FindEntryIndex(entry.ExecutionRequestId());
      if(entryIndex<0)
        {
         int size=ArraySize(m_entries);
         ArrayResize(m_entries,size+1);
         m_entries[size]=entry;
        }
      else
        {
         m_entries[entryIndex]=entry;
        }

      int envelopeIndex=FindEnvelopeIndex(envelope.IdempotencyKey());
      if(envelopeIndex<0)
        {
         int size=ArraySize(m_envelopes);
         ArrayResize(m_envelopes,size+1);
         ArrayResize(m_idempotencyKeys,size+1);
         m_envelopes[size]=envelope;
         m_idempotencyKeys[size]=envelope.IdempotencyKey();
        }
      else
        {
         m_envelopes[envelopeIndex]=envelope;
        }
      return CVoidResult::Ok();
     }

   virtual CResult<CBrokerSubmissionEnvelope> FindEnvelopeByIdempotencyKey(const string idempotencyKey) const
     {
      int index=FindEnvelopeIndex(idempotencyKey);
      if(index<0)
         return CResult<CBrokerSubmissionEnvelope>::Fail(-1,"Envelope not found");
      return CResult<CBrokerSubmissionEnvelope>::Ok(m_envelopes[index]);
     }

   virtual int         RestoreEntries(CPendingExecutionEntry &entries[]) const
     {
      int count=ArraySize(m_entries);
      ArrayResize(entries,count);
      for(int i=0;i<count;i++)
         entries[i]=m_entries[i];
      return count;
     }

   virtual CVoidResult Clear(void)
     {
      ArrayResize(m_entries,0);
      ArrayResize(m_envelopes,0);
      ArrayResize(m_idempotencyKeys,0);
      return CVoidResult::Ok();
     }

   string            ExportEntriesText(void) const
     {
      string text="";
      for(int i=0;i<ArraySize(m_entries);i++)
        {
         if(text!="")
            text+="\n";
         text+=CPendingExecutionPersistenceCodec::EncodeEntry(m_entries[i]);
        }
      return text;
     }

   string            ExportEnvelopesText(void) const
     {
      string text="";
      for(int i=0;i<ArraySize(m_envelopes);i++)
        {
         if(text!="")
            text+="\n";
         text+=CPendingExecutionPersistenceCodec::EncodeEnvelope(m_envelopes[i]);
        }
      return text;
     }

   void              ImportEntriesText(const string text)
     {
      string lines[];
      int count=StringSplit(text,'\n',lines);
      ArrayResize(m_entries,0);
      for(int i=0;i<count;i++)
        {
         CPendingExecutionEntry entry;
         if(!CPendingExecutionPersistenceCodec::TryDecodeEntry(lines[i],entry))
            continue;
         int size=ArraySize(m_entries);
         ArrayResize(m_entries,size+1);
         m_entries[size]=entry;
        }
     }

   void              ImportEnvelopesText(const string text)
     {
      string lines[];
      int count=StringSplit(text,'\n',lines);
      ArrayResize(m_envelopes,0);
      ArrayResize(m_idempotencyKeys,0);
      for(int i=0;i<count;i++)
        {
         CBrokerSubmissionEnvelope envelope;
         if(!CPendingExecutionPersistenceCodec::TryDecodeEnvelope(lines[i],envelope))
            continue;
         int size=ArraySize(m_envelopes);
         ArrayResize(m_envelopes,size+1);
         ArrayResize(m_idempotencyKeys,size+1);
         m_envelopes[size]=envelope;
         m_idempotencyKeys[size]=envelope.IdempotencyKey();
        }
     }
  };

#endif
