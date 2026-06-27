#ifndef BRE_APP_SIMULATED_BROKER_SUBMISSION_INJECTOR_MQH
#define BRE_APP_SIMULATED_BROKER_SUBMISSION_INJECTOR_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionTestInjectionService.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionAcknowledgement.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionType.mqh>
#include <BasketRecovery/Shared/DTOs/NormalizedTradeTransaction.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionCorrelationContext.mqh>

class CSimulatedBrokerSubmissionInjector
  {
private:
   CPendingExecutionRegistry             *m_registry;
   CPendingExecutionTestInjectionService *m_injection;

   bool              TryLoadEntry(const string executionRequestId,CPendingExecutionEntry &entry) const
     {
      if(m_registry==NULL)
         return false;
      return m_registry.TryGetByExecutionRequestId(executionRequestId,entry);
     }

   CNormalizedTradeTransaction BuildTransaction(const CPendingExecutionEntry &entry,
                                                const ENUM_BRE_TRADE_TRANSACTION_TYPE txType,
                                                const ulong orderId,
                                                const ulong dealId,
                                                const double volume) const
     {
      CNormalizedTradeTransaction tx;
      tx.SetSymbol(entry.Symbol());
      tx.SetComment(entry.BrokerComment());
      tx.SetVolume(volume);
      tx.SetOrderId(orderId);
      tx.SetDealId(dealId);
      return tx;
     }

public:
                     CSimulatedBrokerSubmissionInjector(CPendingExecutionRegistry *registry,
                                                        CPendingExecutionTestInjectionService *injection)
     {
      m_registry=registry;
      m_injection=injection;
     }

   CBrokerSubmissionAcknowledgement BuildAcknowledgement(const string executionRequestId,
                                                         const ulong brokerOrderId,
                                                         const datetime acknowledgedAtUtc) const
     {
      CBrokerSubmissionAcknowledgement ack;
      CPendingExecutionEntry entry;
      if(TryLoadEntry(executionRequestId,entry))
        {
         ack.SetExecutionRequestId(executionRequestId);
         ack.SetIdempotencyKey(entry.IdempotencyKey());
         ack.SetBrokerOrderId(brokerOrderId);
         ack.SetBrokerRequestId(entry.BrokerCorrelation().BrokerOrderId());
         ack.SetAcknowledgedAtUtc(acknowledgedAtUtc);
        }
      return ack;
     }

   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE InjectAcknowledgement(const string executionRequestId,
                                                                const ulong brokerOrderId,
                                                                const long magicNumber)
     {
      CPendingExecutionEntry entry;
      if(!TryLoadEntry(executionRequestId,entry))
         return BRE_TRADE_TX_RESULT_UNRELATED;
      CNormalizedTradeTransaction tx=BuildTransaction(entry,BRE_TRADE_TX_TYPE_ORDER_ADD,brokerOrderId,0,entry.RequestedVolume());
      return m_injection.InjectNormalizedTransaction(tx,magicNumber);
     }

   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE InjectPartialFill(const string executionRequestId,
                                                            const ulong dealId,
                                                            const double volume,
                                                            const long magicNumber)
     {
      CPendingExecutionEntry entry;
      if(!TryLoadEntry(executionRequestId,entry))
         return BRE_TRADE_TX_RESULT_UNRELATED;
      CNormalizedTradeTransaction tx=BuildTransaction(entry,BRE_TRADE_TX_TYPE_DEAL_ADD,0,dealId,volume);
      return m_injection.InjectNormalizedTransaction(tx,magicNumber);
     }

   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE InjectFullFill(const string executionRequestId,
                                                         const ulong dealId,
                                                         const long magicNumber)
     {
      CPendingExecutionEntry entry;
      if(!TryLoadEntry(executionRequestId,entry))
         return BRE_TRADE_TX_RESULT_UNRELATED;
      return InjectPartialFill(executionRequestId,dealId,entry.RequestedVolume(),magicNumber);
     }

   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE InjectRejection(const string executionRequestId,
                                                          const ulong orderId,
                                                          const long magicNumber)
     {
      CPendingExecutionEntry entry;
      if(!TryLoadEntry(executionRequestId,entry))
         return BRE_TRADE_TX_RESULT_UNRELATED;
      CNormalizedTradeTransaction tx=BuildTransaction(entry,BRE_TRADE_TX_TYPE_ORDER_DELETE,orderId,0,0.0);
      return m_injection.InjectNormalizedTransaction(tx,magicNumber);
     }

   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE InjectDuplicateTransaction(const string executionRequestId,
                                                                     const ENUM_BRE_TRADE_TRANSACTION_TYPE txType,
                                                                     const ulong orderId,
                                                                     const ulong dealId,
                                                                     const double volume,
                                                                     const long magicNumber)
     {
      ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE first=InjectPartialFill(executionRequestId,dealId,volume,magicNumber);
      if(first!=BRE_TRADE_TX_RESULT_ACCEPTED && first!=BRE_TRADE_TX_RESULT_RECONCILED)
         return first;
      CPendingExecutionEntry entry;
      if(!TryLoadEntry(executionRequestId,entry))
         return BRE_TRADE_TX_RESULT_UNRELATED;
      CNormalizedTradeTransaction tx=BuildTransaction(entry,txType,orderId,dealId,volume);
      return m_injection.InjectNormalizedTransaction(tx,magicNumber);
     }
  };

#endif
