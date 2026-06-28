#ifndef BRE_DOMAIN_RISK_CALCULATION_CONTEXT_MQH
#define BRE_DOMAIN_RISK_CALCULATION_CONTEXT_MQH

#include <BasketRecovery/Domain/Risk/ValueObjects/RiskCalculationSettings.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskLimitProfile.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Market/AccountContextSnapshot.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CRiskCalculationContext
  {
private:
   string                    m_accountCurrency;
   double                    m_contractSize;
   double                    m_basketStopLoss;
   ENUM_BRE_TRADE_DIRECTION  m_basketDirection;
   CRiskLimitProfile         m_riskProfile;
   CRiskCalculationSettings  m_settings;
   CMarketQuote              m_quote;
   CAccountContextSnapshot   m_account;

public:
                     CRiskCalculationContext(void)
     {
      m_accountCurrency="";
      m_contractSize=0.0;
      m_basketStopLoss=0.0;
      m_basketDirection=BRE_DIRECTION_NONE;
     }

   string            AccountCurrency(void) const { return m_accountCurrency; }
   double            ContractSize(void) const { return m_contractSize; }
   double            BasketStopLoss(void) const { return m_basketStopLoss; }
   ENUM_BRE_TRADE_DIRECTION BasketDirection(void) const { return m_basketDirection; }
   CRiskLimitProfile RiskProfile(void) const { return m_riskProfile; }
   CRiskCalculationSettings Settings(void) const { return m_settings; }
   CMarketQuote      Quote(void) const { return m_quote; }
   CAccountContextSnapshot Account(void) const { return m_account; }

   static CRiskCalculationContext Create(const CAccountContextSnapshot &account,
                                         const CMarketQuote &quote,
                                         const CRiskLimitProfile &riskProfile,
                                         const double basketStopLoss,
                                         const ENUM_BRE_TRADE_DIRECTION basketDirection,
                                         const CRiskCalculationSettings &settings,
                                         const string accountCurrency="",
                                         const double contractSize=0.0)
     {
      CRiskCalculationContext context;
      context.m_account=account;
      context.m_quote=quote;
      context.m_riskProfile=riskProfile;
      context.m_basketStopLoss=basketStopLoss;
      context.m_basketDirection=basketDirection;
      context.m_settings=settings;
      context.m_accountCurrency=accountCurrency;
      context.m_contractSize=contractSize;
      return context;
     }
  };

#endif
