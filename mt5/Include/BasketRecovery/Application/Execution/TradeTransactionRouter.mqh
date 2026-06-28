#ifndef BRE_APP_TRADE_TRANSACTION_ROUTER_MQH
#define BRE_APP_TRADE_TRANSACTION_ROUTER_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionTransactionApplicator.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionCorrelationMatcher.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionDiagnostics.mqh>
#include <BasketRecovery/Application/Execution/InMemoryPendingExecutionEventBuffer.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionLifecycleService.mqh>
#include <BasketRecovery/Application/FastPath/BasketFastStateRegistry.mqh>
#include <BasketRecovery/Application/FastPath/ForceReevaluationFlag.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Domain/Execution/BrokerCommentStamp.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionResultCode.mqh>

class CTradeTransactionRouter
  {
private:
   CPendingExecutionRegistry            *m_registry;
   CPendingExecutionDiagnostics         *m_diagnostics;
   CInMemoryPendingExecutionEventBuffer *m_eventBuffer;
   CBasketFastStateRegistry             *m_fastStateRegistry;
   IClock                               *m_clock;
   CPendingExecutionLifecycleService    *m_lifecycle;

   void              MarkForceReevaluate(const CBasketId &basketId,const datetime occurredAtUtc)
     {
      if(m_fastStateRegistry==NULL || basketId.IsEmpty())
         return;
      CBasketFastState state=m_fastStateRegistry.GetOrCreate(basketId);
      CForceReevaluationFlag::Set(state,true);
      if(occurredAtUtc>0)
         state.SetLastTransactionUtc(occurredAtUtc);
      m_fastStateRegistry.Save(basketId,state);
     }

   void              EmitEvent(const string executionRequestId,
                               const ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE code,
                               const string detail)
     {
      if(m_eventBuffer==NULL)
         return;
      CPendingExecutionEvent event;
      event.SetExecutionRequestId(executionRequestId);
      event.SetResultCode(code);
      event.SetDetail(detail);
      if(m_clock!=NULL)
         event.SetOccurredAtUtc(m_clock.Now());
      m_eventBuffer.Append(event);
     }

public:
                     CTradeTransactionRouter(CPendingExecutionRegistry *registry,
                                             CPendingExecutionDiagnostics *diagnostics,
                                             CInMemoryPendingExecutionEventBuffer *eventBuffer,
                                             CBasketFastStateRegistry *fastStateRegistry,
                                             IClock *clock,
                                             CPendingExecutionLifecycleService *lifecycle=NULL)
     {
      m_registry=registry;
      m_diagnostics=diagnostics;
      m_eventBuffer=eventBuffer;
      m_fastStateRegistry=fastStateRegistry;
      m_clock=clock;
      m_lifecycle=lifecycle;
     }

   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE Route(const CTradeTransactionCorrelationContext &context)
     {
      if(m_registry==NULL)
         return BRE_TRADE_TX_RESULT_UNRELATED;

      if(m_diagnostics!=NULL)
         m_diagnostics.OnTransactionNormalized(context.TransactionKey(),
                                               TradeTransactionTypeLabel(context.TransactionType()));

      if(StringFind(context.Comment(),"BRE|")==0 && !CBrokerCommentStamp::ValidateChecksum(context.Comment()))
        {
         if(m_diagnostics!=NULL)
            m_diagnostics.OnUnrelatedTransaction(context.TransactionKey());
         return BRE_TRADE_TX_RESULT_UNRELATED;
        }

      if(context.CorrelationToken()=="" && StringFind(context.Comment(),"BRE|")==0)
        {
         if(m_diagnostics!=NULL)
            m_diagnostics.OnUnrelatedTransaction(context.TransactionKey());
         return BRE_TRADE_TX_RESULT_UNRELATED;
        }

      CPendingExecutionEntry priceProbe;
      priceProbe.SetSymbol(context.Symbol());
      priceProbe.SetRequestedVolume(context.Volume());
      if(CPendingExecutionCorrelationMatcher::MatchesPriceOnly(priceProbe,context))
        {
         if(m_diagnostics!=NULL)
            m_diagnostics.OnUnrelatedTransaction(context.TransactionKey());
         return BRE_TRADE_TX_RESULT_UNRELATED;
        }

      ENUM_BRE_CORRELATION_MATCH_STRATEGY strategy=BRE_CORRELATION_MATCH_NONE;
      int index=m_registry.TryCorrelate(context,strategy);
      if(index<0)
        {
         if(m_diagnostics!=NULL)
            m_diagnostics.OnUnrelatedTransaction(context.TransactionKey());
         return BRE_TRADE_TX_RESULT_UNRELATED;
        }

      CPendingExecutionEntry entry;
      if(!m_registry.TryGetEntry(index,entry))
         return BRE_TRADE_TX_RESULT_UNRELATED;

      if(m_diagnostics!=NULL)
         m_diagnostics.OnCorrelationMatch(entry.ExecutionRequestId(),strategy);

      if(m_registry.IsDuplicateTransaction(context.TransactionKey()))
        {
         if(m_diagnostics!=NULL)
            m_diagnostics.OnDuplicateTransaction(entry.ExecutionRequestId(),context.TransactionKey());
         EmitEvent(entry.ExecutionRequestId(),BRE_TRADE_TX_RESULT_DUPLICATE,"duplicate");
         return BRE_TRADE_TX_RESULT_DUPLICATE;
        }

      ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus=entry.Status();
      ENUM_BRE_TRADE_EXECUTION_STATUS proposedStatus=fromStatus;
      ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE applyResult=
         CPendingExecutionTransactionApplicator::Apply(entry,context,proposedStatus);

      if(applyResult==BRE_TRADE_TX_RESULT_OUT_OF_ORDER)
        {
         if(m_diagnostics!=NULL)
            m_diagnostics.OnOutOfOrderTransaction(entry.ExecutionRequestId(),context.TransactionKey());
         EmitEvent(entry.ExecutionRequestId(),BRE_TRADE_TX_RESULT_OUT_OF_ORDER,"out_of_order");
         return BRE_TRADE_TX_RESULT_OUT_OF_ORDER;
        }

      if(applyResult==BRE_TRADE_TX_RESULT_ACCEPTED || applyResult==BRE_TRADE_TX_RESULT_RECONCILED)
        {
         entry.SetCorrelationState(CPendingExecutionCorrelationMatcher::ToCorrelationState(strategy));
         m_registry.TryUpdateEntry(index,entry);
         m_registry.MarkTransactionProcessed(context.TransactionKey());
         if(m_lifecycle!=NULL)
            m_lifecycle.OnTransactionTransitionAccepted(entry,fromStatus);
         if(m_diagnostics!=NULL)
            m_diagnostics.OnTransitionAccepted(entry.ExecutionRequestId(),fromStatus,entry.Status());
         MarkForceReevaluate(entry.BasketId(),context.OccurredAtUtc());
         EmitEvent(entry.ExecutionRequestId(),applyResult,TradeExecutionStatusLabel(entry.Status()));
         if(m_diagnostics!=NULL)
            m_diagnostics.OnRouteResult(entry.ExecutionRequestId(),applyResult);
         return applyResult;
        }

      if(m_diagnostics!=NULL)
         m_diagnostics.OnTransitionRejected(entry.ExecutionRequestId(),"apply_failed");
      return BRE_TRADE_TX_RESULT_REJECTED;
     }
  };

#endif
