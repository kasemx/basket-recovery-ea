#ifndef BRE_DOMAIN_BASKET_RISK_SNAPSHOT_MQH
#define BRE_DOMAIN_BASKET_RISK_SNAPSHOT_MQH

#include <BasketRecovery/Domain/Risk/Enums/RiskSafetyStatus.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/PositionRiskSnapshot.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>

class CBasketRiskSnapshot
  {
private:
   CBasketId                     m_basketId;
   string                        m_symbol;
   string                        m_accountCurrency;
   double                        m_accountEquity;
   double                        m_accountBalance;
   double                        m_basketStopLoss;
   double                        m_weightedAverageEntry;
   double                        m_floatingProfit;
   double                        m_currentSlRiskMoney;
   double                        m_targetRiskMoney;
   double                        m_maxRiskMoney;
   double                        m_currentRiskUtilization;
   double                        m_headroomMoney;
   bool                          m_aboveTargetRisk;
   bool                          m_atOrAboveMaxRisk;
   ENUM_BRE_RISK_SAFETY_STATUS   m_safetyStatus;
   CPositionRiskSnapshot         m_positions[];
   int                           m_positionCount;

public:
                     CBasketRiskSnapshot(void)
     {
      m_accountEquity=0.0;
      m_accountBalance=0.0;
      m_basketStopLoss=0.0;
      m_weightedAverageEntry=0.0;
      m_floatingProfit=0.0;
      m_currentSlRiskMoney=0.0;
      m_targetRiskMoney=0.0;
      m_maxRiskMoney=0.0;
      m_currentRiskUtilization=0.0;
      m_headroomMoney=0.0;
      m_aboveTargetRisk=false;
      m_atOrAboveMaxRisk=false;
      m_safetyStatus=BRE_RISK_SAFETY_UNKNOWN;
      m_positionCount=0;
     }

   CBasketId         BasketId(void) const { return m_basketId; }
   string            Symbol(void) const { return m_symbol; }
   string            AccountCurrency(void) const { return m_accountCurrency; }
   double            AccountEquity(void) const { return m_accountEquity; }
   double            AccountBalance(void) const { return m_accountBalance; }
   double            BasketStopLoss(void) const { return m_basketStopLoss; }
   double            WeightedAverageEntry(void) const { return m_weightedAverageEntry; }
   double            FloatingProfit(void) const { return m_floatingProfit; }
   double            CurrentSlRiskMoney(void) const { return m_currentSlRiskMoney; }
   double            TargetRiskMoney(void) const { return m_targetRiskMoney; }
   double            MaxRiskMoney(void) const { return m_maxRiskMoney; }
   double            CurrentRiskUtilization(void) const { return m_currentRiskUtilization; }
   double            HeadroomMoney(void) const { return m_headroomMoney; }
   bool              AboveTargetRisk(void) const { return m_aboveTargetRisk; }
   bool              AtOrAboveMaxRisk(void) const { return m_atOrAboveMaxRisk; }
   ENUM_BRE_RISK_SAFETY_STATUS SafetyStatus(void) const { return m_safetyStatus; }
   bool              IsSafe(void) const { return m_safetyStatus==BRE_RISK_SAFETY_SAFE; }
   int               PositionCount(void) const { return m_positionCount; }

   CPositionRiskSnapshot PositionAt(const int index) const
     {
      if(index<0 || index>=m_positionCount)
         return CPositionRiskSnapshot::Unknown(0,"");
      return m_positions[index];
     }

   static CBasketRiskSnapshot Unsafe(const CBasketId &basketId,const string symbol)
     {
      CBasketRiskSnapshot snapshot;
      snapshot.m_basketId=basketId;
      snapshot.m_symbol=symbol;
      snapshot.m_safetyStatus=BRE_RISK_SAFETY_UNSAFE;
      return snapshot;
     }

   static CBasketRiskSnapshot Unknown(const CBasketId &basketId,const string symbol)
     {
      CBasketRiskSnapshot snapshot;
      snapshot.m_basketId=basketId;
      snapshot.m_symbol=symbol;
      snapshot.m_safetyStatus=BRE_RISK_SAFETY_UNKNOWN;
      return snapshot;
     }

   void              SetCore(const CBasketId &basketId,
                             const string symbol,
                             const string accountCurrency,
                             const double accountEquity,
                             const double accountBalance,
                             const double basketStopLoss,
                             const double weightedAverageEntry,
                             const double floatingProfit,
                             const double currentSlRiskMoney,
                             const double targetRiskMoney,
                             const double maxRiskMoney,
                             const ENUM_BRE_RISK_SAFETY_STATUS safetyStatus)
     {
      m_basketId=basketId;
      m_symbol=symbol;
      m_accountCurrency=accountCurrency;
      m_accountEquity=accountEquity;
      m_accountBalance=accountBalance;
      m_basketStopLoss=basketStopLoss;
      m_weightedAverageEntry=weightedAverageEntry;
      m_floatingProfit=floatingProfit;
      m_currentSlRiskMoney=currentSlRiskMoney;
      m_targetRiskMoney=targetRiskMoney;
      m_maxRiskMoney=maxRiskMoney;
      m_safetyStatus=safetyStatus;
      m_headroomMoney=maxRiskMoney-currentSlRiskMoney;
      m_aboveTargetRisk=currentSlRiskMoney>targetRiskMoney;
      m_atOrAboveMaxRisk=currentSlRiskMoney>=maxRiskMoney;
      m_currentRiskUtilization=maxRiskMoney>0.0 ? currentSlRiskMoney/maxRiskMoney : 0.0;
     }

   void              SetPositions(const CPositionRiskSnapshot &positions[],const int count)
     {
      m_positionCount=count;
      ArrayResize(m_positions,count);
      for(int i=0;i<count;i++)
         m_positions[i]=positions[i];
     }
  };

#endif
