#ifndef BASKET_RECOVERY_SHARED_PRICE_MQH
#define BASKET_RECOVERY_SHARED_PRICE_MQH

class CPrice
  {
private:
   double m_value;

public:
                     CPrice(void) { m_value=0.0; }
                     CPrice(const double value) { m_value=value; }

   double            Value(void) const { return m_value; }
   void              SetValue(const double value) { m_value=value; }
   bool              IsZero(void) const { return m_value==0.0; }
  };

#endif
