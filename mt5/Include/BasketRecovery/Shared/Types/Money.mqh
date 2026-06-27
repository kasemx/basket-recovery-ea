#ifndef BASKET_RECOVERY_SHARED_MONEY_MQH
#define BASKET_RECOVERY_SHARED_MONEY_MQH

class CMoney
  {
private:
   double m_amount;

public:
                     CMoney(void) { m_amount=0.0; }
                     CMoney(const double amount) { m_amount=amount; }

   double            Amount(void) const { return m_amount; }
   void              SetAmount(const double amount) { m_amount=amount; }

   CMoney            Add(const CMoney &other) const { return CMoney(m_amount+other.m_amount); }
   CMoney            Subtract(const CMoney &other) const { return CMoney(m_amount-other.m_amount); }

   bool              operator>(const CMoney &other) const { return m_amount>other.m_amount; }
   bool              operator>=(const CMoney &other) const { return m_amount>=other.m_amount; }
   bool              operator<(const CMoney &other) const { return m_amount<other.m_amount; }
  };

#endif
