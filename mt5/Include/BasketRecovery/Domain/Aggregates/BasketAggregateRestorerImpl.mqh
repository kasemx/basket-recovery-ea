#ifndef BASKET_RECOVERY_DOMAIN_BASKET_AGGREGATE_RESTORER_IMPL_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_AGGREGATE_RESTORER_IMPL_MQH

#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregateRestorer.mqh>

bool CBasketAggregateRestorer::Restore(CBasketAggregate &aggregate,const CBasketPersistenceDto &dto)
  {
   if(dto.basketId.IsEmpty())
      return false;

   aggregate.ClearForRestore();
   aggregate.SetIdentity(dto.basketId,dto.correlationKey,dto.direction,dto.symbol);
   aggregate.SetLifecycleState(dto.lifecycleState);
   aggregate.SetModeFlagsFromDto(dto);
   aggregate.SetLegacyProfileSnapshot(dto.hasProfileSnapshot,dto.profileName,dto.risk,dto.recovery,
                                      dto.takeProfit,dto.breakEven,dto.execution,dto.profileBoundAt);

   if(dto.hasStrategySnapshot && dto.strategyCanonicalJson!="")
     {
      CStrategyProfileJsonParser parser;
      CResult<CStrategyProfile> profileResult=parser.Parse(dto.strategyCanonicalJson,dto.strategyBoundAtUtc);
      if(profileResult.IsOk())
        {
         CStrategyProfile profile;
         profileResult.TryGetValue(profile);
         CStrategyProfileSnapshot snapshot=CStrategyProfileSnapshot::Create(profile,
                                                                            dto.strategyCanonicalJson,
                                                                            dto.strategyProfileHash,
                                                                            dto.strategyBoundAtUtc);
         aggregate.RestoreStrategyBinding(snapshot,dto.strategyMigrationRequired);
        }
      else
         aggregate.RestoreStrategyBinding(CStrategyProfileSnapshot::CreateUnbound(),true);
     }
   else
      aggregate.RestoreStrategyBinding(CStrategyProfileSnapshot::CreateUnbound(),
                                       dto.strategyMigrationRequired || !dto.hasStrategySnapshot);

   CBasketProfitLevelProgress levels[];
   int levelCount=ArraySize(dto.profitLevelProgress);
   ArrayResize(levels,levelCount);
   for(int i=0;i<levelCount;i++)
     {
      if(dto.profitLevelProgress[i].reached)
        {
         levels[i]=CBasketProfitLevelProgress::CreateReached(dto.profitLevelProgress[i].levelId,
                                                             CUtcTime((datetime)dto.profitLevelProgress[i].reachedAtUtc),
                                                             CCommandId(dto.profitLevelProgress[i].executionCommandId),
                                                             CEventId(dto.profitLevelProgress[i].executionEventId));
        }
      else
         levels[i]=CBasketProfitLevelProgress::CreateEmpty(dto.profitLevelProgress[i].levelId);
     }
   aggregate.RestoreProfitLevels(levels,levelCount);
   aggregate.RestoreExecutedBreakEvenRules(dto.executedBreakEvenRuleIds);
   aggregate.SetVersionState(dto.version,dto.lastCommandId,dto.lastEventId,dto.lastModifiedUtc);
   aggregate.SetSignalFromDto(dto);
   aggregate.SetMetadataFromDto(dto);
   aggregate.SetPositionSnapshotsFromDto(dto);
   aggregate.SetAuditHistoryFromDto(dto);
   return true;
  }

#endif
