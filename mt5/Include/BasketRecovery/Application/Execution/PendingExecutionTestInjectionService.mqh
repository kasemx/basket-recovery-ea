#ifndef BRE_APP_PENDING_EXECUTION_TEST_INJECTION_MQH
#define BRE_APP_PENDING_EXECUTION_TEST_INJECTION_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/TradeTransactionRouter.mqh>
#include <BasketRecovery/Shared/DTOs/NormalizedTradeTransaction.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5TradeTransactionAdapter.mqh>

class CPendingExecutionTestInjectionService
  {
private:
   CPendingExecutionRegistry *m_registry;
   CTradeTransactionRouter   *m_router;

public:
                     CPendingExecutionTestInjectionService(CPendingExecutionRegistry *registry,
                                                           CTradeTransactionRouter *router)
     {
      m_registry=registry;
      m_router=router;
     }

   CVoidResult       RegisterPendingEntry(const CPendingExecutionEntry &entry)
     {
      if(m_registry==NULL)
         return CVoidResult::Fail(-1,"registry unavailable");
      return m_registry.Register(entry);
     }

   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE InjectNormalizedTransaction(const CNormalizedTradeTransaction &transaction,
                                                                      const long magicNumber=0)
     {
      if(m_router==NULL)
         return BRE_TRADE_TX_RESULT_UNRELATED;
      CTradeTransactionCorrelationContext context=
         CMt5TradeTransactionAdapter::BuildContext(transaction,magicNumber);
      return m_router.Route(context);
     }

   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE InjectCorrelationContext(const CTradeTransactionCorrelationContext &context)
     {
      if(m_router==NULL)
         return BRE_TRADE_TX_RESULT_UNRELATED;
      return m_router.Route(context);
     }
  };

#endif
