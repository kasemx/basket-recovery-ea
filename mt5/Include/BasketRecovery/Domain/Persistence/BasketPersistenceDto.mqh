#ifndef BASKET_RECOVERY_DOMAIN_BASKET_PERSISTENCE_DTO_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_PERSISTENCE_DTO_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>
#include <BasketRecovery/Shared/Types/Money.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Configuration/RiskProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/RecoveryProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/TakeProfitProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/BreakEvenProfileConfig.mqh>
#include <BasketRecovery/Domain/Configuration/ExecutionProfileConfig.mqh>
#include <BasketRecovery/Domain/ValueObjects/AuditRecord.mqh>

struct SBasketPositionSnapshotDto
  {
   int       version;
   string    basketId;
   datetime  updatedAt;
   int       openCount;
   int       transactionCount;
  };

struct SBasketSignalDetailsDto
  {
   bool   hasDetails;
   double rangeLow;
   double rangeHigh;
   double stopLoss;
   double tp1;
   double tp2;
   double tp3;
   double tp4;
   bool   tpOpen;
  };

class CBasketPersistenceDto
  {
public:
   CBasketId                         basketId;
   string                            correlationKey;
   ENUM_BRE_TRADE_DIRECTION          direction;
   string                            symbol;
   ENUM_BRE_BASKET_LIFECYCLE_STATE   lifecycleState;
   bool                              recoveryActive;
   bool                              recoveryPermanentlyDisabled;
   bool                              riskReductionActive;
   bool                              maxRiskLockout;
   bool                              hasProfileSnapshot;
   string                            profileName;
   CRiskProfileConfig                risk;
   CRecoveryProfileConfig            recovery;
   CTakeProfitProfileConfig          takeProfit;
   CBreakEvenProfileConfig           breakEven;
   CExecutionProfileConfig           execution;
   CUtcTime                          profileBoundAt;
   long                              version;
   CCommandId                        lastCommandId;
   CEventId                          lastEventId;
   CUtcTime                          lastModifiedUtc;
   CSignalId                         signalId;
   string                            signalCorrelationKey;
   string                            signalSequence;
   ENUM_BRE_TRADE_DIRECTION          signalDirection;
   string                            signalSymbol;
   SBasketSignalDetailsDto           signalDetails;
   datetime                          signalReceivedAt;
   bool                              signalIsConsumed;
   CUtcTime                          createdAtUtc;
   CUtcTime                          updatedAtUtc;
   CMoney                            realizedProfit;
   string                            closeReason;
   SBasketPositionSnapshotDto        positionSnapshots[];
   CAuditRecord                      commandHistory[];
   CAuditRecord                      eventHistory[];
  };

#endif
