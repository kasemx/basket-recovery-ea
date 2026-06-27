#ifndef BASKET_RECOVERY_INTERFACES_BOOTSTRAPPER_MQH
#define BASKET_RECOVERY_INTERFACES_BOOTSTRAPPER_MQH

#include <BasketRecovery/Application/Kernel/ApplicationContext.mqh>
#include <BasketRecovery/Application/Kernel/ApplicationKernel.mqh>
#include <BasketRecovery/Application/Kernel/ServiceContainer.mqh>
#include <BasketRecovery/Application/Configuration/ProfileSnapshotFactory.mqh>
#include <BasketRecovery/Infrastructure/Configuration/Mt5ConfigurationLoader.mqh>
#include <BasketRecovery/Infrastructure/Logging/FileLogger.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5Clock.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5UniqueIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Persistence/PersistenceManager.mqh>
#include <BasketRecovery/Infrastructure/Events/InMemoryEventBus.mqh>
#include <BasketRecovery/Infrastructure/TradeRequests/InMemoryTradeRequestQueue.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/BrokerReconciliationService.mqh>
#include <BasketRecovery/Infrastructure/Configuration/DefaultProfileLoader.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestWebRequestClient.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestClient.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestClientConfig.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestCommandSource.mqh>
#include <BasketRecovery/Application/Services/CommandIngestionService.mqh>
#include <BasketRecovery/Application/Kernel/TransitionRuleRegistry.mqh>
#include <BasketRecovery/Application/Kernel/DefaultTransitionRuleTable.mqh>
#include <BasketRecovery/Domain/StateMachine/AlwaysTrueTransitionGuard.mqh>
#include <BasketRecovery/Shared/Constants/FeatureFlags.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CBootstrapper
  {
public:
   static CApplicationContext* Bootstrap(const string profileName,
                                         const string logFilePath,
                                         const int logLevel,
                                         const string accountLabel,
                                         const string apiBaseUrl,
                                         const string apiKey,
                                         const int restPollIntervalMs,
                                         const int applicationTimerIntervalMs,
                                         const int strategyEvalIntervalMs,
                                         const int maxBasketsPerEvalCycle)
     {
      CResult<CEAConfiguration> configurationResult=
         CMt5ConfigurationLoader::LoadFromInputs(profileName,logFilePath,logLevel,accountLabel,apiBaseUrl,apiKey,
                                                 restPollIntervalMs,applicationTimerIntervalMs,
                                                 strategyEvalIntervalMs,maxBasketsPerEvalCycle);

      if(configurationResult.IsFail())
        {
         Print("BasketRecovery bootstrap failed: ",configurationResult.ErrorMessage());
         return NULL;
        }

      CEAConfiguration configuration;
      if(!configurationResult.TryGetValue(configuration))
        {
         Print("BasketRecovery bootstrap failed: configuration result has no value");
         return NULL;
        }

      CFileLogger *logger=new CFileLogger();
      if(!logger.Initialize(configuration.LogFilePath(),configuration.LogLevel()))
        {
         delete logger;
         Print("BasketRecovery logger initialization failed");
         return NULL;
        }

      CMt5Clock *clock=new CMt5Clock();

      CDefaultProfileLoader *profileLoader=new CDefaultProfileLoader(clock);
      CResult<CProfileBundle> profileResult=profileLoader.LoadProfile(configuration.ProfileName());
      if(profileResult.IsFail())
        {
         logger.Error("SYSTEM","Bootstrap","","Profile load failed",profileResult.ErrorCode());
         delete profileLoader;
         delete clock;
         delete logger;
         return NULL;
        }

      CProfileBundle profileBundle;
      if(!profileResult.TryGetValue(profileBundle))
        {
         logger.Error("SYSTEM","Bootstrap","","Profile result has no value",BRE_ERR_PROFILE_LOAD_FAILED);
         delete profileLoader;
         delete clock;
         delete logger;
         return NULL;
        }

      CProfileSnapshot profileSnapshot=CProfileSnapshotFactory::FromBundle(profileBundle,*clock);

      int effectivePollIntervalMs=configuration.RestPollIntervalMs();
      if(effectivePollIntervalMs<=0)
         effectivePollIntervalMs=profileBundle.Execution().RestPollIntervalMs();
      configuration.SetRestPollIntervalMs(effectivePollIntervalMs);

      static CAlwaysTrueTransitionGuard s_defaultTransitionGuard;

      CTransitionRuleRegistry *transitionRuleRegistry=new CTransitionRuleRegistry();
      CVoidResult populateResult=
         CDefaultTransitionRuleTable::RegisterDefaultRules(*transitionRuleRegistry,&s_defaultTransitionGuard);
      if(populateResult.IsFail())
        {
         logger.Error("SYSTEM","Bootstrap","","Transition rule table population failed",populateResult.ErrorCode());
         delete transitionRuleRegistry;
         delete profileLoader;
         delete clock;
         delete logger;
         return NULL;
        }

      CVoidResult registryValidation=transitionRuleRegistry.Validate();
      if(registryValidation.IsFail())
        {
         logger.Error("SYSTEM","Bootstrap","","Transition registry validation failed",registryValidation.ErrorCode());
         delete transitionRuleRegistry;
         delete profileLoader;
         delete clock;
         delete logger;
         return NULL;
        }

      CInMemorySnapshotStore *snapshotStore=new CInMemorySnapshotStore(clock);
      CBrokerReconciliationService *reconciliationService=
         new CBrokerReconciliationService(snapshotStore,clock,logger);

      CServiceContainer *container=new CServiceContainer();
      container.RegisterLogger(logger,true);
      container.RegisterClock(clock,true);
      container.RegisterEventBus(new CInMemoryEventBus(),true);
      container.RegisterTradeRequestQueue(new CInMemoryTradeRequestQueue(),true);
      container.RegisterSnapshotStore(snapshotStore,true);
      container.RegisterProfileLoader(profileLoader,true);
      container.RegisterTransitionRuleRegistry(transitionRuleRegistry,true);
      container.RegisterReconciliationService(reconciliationService,true);
      container.RegisterUniqueIdGenerator(new CMt5UniqueIdGenerator(),true);
      container.SetEAConfiguration(configuration);

      CPersistenceManager *persistenceManager=new CPersistenceManager(false,500);
      if(persistenceManager.RecoverOnStartup().IsFail())
        {
         delete persistenceManager;
         delete container;
         return NULL;
        }
      container.RegisterCommandQueue(persistenceManager.CommandQueue(),false);

      CRestClientConfig restConfig;
      restConfig.SetBaseUrl(configuration.ApiBaseUrl());
      restConfig.SetApiKey(configuration.ApiKey());
      restConfig.SetAccountId(configuration.AccountLogin());
      restConfig.SetMt5InstanceId(IntegerToString(configuration.AccountLogin())+"-"+configuration.AccountLabel());
      restConfig.SetTimeoutMs(5000);

      CRestClient *restClient=new CRestClient(new CRestWebRequestClient(restConfig.TimeoutMs()),true);
      CRestCommandSource *commandSource=new CRestCommandSource(restClient,restConfig,true);
      CCommandIngestionService *commandIngestionService=
         new CCommandIngestionService(commandSource,persistenceManager.CommandQueue(),logger);
      container.RegisterCommandSource(commandSource,true);
      container.RegisterCommandIngestionService(commandIngestionService,true);

      CVoidResult reconciliationResult=reconciliationService.ReconcileAtStartup();
      if(reconciliationResult.IsFail())
        {
         logger.Error("SYSTEM","Bootstrap","","Startup reconciliation failed",reconciliationResult.ErrorCode());
         delete persistenceManager;
         delete container;
         return NULL;
        }

      CApplicationKernel *kernel=new CApplicationKernel();
      if(!kernel.Initialize(transitionRuleRegistry,clock,container.UniqueIdGenerator(),
                             commandIngestionService,profileSnapshot,persistenceManager,
                             effectivePollIntervalMs,configuration.StrategyEvalIntervalMs(),
                             configuration.MaxBasketsPerEvalCycle()))
        {
         delete kernel;
         delete container;
         return NULL;
        }

      CApplicationContext *context=new CApplicationContext();
      if(!context.Initialize(container,kernel))
        {
         delete context;
         delete kernel;
         delete container;
         return NULL;
        }

      logger.Info("SYSTEM","Startup",
                  "",
                  StringFormat("BasketRecoveryEA initialized | profile=%s | profile_snapshot=%s | account=%I64d | label=%s | transition_rules=%d | snapshots=%d | rest=%s | rest_poll_ms=%d | features=signals:%s",
                               configuration.ProfileName(),
                               profileSnapshot.ProfileName(),
                               configuration.AccountLogin(),
                               configuration.AccountLabel(),
                               transitionRuleRegistry.RuleCount(),
                               context.SnapshotCount(),
                               configuration.ApiBaseUrl()=="" ? "disabled" : configuration.ApiBaseUrl(),
                               effectivePollIntervalMs,
                               BRE_FEATURE_SIGNALS ? "on" : "off"));

      return context;
     }
  };

#endif
