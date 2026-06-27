#ifndef BASKET_RECOVERY_INFRASTRUCTURE_IN_MEMORY_TRADE_REQUEST_QUEUE_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_IN_MEMORY_TRADE_REQUEST_QUEUE_MQH

#include <BasketRecovery/Application/Ports/ITradeRequestQueue.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CInMemoryTradeRequestQueue : public ITradeRequestQueue
  {
private:
   CTradeRequest *m_items[];
   int            m_count;

   int FindIndexByIdempotencyKey(const string idempotencyKey) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL && m_items[i].IdempotencyKey()==idempotencyKey)
            return i;
        }
      return -1;
     }

public:
                     CInMemoryTradeRequestQueue(void)
     {
      m_count=0;
      ArrayResize(m_items,0);
     }

   virtual          ~CInMemoryTradeRequestQueue(void)
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL)
           {
            delete m_items[i];
            m_items[i]=NULL;
           }
        }
     }

   virtual CVoidResult Enqueue(CTradeRequest *request)
     {
      if(request==NULL)
         return CVoidResult::Fail(BRE_ERR_TRADE_REQUEST_INVALID,"Trade request is null");

      if(FindIndexByIdempotencyKey(request.IdempotencyKey())>=0)
         return CVoidResult::Ok();

      ArrayResize(m_items,m_count+1);
      m_items[m_count]=request;
      m_count++;
      return CVoidResult::Ok();
     }

   virtual CTradeRequest* DequeueNext(void)
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL && m_items[i].Status()==BRE_TRADE_REQUEST_QUEUED)
            return m_items[i];
        }
      return NULL;
     }

   virtual CVoidResult MarkFilled(const CRequestId &requestId)
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL && m_items[i].Id().Value()==requestId.Value())
           {
            m_items[i].SetStatus(BRE_TRADE_REQUEST_FILLED);
            return CVoidResult::Ok();
           }
        }
      return CVoidResult::Fail(BRE_ERR_TRADE_REQUEST_INVALID,"Trade request not found");
     }

   virtual CVoidResult MarkRejected(const CRequestId &requestId,const int errorCode,const string &message)
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL && m_items[i].Id().Value()==requestId.Value())
           {
            m_items[i].SetStatus(BRE_TRADE_REQUEST_REJECTED);
            return CVoidResult::Fail(errorCode,message);
           }
        }
      return CVoidResult::Fail(errorCode,message);
     }

   virtual CTradeRequest* FindByIdempotencyKey(const string idempotencyKey)
     {
      int index=FindIndexByIdempotencyKey(idempotencyKey);
      if(index<0)
         return NULL;
      return m_items[index];
     }

   virtual int QueuedCount(void) const
     {
      int queued=0;
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL && m_items[i].Status()==BRE_TRADE_REQUEST_QUEUED)
            queued++;
        }
      return queued;
     }
  };

#endif
