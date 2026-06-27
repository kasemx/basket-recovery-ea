#ifndef BRE_DOMAIN_ACCOUNT_CONTEXT_SNAPSHOT_MQH
#define BRE_DOMAIN_ACCOUNT_CONTEXT_SNAPSHOT_MQH

class CAccountContextSnapshot
  {
private:
   long   m_login;
   double m_balance;
   double m_equity;
   double m_margin;
   double m_freeMargin;
   bool   m_tradeAllowed;

public:
                     CAccountContextSnapshot(void)
     {
      m_login=0;
      m_balance=0.0;
      m_equity=0.0;
      m_margin=0.0;
      m_freeMargin=0.0;
      m_tradeAllowed=false;
     }

                     CAccountContextSnapshot(const CAccountContextSnapshot &other)
     {
      m_login=other.m_login;
      m_balance=other.m_balance;
      m_equity=other.m_equity;
      m_margin=other.m_margin;
      m_freeMargin=other.m_freeMargin;
      m_tradeAllowed=other.m_tradeAllowed;
     }

   long              Login(void) const { return m_login; }
   double            Balance(void) const { return m_balance; }
   double            Equity(void) const { return m_equity; }
   double            Margin(void) const { return m_margin; }
   double            FreeMargin(void) const { return m_freeMargin; }
   bool              TradeAllowed(void) const { return m_tradeAllowed; }

   static CAccountContextSnapshot Create(const long login,
                                         const double balance,
                                         const double equity,
                                         const double margin,
                                         const double freeMargin,
                                         const bool tradeAllowed)
     {
      CAccountContextSnapshot snapshot;
      snapshot.m_login=login;
      snapshot.m_balance=balance;
      snapshot.m_equity=equity;
      snapshot.m_margin=margin;
      snapshot.m_freeMargin=freeMargin;
      snapshot.m_tradeAllowed=tradeAllowed;
      return snapshot;
     }
  };

#endif
