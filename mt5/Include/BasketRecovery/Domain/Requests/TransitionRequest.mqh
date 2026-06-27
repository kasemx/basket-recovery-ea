#ifndef BASKET_RECOVERY_DOMAIN_TRANSITION_REQUEST_MQH
#define BASKET_RECOVERY_DOMAIN_TRANSITION_REQUEST_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/EventType.mqh>
#include <BasketRecovery/Domain/ValueObjects/SignalDetails.mqh>
#include <BasketRecovery/Shared/Types/Price.mqh>

enum ENUM_BRE_TRANSITION_REQUEST_KIND
  {
   BRE_TRANSITION_REQUEST_LIFECYCLE=0,
   BRE_TRANSITION_REQUEST_SIGNAL_DETAILS,
   BRE_TRANSITION_REQUEST_STOP_LOSS,
   BRE_TRANSITION_REQUEST_TAKE_PROFIT,
   BRE_TRANSITION_REQUEST_CLOSE
  };

class CTransitionRequest
  {
private:
   ENUM_BRE_TRANSITION_REQUEST_KIND m_kind;
   CBasketId                        m_basketId;
   CCommandId                       m_commandId;
   CEventId                         m_eventId;
   ENUM_BRE_EVENT_TYPE              m_triggerEvent;
   CSignalDetails                   m_signalDetails;
   CPrice                           m_stopLoss;
   string                           m_closeReason;
   bool                             m_hasSignalDetails;
   bool                             m_hasStopLoss;

public:
                     CTransitionRequest(void)
     {
      m_kind=BRE_TRANSITION_REQUEST_LIFECYCLE;
      m_triggerEvent=BRE_EVENT_NONE;
      m_closeReason="";
      m_hasSignalDetails=false;
      m_hasStopLoss=false;
     }

   ENUM_BRE_TRANSITION_REQUEST_KIND Kind(void) const { return m_kind; }
   CBasketId                        BasketId(void) const { return m_basketId; }
   CCommandId                       CommandId(void) const { return m_commandId; }
   CEventId                         EventId(void) const { return m_eventId; }
   ENUM_BRE_EVENT_TYPE              TriggerEvent(void) const { return m_triggerEvent; }
   CSignalDetails                   SignalDetailsPayload(void) const { return m_signalDetails; }
   CPrice                           StopLoss(void) const { return m_stopLoss; }
   string                           CloseReason(void) const { return m_closeReason; }
   bool                             HasSignalDetails(void) const { return m_hasSignalDetails; }
   bool                             HasStopLoss(void) const { return m_hasStopLoss; }

   void                             SetKind(const ENUM_BRE_TRANSITION_REQUEST_KIND value) { m_kind=value; }
   void                             SetBasketId(const CBasketId &value) { m_basketId=value; }
   void                             SetCommandId(const CCommandId &value) { m_commandId=value; }
   void                             SetEventId(const CEventId &value) { m_eventId=value; }
   void                             SetTriggerEvent(const ENUM_BRE_EVENT_TYPE value) { m_triggerEvent=value; }
   void                             SetSignalDetailsPayload(const CSignalDetails &value) { m_signalDetails=value; m_hasSignalDetails=true; }
   void                             SetStopLoss(const CPrice &value) { m_stopLoss=value; m_hasStopLoss=true; }
   void                             SetCloseReason(const string value) { m_closeReason=value; }

   static CTransitionRequest        ForLifecycle(const CBasketId &basketId,
                                                 const CCommandId &commandId,
                                                 const CEventId &eventId,
                                                 const ENUM_BRE_EVENT_TYPE triggerEvent)
     {
      CTransitionRequest request;
      request.SetKind(BRE_TRANSITION_REQUEST_LIFECYCLE);
      request.SetBasketId(basketId);
      request.SetCommandId(commandId);
      request.SetEventId(eventId);
      request.SetTriggerEvent(triggerEvent);
      return request;
     }

   static CTransitionRequest        ForClose(const CBasketId &basketId,
                                             const CCommandId &commandId,
                                             const CEventId &eventId,
                                             const string closeReason)
     {
      CTransitionRequest request=ForLifecycle(basketId,commandId,eventId,BRE_EVENT_CLOSE_BASKET_REQUESTED);
      request.SetKind(BRE_TRANSITION_REQUEST_CLOSE);
      request.SetCloseReason(closeReason);
      return request;
     }
  };

#endif
