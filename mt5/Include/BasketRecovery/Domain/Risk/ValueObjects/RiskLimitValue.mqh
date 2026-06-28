#ifndef BRE_DOMAIN_RISK_LIMIT_VALUE_MQH
#define BRE_DOMAIN_RISK_LIMIT_VALUE_MQH

#include <BasketRecovery/Domain/Risk/Enums/RiskLimitMode.mqh>

class CRiskLimitValue
  {
private:
   ENUM_BRE_RISK_LIMIT_MODE m_mode;
   double                   m_value;

public:
                     CRiskLimitValue(void)
     {
      m_mode=BRE_RISK_LIMIT_PERCENT_EQUITY;
      m_value=0.0;
     }

   ENUM_BRE_RISK_LIMIT_MODE Mode(void) const { return m_mode; }
   double            Value(void) const { return m_value; }

   static CRiskLimitValue Create(const ENUM_BRE_RISK_LIMIT_MODE mode,const double value)
     {
      CRiskLimitValue limit;
      limit.m_mode=mode;
      limit.m_value=value;
      return limit;
     }

   static CRiskLimitValue PercentEquity(const double pct)
     {
      return Create(BRE_RISK_LIMIT_PERCENT_EQUITY,pct);
     }

   static CRiskLimitValue Money(const double amount)
     {
      return Create(BRE_RISK_LIMIT_MONEY,amount);
     }
  };

#endif
