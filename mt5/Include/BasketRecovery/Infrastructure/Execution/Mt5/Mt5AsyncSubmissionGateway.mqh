#ifndef BRE_INF_MT5_ASYNC_SUBMISSION_GATEWAY_MQH
#define BRE_INF_MT5_ASYNC_SUBMISSION_GATEWAY_MQH

#include <BasketRecovery/Application/Execution/Ports/ISubmissionGateway.mqh>
#include <BasketRecovery/Application/Execution/LiveSubmissionSafetyGate.mqh>
#include <BasketRecovery/Application/Execution/LiveSubmissionSafetyGateContext.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/IMt5AsyncOrderSendTransport.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5EnvelopeTradeRequestTranslator.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionResult.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionDiagnostics.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>

class CMt5LiveAsyncOrderSendTransport : public IMt5AsyncOrderSendTransport
  {
public:
   virtual bool      SendAsync(MqlTradeRequest &request,MqlTradeResult &result)
     {
      ZeroMemory(result);
      return OrderSendAsync(request,result);
     }
  };

class CMt5AsyncSubmissionGateway : public ISubmissionGateway
  {
private:
   IMt5AsyncOrderSendTransport      *m_transport;
   CMt5EnvelopeTradeRequestTranslator m_translator;
   CMt5AsyncSubmissionDiagnostics   *m_diagnostics;
   CLiveSubmissionSafetyGateContext  m_attemptContext;
   CPendingExecutionRegistry        *m_attemptRegistry;
   bool                              m_attemptActive;
   bool                              m_brokerInvoked;
   int                               m_slippagePoints;
   CMt5AsyncSubmissionResult         m_lastAsyncResult;

public:
                     CMt5AsyncSubmissionGateway(IMt5AsyncOrderSendTransport *transport,
                                                CMt5AsyncSubmissionDiagnostics *diagnostics=NULL,
                                                const int slippagePoints=10)
     {
      m_diagnostics=diagnostics;
      m_transport=transport;
      m_attemptRegistry=NULL;
      m_attemptActive=false;
      m_brokerInvoked=false;
      m_slippagePoints=slippagePoints;
     }

   virtual bool      IsSimulated(void) const { return false; }

   bool              WasBrokerInvoked(void) const { return m_brokerInvoked; }
   CMt5AsyncSubmissionResult LastAsyncResult(void) const { return m_lastAsyncResult; }

   void              BeginSubmissionAttempt(const CLiveSubmissionSafetyGateContext &context,
                                              CPendingExecutionRegistry *registry)
     {
      m_attemptContext=context;
      m_attemptRegistry=registry;
      m_attemptActive=true;
      m_brokerInvoked=false;
     }

   void              EndSubmissionAttempt(void)
     {
      m_attemptActive=false;
      m_attemptRegistry=NULL;
     }

   virtual CSubmissionGatewayResult Submit(const CBrokerSubmissionEnvelope &envelope)
     {
      m_lastAsyncResult=CMt5AsyncSubmissionResult();
      if(!m_attemptActive)
         return CSubmissionGatewayResult::Rejected("Async submission attempt context is not active");

      if(envelope.IntentType()!=BRE_EXEC_INTENT_OPEN_POSITION)
         return CSubmissionGatewayResult::Rejected("Only OPEN_POSITION is supported for demo manual submission");

      ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON safetyReason=BRE_LIVE_SAFETY_NONE;
      string safetyDetail="";
      if(!CLiveSubmissionSafetyGate::Evaluate(m_attemptContext,m_attemptRegistry,safetyReason,safetyDetail))
        {
         if(m_diagnostics!=NULL)
            m_diagnostics.OnSafetyGateBlocked(envelope.ExecutionRequestId(),safetyReason,safetyDetail);
         return CSubmissionGatewayResult::Rejected(StringFormat("Safety gate blocked: %s",safetyDetail));
        }

      if(m_transport==NULL)
         return CSubmissionGatewayResult::Rejected("Async order send transport is not configured");

      CMarketQuote quote=m_attemptContext.Quote();
      MqlTradeRequest request;
      string translateError="";
      if(!m_translator.TryTranslateOpenMarketDeal(envelope,
                                                  quote.Bid(),
                                                  quote.Ask(),
                                                  m_slippagePoints,
                                                  request,
                                                  translateError))
         return CSubmissionGatewayResult::Rejected(translateError);

      MqlTradeResult asyncResult;
      m_brokerInvoked=true;
      bool accepted=m_transport.SendAsync(request,asyncResult);
      if(accepted)
         m_lastAsyncResult.SetAccepted(asyncResult.retcode,asyncResult.order,"OrderSendAsync accepted");
      else
         m_lastAsyncResult.SetRejected(GetLastError(),asyncResult.retcode,"OrderSendAsync rejected");

      if(m_diagnostics!=NULL)
         m_diagnostics.OnOrderSendAsyncAttempt(envelope,accepted,m_lastAsyncResult);

      if(!accepted)
         return CSubmissionGatewayResult::Rejected(StringFormat("OrderSendAsync=false retcode=%u last_error=%d",
                                                                asyncResult.retcode,
                                                                m_lastAsyncResult.LastError()));

      ulong brokerOrderId=asyncResult.order;
      return CSubmissionGatewayResult::Accepted(brokerOrderId,"OrderSendAsync transport accepted");
     }
  };

#endif
