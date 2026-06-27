#ifndef BRE_APP_TRADE_TRANSACTION_FAST_PATH_MQH
#define BRE_APP_TRADE_TRANSACTION_FAST_PATH_MQH

#include <BasketRecovery/Application/FastPath/BasketFastStateRegistry.mqh>
#include <BasketRecovery/Application/FastPath/SymbolBasketIndex.mqh>
#include <BasketRecovery/Application/FastPath/ForceReevaluationFlag.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Shared/DTOs/NormalizedTradeTransaction.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CTradeTransactionFastPathService
  {
private:
   IPositionSnapshotStore   *m_snapshotStore;
   CBasketFastStateRegistry *m_fastStateRegistry;
   CSymbolBasketIndex       *m_symbolIndex;

public:
                     CTradeTransactionFastPathService(IPositionSnapshotStore *snapshotStore,
                                                      CBasketFastStateRegistry *fastStateRegistry,
                                                      CSymbolBasketIndex *symbolIndex)
     {
      m_snapshotStore=snapshotStore;
      m_fastStateRegistry=fastStateRegistry;
      m_symbolIndex=symbolIndex;
     }

   CVoidResult       Handle(const CNormalizedTradeTransaction &transaction)
     {
      if(m_snapshotStore==NULL)
         return CVoidResult::Fail(BRE_ERR_SNAPSHOT_NOT_FOUND,"Snapshot store is required");

      CVoidResult applyResult=m_snapshotStore.ApplyNormalizedTransaction(transaction);
      if(applyResult.IsFail())
         return applyResult;

      CBasketId basketId=transaction.BasketId();
      if(basketId.IsEmpty() || m_fastStateRegistry==NULL)
         return CVoidResult::Ok();

      CBasketFastState state=m_fastStateRegistry.GetOrCreate(basketId);
      CForceReevaluationFlag::Set(state,true);
      state.SetLastTransactionUtc(transaction.OccurredAtUtc());
      m_fastStateRegistry.Save(basketId,state);

      if(m_symbolIndex!=NULL)
         m_symbolIndex.MarkDirty();

      return CVoidResult::Ok();
     }
  };

#endif
