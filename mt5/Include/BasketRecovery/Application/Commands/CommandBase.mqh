#ifndef BASKET_RECOVERY_APPLICATION_COMMAND_BASE_MQH
#define BASKET_RECOVERY_APPLICATION_COMMAND_BASE_MQH

#include <BasketRecovery/Application/Commands/ICommand.mqh>

class CCommandBase : public ICommand
  {
protected:
   CCommandId              m_id;
   ENUM_BRE_COMMAND_TYPE   m_type;
   string                  m_idempotencyKey;
   CBasketId               m_basketId;
   string                  m_correlationKey;
   ENUM_BRE_COMMAND_STATUS m_status;
   int                     m_priority;
   string                  m_source;
   datetime                m_enqueuedAt;
   int                     m_retryCount;

public:
                     CCommandBase(void)
     {
      m_type=BRE_COMMAND_NONE;
      m_idempotencyKey="";
      m_correlationKey="";
      m_status=BRE_COMMAND_STATUS_PENDING;
      m_priority=10;
      m_source="INTERNAL";
      m_enqueuedAt=0;
      m_retryCount=0;
     }

   virtual          ~CCommandBase(void) {}

   virtual ENUM_BRE_COMMAND_TYPE Type(void) const { return m_type; }
   virtual CCommandId          Id(void) const { return m_id; }
   virtual string              IdempotencyKey(void) const { return m_idempotencyKey; }
   virtual CBasketId           BasketId(void) const { return m_basketId; }
   virtual string              CorrelationKey(void) const { return m_correlationKey; }
   virtual ENUM_BRE_COMMAND_STATUS Status(void) const { return m_status; }
   virtual int                 Priority(void) const { return m_priority; }
   virtual string              Source(void) const { return m_source; }
   virtual datetime            EnqueuedAt(void) const { return m_enqueuedAt; }

   int                         RetryCount(void) const { return m_retryCount; }

   void                        SetId(const CCommandId &value) { m_id=value; }
   void                        SetType(const ENUM_BRE_COMMAND_TYPE value) { m_type=value; }
   void                        SetIdempotencyKey(const string value) { m_idempotencyKey=value; }
   void                        SetBasketId(const CBasketId &value) { m_basketId=value; }
   void                        SetCorrelationKey(const string value) { m_correlationKey=value; }
   void                        SetStatus(const ENUM_BRE_COMMAND_STATUS value) { m_status=value; }
   void                        SetPriority(const int value) { m_priority=value; }
   void                        SetSource(const string value) { m_source=value; }
   void                        SetEnqueuedAt(const datetime value) { m_enqueuedAt=value; }
   void                        SetRetryCount(const int value) { m_retryCount=value; }
  };

#endif
