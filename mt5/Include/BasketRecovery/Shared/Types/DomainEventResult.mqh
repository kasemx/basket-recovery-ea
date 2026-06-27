#ifndef BASKET_RECOVERY_SHARED_DOMAIN_EVENT_RESULT_MQH
#define BASKET_RECOVERY_SHARED_DOMAIN_EVENT_RESULT_MQH

#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Domain/Events/DomainEvent.mqh>

class CDomainEventResult
  {
public:
   bool          m_success;
   CDomainEvent *m_event;
   int           m_errorCode;
   string        m_errorMessage;
   bool          m_hasValue;

                     CDomainEventResult(void)
     {
      m_success=false;
      m_event=NULL;
      m_errorCode=BRE_ERR_NONE;
      m_errorMessage="";
      m_hasValue=false;
     }

                     CDomainEventResult(const CDomainEventResult &other)
     {
      m_success=other.m_success;
      m_event=other.m_event;
      m_errorCode=other.m_errorCode;
      m_errorMessage=other.m_errorMessage;
      m_hasValue=other.m_hasValue;
     }

   static CDomainEventResult Ok(CDomainEvent *event)
     {
      CDomainEventResult result;
      result.m_success=true;
      result.m_hasValue=true;
      result.m_event=event;
      return result;
     }

   static CDomainEventResult Fail(const int errorCode,const string message)
     {
      CDomainEventResult result;
      result.m_success=false;
      result.m_errorCode=errorCode;
      result.m_errorMessage=message;
      return result;
     }

   bool              IsOk(void) const { return m_success; }
   bool              IsFail(void) const { return !m_success; }
   int               ErrorCode(void) const { return m_errorCode; }
   string            ErrorMessage(void) const { return m_errorMessage; }
   bool              HasValue(void) const { return m_hasValue && m_success; }

   bool              TryGetEvent(CDomainEvent *&outEvent) const
     {
      if(!HasValue())
         return false;
      outEvent=m_event;
      return true;
     }
  };

#endif
