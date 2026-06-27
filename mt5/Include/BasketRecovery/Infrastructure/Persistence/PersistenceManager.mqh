#ifndef BASKET_RECOVERY_INFRASTRUCTURE_PERSISTENCE_MANAGER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_PERSISTENCE_MANAGER_MQH

#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileCommandPersistence.mqh>
#include <BasketRecovery/Infrastructure/Persistence/PersistentCommandQueue.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileIdempotencyPersistence.mqh>
#include <BasketRecovery/Infrastructure/Persistence/PersistenceSaveQueue.mqh>
#include <BasketRecovery/Infrastructure/Idempotency/InMemoryIdempotencyStore.mqh>
#include <BasketRecovery/Application/Ports/IIdempotencyStore.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CPersistenceManager
  {
private:
   CFileBasketRepository       *m_basketRepository;
   CFileCommandPersistence     *m_commandPersistence;
   CPersistentCommandQueue     *m_commandQueue;
   CFileIdempotencyPersistence *m_idempotencyPersistence;
   CInMemoryIdempotencyStore   *m_idempotencyStore;
   CPersistenceSaveQueue       *m_saveQueue;
   bool                         m_recoveryMode;

public:
                     CPersistenceManager(const bool recoveryMode=false,const int debounceMs=500)
     {
      m_recoveryMode=recoveryMode;
      m_basketRepository=new CFileBasketRepository(BRE_PERSISTENCE_BASKET_SUBDIR,recoveryMode);
      m_commandPersistence=new CFileCommandPersistence(BRE_PERSISTENCE_PENDING_COMMANDS_FILE,recoveryMode);
      m_commandQueue=new CPersistentCommandQueue(m_commandPersistence);
      m_idempotencyPersistence=new CFileIdempotencyPersistence(BRE_PERSISTENCE_IDEMPOTENCY_FILE,recoveryMode);
      m_idempotencyStore=new CInMemoryIdempotencyStore(m_idempotencyPersistence);
      m_saveQueue=new CPersistenceSaveQueue(debounceMs);
     }

                    ~CPersistenceManager(void)
     {
      if(m_saveQueue!=NULL) delete m_saveQueue;
      if(m_idempotencyStore!=NULL) delete m_idempotencyStore;
      if(m_commandQueue!=NULL) delete m_commandQueue;
      if(m_idempotencyPersistence!=NULL) delete m_idempotencyPersistence;
      if(m_commandPersistence!=NULL) delete m_commandPersistence;
      if(m_basketRepository!=NULL) delete m_basketRepository;
     }

   void              SetRecoveryMode(const bool value)
     {
      m_recoveryMode=value;
      if(m_basketRepository!=NULL)
         m_basketRepository.SetRecoveryMode(value);
      if(m_commandPersistence!=NULL)
         m_commandPersistence.SetRecoveryMode(value);
      if(m_idempotencyPersistence!=NULL)
         m_idempotencyPersistence.SetRecoveryMode(value);
     }

   IBasketRepository&            BasketRepository(void) { return *m_basketRepository; }
   ICommandQueue&                CommandQueue(void) { return *m_commandQueue; }
   IIdempotencyStore&            IdempotencyStore(void) { return *m_idempotencyStore; }
   IIdempotencyPersistence&      IdempotencyPersistence(void) { return *m_idempotencyPersistence; }
   CPersistenceSaveQueue&        SaveQueue(void) { return *m_saveQueue; }

   CVoidResult       QueueSaveBasket(const CBasketAggregate &aggregate)
     {
      m_saveQueue.QueueSave(aggregate);
      return CVoidResult::Ok();
     }

   CVoidResult       SaveBasketImmediate(const CBasketAggregate &aggregate)
     {
      return m_basketRepository.Save(aggregate);
     }

   CResult<CBasketAggregate> LoadBasket(const CBasketId &basketId) const
     {
      return m_basketRepository.Load(basketId);
     }

   CVoidResult       DeleteBasket(const CBasketId &basketId)
     {
      return m_basketRepository.Delete(basketId);
     }

   int               LoadAllBaskets(CBasketAggregate &aggregates[]) const
     {
      return m_basketRepository.LoadAll(aggregates);
     }

   CVoidResult       Flush(void)
     {
      if(m_saveQueue.HasPending())
        {
         CVoidResult flushResult=m_saveQueue.Flush(*m_basketRepository);
         if(flushResult.IsFail())
            return flushResult;
        }
      return CVoidResult::Ok();
     }

   CVoidResult       FlushIfDue(void)
     {
      if(m_saveQueue.ShouldFlush())
         return Flush();
      return CVoidResult::Ok();
     }

   CVoidResult       RecoverOnStartup(void)
     {
      CVoidResult commandRecover=m_commandQueue.RecoverFromPersistence();
      if(commandRecover.IsFail())
         return commandRecover;

      CVoidResult idempotencyRecover=m_idempotencyStore.RecoverFromPersistence();
      if(idempotencyRecover.IsFail())
         return idempotencyRecover;

      return CVoidResult::Ok();
     }
  };

#endif
