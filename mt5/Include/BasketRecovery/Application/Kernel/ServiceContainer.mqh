#ifndef BASKET_RECOVERY_APPLICATION_SERVICE_CONTAINER_MQH
#define BASKET_RECOVERY_APPLICATION_SERVICE_CONTAINER_MQH

#include <BasketRecovery/Application/Ports/ILogger.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/ICommandQueue.mqh>
#include <BasketRecovery/Application/Ports/IEventBus.mqh>
#include <BasketRecovery/Application/Ports/ITradeRequestQueue.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Ports/IConfigurationProfileLoader.mqh>
#include <BasketRecovery/Application/Ports/IBrokerReconciliationService.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Ports/ICommandSource.mqh>
#include <BasketRecovery/Domain/StateMachine/ITransitionRuleRegistry.mqh>
#include <BasketRecovery/Application/Configuration/EAConfiguration.mqh>
#include <BasketRecovery/Application/Services/CommandIngestionService.mqh>

class CServiceContainer
  {
private:
   ILogger                       *m_logger;
   IClock                        *m_clock;
   ICommandQueue                 *m_commandQueue;
   IEventBus                     *m_eventBus;
   ITradeRequestQueue            *m_tradeRequestQueue;
   IPositionSnapshotStore        *m_snapshotStore;
   IConfigurationProfileLoader   *m_profileLoader;
   ITransitionRuleRegistry       *m_transitionRuleRegistry;
   IBrokerReconciliationService  *m_reconciliationService;
   IUniqueIdGenerator            *m_uniqueIdGenerator;
   ICommandSource                *m_commandSource;
   CCommandIngestionService      *m_commandIngestionService;
   CEAConfiguration               m_eaConfiguration;

   bool                           m_ownsLogger;
   bool                           m_ownsClock;
   bool                           m_ownsCommandQueue;
   bool                           m_ownsEventBus;
   bool                           m_ownsTradeRequestQueue;
   bool                           m_ownsSnapshotStore;
   bool                           m_ownsProfileLoader;
   bool                           m_ownsTransitionRuleRegistry;
   bool                           m_ownsReconciliationService;
   bool                           m_ownsUniqueIdGenerator;
   bool                           m_ownsCommandSource;
   bool                           m_ownsCommandIngestionService;

public:
                     CServiceContainer(void)
     {
      m_logger=NULL;
      m_clock=NULL;
      m_commandQueue=NULL;
      m_eventBus=NULL;
      m_tradeRequestQueue=NULL;
      m_snapshotStore=NULL;
      m_profileLoader=NULL;
      m_transitionRuleRegistry=NULL;
      m_reconciliationService=NULL;
      m_uniqueIdGenerator=NULL;
      m_commandSource=NULL;
      m_commandIngestionService=NULL;
      m_ownsLogger=false;
      m_ownsClock=false;
      m_ownsCommandQueue=false;
      m_ownsEventBus=false;
      m_ownsTradeRequestQueue=false;
      m_ownsSnapshotStore=false;
      m_ownsProfileLoader=false;
      m_ownsTransitionRuleRegistry=false;
      m_ownsReconciliationService=false;
      m_ownsUniqueIdGenerator=false;
      m_ownsCommandSource=false;
      m_ownsCommandIngestionService=false;
     }

                    ~CServiceContainer(void)
     {
      Shutdown();
     }

   void              RegisterLogger(ILogger *logger,const bool takeOwnership)
     {
      m_logger=logger;
      m_ownsLogger=takeOwnership;
     }

   void              RegisterClock(IClock *clock,const bool takeOwnership)
     {
      m_clock=clock;
      m_ownsClock=takeOwnership;
     }

   void              RegisterCommandQueue(ICommandQueue *commandQueue,const bool takeOwnership)
     {
      m_commandQueue=commandQueue;
      m_ownsCommandQueue=takeOwnership;
     }

   void              RegisterEventBus(IEventBus *eventBus,const bool takeOwnership)
     {
      m_eventBus=eventBus;
      m_ownsEventBus=takeOwnership;
     }

   void              RegisterTradeRequestQueue(ITradeRequestQueue *tradeRequestQueue,const bool takeOwnership)
     {
      m_tradeRequestQueue=tradeRequestQueue;
      m_ownsTradeRequestQueue=takeOwnership;
     }

   void              RegisterSnapshotStore(IPositionSnapshotStore *snapshotStore,const bool takeOwnership)
     {
      m_snapshotStore=snapshotStore;
      m_ownsSnapshotStore=takeOwnership;
     }

   void              RegisterProfileLoader(IConfigurationProfileLoader *profileLoader,const bool takeOwnership)
     {
      m_profileLoader=profileLoader;
      m_ownsProfileLoader=takeOwnership;
     }

   void              RegisterTransitionRuleRegistry(ITransitionRuleRegistry *transitionRuleRegistry,const bool takeOwnership)
     {
      m_transitionRuleRegistry=transitionRuleRegistry;
      m_ownsTransitionRuleRegistry=takeOwnership;
     }

   void              RegisterReconciliationService(IBrokerReconciliationService *reconciliationService,const bool takeOwnership)
     {
      m_reconciliationService=reconciliationService;
      m_ownsReconciliationService=takeOwnership;
     }

   void              RegisterUniqueIdGenerator(IUniqueIdGenerator *uniqueIdGenerator,const bool takeOwnership)
     {
      m_uniqueIdGenerator=uniqueIdGenerator;
      m_ownsUniqueIdGenerator=takeOwnership;
     }

   void              RegisterCommandSource(ICommandSource *commandSource,const bool takeOwnership)
     {
      m_commandSource=commandSource;
      m_ownsCommandSource=takeOwnership;
     }

   void              RegisterCommandIngestionService(CCommandIngestionService *service,const bool takeOwnership)
     {
      m_commandIngestionService=service;
      m_ownsCommandIngestionService=takeOwnership;
     }

   void              SetEAConfiguration(const CEAConfiguration &configuration) { m_eaConfiguration=configuration; }

   ILogger*                      Logger(void) const { return m_logger; }
   IClock*                       Clock(void) const { return m_clock; }
   ICommandQueue*                CommandQueue(void) const { return m_commandQueue; }
   IEventBus*                    EventBus(void) const { return m_eventBus; }
   ITradeRequestQueue*           TradeRequestQueue(void) const { return m_tradeRequestQueue; }
   IPositionSnapshotStore*       SnapshotStore(void) const { return m_snapshotStore; }
   IConfigurationProfileLoader*  ProfileLoader(void) const { return m_profileLoader; }
   ITransitionRuleRegistry*      TransitionRuleRegistry(void) const { return m_transitionRuleRegistry; }
   IBrokerReconciliationService* ReconciliationService(void) const { return m_reconciliationService; }
   IUniqueIdGenerator*           UniqueIdGenerator(void) const { return m_uniqueIdGenerator; }
   ICommandSource*               CommandSource(void) const { return m_commandSource; }
   CCommandIngestionService*     CommandIngestionService(void) const { return m_commandIngestionService; }
   CEAConfiguration              EAConfiguration(void) const { return m_eaConfiguration; }

   void              Shutdown(void)
     {
      if(m_ownsLogger && m_logger!=NULL) { delete m_logger; m_logger=NULL; }
      if(m_ownsClock && m_clock!=NULL) { delete m_clock; m_clock=NULL; }
      if(m_ownsCommandQueue && m_commandQueue!=NULL) { delete m_commandQueue; m_commandQueue=NULL; }
      if(m_ownsEventBus && m_eventBus!=NULL) { delete m_eventBus; m_eventBus=NULL; }
      if(m_ownsTradeRequestQueue && m_tradeRequestQueue!=NULL) { delete m_tradeRequestQueue; m_tradeRequestQueue=NULL; }
      if(m_ownsSnapshotStore && m_snapshotStore!=NULL) { delete m_snapshotStore; m_snapshotStore=NULL; }
      if(m_ownsProfileLoader && m_profileLoader!=NULL) { delete m_profileLoader; m_profileLoader=NULL; }
      if(m_ownsTransitionRuleRegistry && m_transitionRuleRegistry!=NULL) { delete m_transitionRuleRegistry; m_transitionRuleRegistry=NULL; }
      if(m_ownsReconciliationService && m_reconciliationService!=NULL) { delete m_reconciliationService; m_reconciliationService=NULL; }
      if(m_ownsUniqueIdGenerator && m_uniqueIdGenerator!=NULL) { delete m_uniqueIdGenerator; m_uniqueIdGenerator=NULL; }
      if(m_ownsCommandIngestionService && m_commandIngestionService!=NULL) { delete m_commandIngestionService; m_commandIngestionService=NULL; }
      if(m_ownsCommandSource && m_commandSource!=NULL) { delete m_commandSource; m_commandSource=NULL; }
     }
  };

#endif
