#ifndef BASKET_RECOVERY_APPLICATION_STRATEGY_COMMANDS_MQH
#define BASKET_RECOVERY_APPLICATION_STRATEGY_COMMANDS_MQH

#include <BasketRecovery/Application/Commands/StrategyCommandBase.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/CloseMode.mqh>

class CEvaluateStrategyCommand : public CStrategyCommandBase
  {
public:
                     CEvaluateStrategyCommand(void) { SetType(BRE_COMMAND_EVALUATE_STRATEGY); }
  };

class COpenRecoveryPositionCommand : public CStrategyCommandBase
  {
private:
   int    m_stepIndex;
   double m_lotSize;

public:
                     COpenRecoveryPositionCommand(void)
     {
      SetType(BRE_COMMAND_OPEN_RECOVERY_POSITION);
      m_stepIndex=0;
      m_lotSize=0.0;
     }

   int                 StepIndex(void) const { return m_stepIndex; }
   double              LotSize(void) const { return m_lotSize; }
   void                SetStepIndex(const int value) { m_stepIndex=value; }
   void                SetLotSize(const double value) { m_lotSize=value; }
  };

class CClosePositionsCommand : public CStrategyCommandBase
  {
private:
   string              m_levelId;
   double              m_closePercent;
   ENUM_BRE_CLOSE_MODE m_closeMode;
   bool                m_partialClose;

public:
                     CClosePositionsCommand(void)
     {
      SetType(BRE_COMMAND_CLOSE_POSITIONS);
      m_levelId="";
      m_closePercent=0.0;
      m_closeMode=BRE_CLOSE_MODE_NONE;
      m_partialClose=false;
     }

   string              LevelId(void) const { return m_levelId; }
   double              ClosePercent(void) const { return m_closePercent; }
   ENUM_BRE_CLOSE_MODE CloseMode(void) const { return m_closeMode; }
   bool                PartialClose(void) const { return m_partialClose; }
   void                SetLevelId(const string value) { m_levelId=value; }
   void                SetClosePercent(const double value) { m_closePercent=value; }
   void                SetCloseMode(const ENUM_BRE_CLOSE_MODE value) { m_closeMode=value; }
   void                SetPartialClose(const bool value) { m_partialClose=value; }
  };

class CMoveBasketStopLossCommand : public CStrategyCommandBase
  {
private:
   string m_ruleId;
   double m_stopLossPrice;

public:
                     CMoveBasketStopLossCommand(void)
     {
      SetType(BRE_COMMAND_MOVE_BASKET_STOP_LOSS);
      m_ruleId="";
      m_stopLossPrice=0.0;
     }

   string              RuleId(void) const { return m_ruleId; }
   double              StopLossPrice(void) const { return m_stopLossPrice; }
   void                SetRuleId(const string value) { m_ruleId=value; }
   void                SetStopLossPrice(const double value) { m_stopLossPrice=value; }
  };

class CDisableRecoveryCommand : public CStrategyCommandBase
  {
public:
                     CDisableRecoveryCommand(void) { SetType(BRE_COMMAND_DISABLE_RECOVERY); }
  };

class CReduceBasketRiskCommand : public CStrategyCommandBase
  {
private:
   double m_closePercent;

public:
                     CReduceBasketRiskCommand(void)
     {
      SetType(BRE_COMMAND_REDUCE_BASKET_RISK);
      m_closePercent=0.0;
     }

   double              ClosePercent(void) const { return m_closePercent; }
   void                SetClosePercent(const double value) { m_closePercent=value; }
  };

class CMarkProfitLevelCompletedCommand : public CStrategyCommandBase
  {
private:
   string m_levelId;
   double m_realizedProfit;

public:
                     CMarkProfitLevelCompletedCommand(void)
     {
      SetType(BRE_COMMAND_MARK_PROFIT_LEVEL_COMPLETED);
      m_levelId="";
      m_realizedProfit=0.0;
     }

   string              LevelId(void) const { return m_levelId; }
   double              RealizedProfit(void) const { return m_realizedProfit; }
   void                SetLevelId(const string value) { m_levelId=value; }
   void                SetRealizedProfit(const double value) { m_realizedProfit=value; }
  };

#endif
