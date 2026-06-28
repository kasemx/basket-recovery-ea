#ifndef BRE_DOMAIN_ACCOUNT_EXECUTION_ELIGIBILITY_SNAPSHOT_MQH
#define BRE_DOMAIN_ACCOUNT_EXECUTION_ELIGIBILITY_SNAPSHOT_MQH

#include <BasketRecovery/Domain/Execution/AccountExecutionEligibilityClassification.mqh>

class CAccountExecutionEligibilitySnapshot
  {
private:
   ENUM_BRE_ACCOUNT_EXECUTION_ELIGIBILITY_CLASSIFICATION m_classification;
   bool                    m_accountTradeAllowed;
   bool                    m_terminalTradeAllowed;
   bool                    m_chartExpertTradeAllowed;
   string                  m_accountServer;
   string                  m_accountName;
   long                    m_accountLogin;
   double                  m_balance;
   double                  m_equity;

public:
                     CAccountExecutionEligibilitySnapshot(void)
     {
      m_classification=BRE_ACCOUNT_ELIGIBILITY_UNKNOWN;
      m_accountTradeAllowed=false;
      m_terminalTradeAllowed=false;
      m_chartExpertTradeAllowed=false;
      m_accountLogin=0;
      m_balance=0.0;
      m_equity=0.0;
     }

   ENUM_BRE_ACCOUNT_EXECUTION_ELIGIBILITY_CLASSIFICATION Classification(void) const { return m_classification; }
   bool              AccountTradeAllowed(void) const { return m_accountTradeAllowed; }
   bool              TerminalTradeAllowed(void) const { return m_terminalTradeAllowed; }
   bool              ChartExpertTradeAllowed(void) const { return m_chartExpertTradeAllowed; }
   string            AccountServer(void) const { return m_accountServer; }
   string            AccountName(void) const { return m_accountName; }
   long              AccountLogin(void) const { return m_accountLogin; }
   double            Balance(void) const { return m_balance; }
   double            Equity(void) const { return m_equity; }

   void              SetClassification(const ENUM_BRE_ACCOUNT_EXECUTION_ELIGIBILITY_CLASSIFICATION value) { m_classification=value; }
   void              SetAccountTradeAllowed(const bool value) { m_accountTradeAllowed=value; }
   void              SetTerminalTradeAllowed(const bool value) { m_terminalTradeAllowed=value; }
   void              SetChartExpertTradeAllowed(const bool value) { m_chartExpertTradeAllowed=value; }
   void              SetAccountServer(const string value) { m_accountServer=value; }
   void              SetAccountName(const string value) { m_accountName=value; }
   void              SetAccountLogin(const long value) { m_accountLogin=value; }
   void              SetBalance(const double value) { m_balance=value; }
   void              SetEquity(const double value) { m_equity=value; }

   bool              IsExplicitDemo(void) const { return m_classification==BRE_ACCOUNT_ELIGIBILITY_DEMO; }
  };

#endif
