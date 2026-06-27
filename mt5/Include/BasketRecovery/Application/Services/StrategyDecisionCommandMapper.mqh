#ifndef BRE_APP_STRATEGY_DECISION_CMD_MAPPER_MQH
#define BRE_APP_STRATEGY_DECISION_CMD_MAPPER_MQH

#include <BasketRecovery/Application/Commands/ICommand.mqh>
#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecisionSet.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/StrategyDecisionType.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class CStrategyDecisionCommandMapper
  {
private:
   string            m_mappedKeys[];
   int               m_mappedKeyCount;

   bool              HasMappedKey(const string key) const
     {
      for(int i=0;i<m_mappedKeyCount;i++)
        {
         if(m_mappedKeys[i]==key)
            return true;
        }
      return false;
     }

   void              RememberKey(const string key)
     {
      if(key=="" || HasMappedKey(key))
         return;
      ArrayResize(m_mappedKeys,m_mappedKeyCount+1);
      m_mappedKeys[m_mappedKeyCount]=key;
      m_mappedKeyCount++;
     }

   ICommand*         MapDecision(const CStrategyDecision &decision,
                                 const CBasketId &basketId,
                                 const long expectedBasketVersion,
                                 const string strategyProfileHash,
                                 const string correlationId) const
     {
      string idempotencyKey=decision.IdempotencyKey();
      if(idempotencyKey=="" || HasMappedKey(idempotencyKey))
         return NULL;

      switch(decision.Type())
        {
         case BRE_STRATEGY_DECISION_OPEN_RECOVERY:
           {
            COpenRecoveryPositionDecision openDecision=decision.OpenRecovery();
            COpenRecoveryPositionCommand *command=new COpenRecoveryPositionCommand();
            command.SetBasketId(basketId);
            command.SetCorrelationKey(correlationId);
            command.SetExpectedBasketVersion(expectedBasketVersion);
            command.SetStrategyProfileHash(strategyProfileHash);
            command.SetIdempotencyKey(idempotencyKey);
            command.SetStepIndex(openDecision.StepIndex());
            command.SetLotSize(openDecision.Lot());
            return command;
           }
         case BRE_STRATEGY_DECISION_CLOSE_POSITIONS:
           {
            CClosePositionsDecision closeDecision=decision.ClosePositions();
            CClosePositionsCommand *command=new CClosePositionsCommand();
            command.SetBasketId(basketId);
            command.SetCorrelationKey(correlationId);
            command.SetExpectedBasketVersion(expectedBasketVersion);
            command.SetStrategyProfileHash(strategyProfileHash);
            command.SetIdempotencyKey(idempotencyKey);
            command.SetLevelId(closeDecision.LevelId());
            command.SetClosePercent(closeDecision.ClosePercent());
            command.SetCloseMode(closeDecision.CloseMode());
            command.SetPartialClose(closeDecision.PartialClose());
            return command;
           }
         case BRE_STRATEGY_DECISION_MOVE_BREAK_EVEN:
           {
            CMoveBreakEvenDecision beDecision=decision.MoveBreakEven();
            CMoveBasketStopLossCommand *command=new CMoveBasketStopLossCommand();
            command.SetBasketId(basketId);
            command.SetCorrelationKey(correlationId);
            command.SetExpectedBasketVersion(expectedBasketVersion);
            command.SetStrategyProfileHash(strategyProfileHash);
            command.SetIdempotencyKey(idempotencyKey);
            command.SetRuleId(beDecision.RuleId());
            command.SetStopLossPrice(beDecision.UseOffset() ? beDecision.SlOffsetPips() : beDecision.BufferPips());
            return command;
           }
         case BRE_STRATEGY_DECISION_DISABLE_RECOVERY:
           {
            CDisableRecoveryCommand *command=new CDisableRecoveryCommand();
            command.SetBasketId(basketId);
            command.SetCorrelationKey(correlationId);
            command.SetExpectedBasketVersion(expectedBasketVersion);
            command.SetStrategyProfileHash(strategyProfileHash);
            command.SetIdempotencyKey(idempotencyKey);
            return command;
           }
         case BRE_STRATEGY_DECISION_REDUCE_RISK:
           {
            CReduceRiskDecision riskDecision=decision.ReduceRisk();
            CReduceBasketRiskCommand *command=new CReduceBasketRiskCommand();
            command.SetBasketId(basketId);
            command.SetCorrelationKey(correlationId);
            command.SetExpectedBasketVersion(expectedBasketVersion);
            command.SetStrategyProfileHash(strategyProfileHash);
            command.SetIdempotencyKey(idempotencyKey);
            command.SetClosePercent(0.0);
            return command;
           }
         default:
            return NULL;
        }
     }

public:
                     CStrategyDecisionCommandMapper(void)
     {
      m_mappedKeyCount=0;
      ArrayResize(m_mappedKeys,0);
     }

   CResult<int>      MapDecisionSet(const CStrategyDecisionSet &decisionSet,
                                     const CBasketId &basketId,
                                     const long expectedBasketVersion,
                                     const string strategyProfileHash,
                                     const string correlationId,
                                     ICommand* &outCommands[])
     {
      if(strategyProfileHash=="")
         return CResult<int>::Fail(BRE_ERR_STRATEGY_HASH_MISMATCH,"Strategy profile hash is required");

      int mappedCount=0;
      int decisionCount=decisionSet.Count();
      for(int i=0;i<decisionCount;i++)
        {
         CStrategyDecision decision=decisionSet.DecisionAt(i);
         if(decision.Type()==BRE_STRATEGY_DECISION_NO_ACTION)
            continue;

         string idempotencyKey=decision.IdempotencyKey();
         if(HasMappedKey(idempotencyKey))
            continue;

         ICommand *command=MapDecision(decision,basketId,expectedBasketVersion,strategyProfileHash,correlationId);
         if(command==NULL)
            continue;

         ArrayResize(outCommands,mappedCount+1);
         outCommands[mappedCount]=command;
         mappedCount++;
         RememberKey(idempotencyKey);
        }
      return CResult<int>::Ok(mappedCount);
     }
  };

#endif
