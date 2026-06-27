#ifndef BASKET_RECOVERY_DOMAIN_SIGNAL_DETAILS_MQH
#define BASKET_RECOVERY_DOMAIN_SIGNAL_DETAILS_MQH

#include <BasketRecovery/Shared/Types/Price.mqh>

class CSignalDetails
  {
private:
   CPrice m_rangeLow;
   CPrice m_rangeHigh;
   CPrice m_stopLoss;
   CPrice m_tp1;
   CPrice m_tp2;
   CPrice m_tp3;
   CPrice m_tp4;
   bool   m_tpOpen;
   bool   m_hasDetails;

public:
                     CSignalDetails(void)
     {
      m_tpOpen=false;
      m_hasDetails=false;
     }

   bool              HasDetails(void) const { return m_hasDetails; }
   CPrice            RangeLow(void) const { return m_rangeLow; }
   CPrice            RangeHigh(void) const { return m_rangeHigh; }
   CPrice            StopLoss(void) const { return m_stopLoss; }
   CPrice            Tp1(void) const { return m_tp1; }
   CPrice            Tp2(void) const { return m_tp2; }
   CPrice            Tp3(void) const { return m_tp3; }
   CPrice            Tp4(void) const { return m_tp4; }
   bool              TpOpen(void) const { return m_tpOpen; }

   void              SetHasDetails(const bool value) { m_hasDetails=value; }
   void              SetRangeLow(const CPrice &value) { m_rangeLow=value; }
   void              SetRangeHigh(const CPrice &value) { m_rangeHigh=value; }
   void              SetStopLoss(const CPrice &value) { m_stopLoss=value; }
   void              SetTp1(const CPrice &value) { m_tp1=value; }
   void              SetTp2(const CPrice &value) { m_tp2=value; }
   void              SetTp3(const CPrice &value) { m_tp3=value; }
   void              SetTp4(const CPrice &value) { m_tp4=value; }
   void              SetTpOpen(const bool value) { m_tpOpen=value; }
  };

#endif
