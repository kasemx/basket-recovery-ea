#ifndef BRE_INF_MT5_ACCOUNT_EXECUTION_ELIGIBILITY_PROVIDER_MQH
#define BRE_INF_MT5_ACCOUNT_EXECUTION_ELIGIBILITY_PROVIDER_MQH

#include <BasketRecovery/Application/Execution/Ports/IAccountExecutionEligibilityProvider.mqh>

class CMt5AccountExecutionEligibilityProvider : public IAccountExecutionEligibilityProvider
  {
public:
   virtual CAccountExecutionEligibilitySnapshot Capture(void) const
     {
      CAccountExecutionEligibilitySnapshot snapshot;
      snapshot.SetAccountLogin(AccountInfoInteger(ACCOUNT_LOGIN));
      snapshot.SetAccountServer(AccountInfoString(ACCOUNT_SERVER));
      snapshot.SetAccountName(AccountInfoString(ACCOUNT_NAME));
      snapshot.SetBalance(AccountInfoDouble(ACCOUNT_BALANCE));
      snapshot.SetEquity(AccountInfoDouble(ACCOUNT_EQUITY));
      snapshot.SetAccountTradeAllowed(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)>0);
      snapshot.SetTerminalTradeAllowed(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)>0);
      snapshot.SetChartExpertTradeAllowed(MQLInfoInteger(MQL_TRADE_ALLOWED)>0);

      ENUM_ACCOUNT_TRADE_MODE tradeMode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
      if(tradeMode==ACCOUNT_TRADE_MODE_DEMO)
         snapshot.SetClassification(BRE_ACCOUNT_ELIGIBILITY_DEMO);
      else if(tradeMode==ACCOUNT_TRADE_MODE_REAL)
         snapshot.SetClassification(BRE_ACCOUNT_ELIGIBILITY_REAL);
      else
         snapshot.SetClassification(BRE_ACCOUNT_ELIGIBILITY_UNKNOWN);

      return snapshot;
     }
  };

#endif
