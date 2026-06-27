#ifndef BASKET_RECOVERY_DOMAIN_BASKET_METADATA_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_METADATA_MQH

#include <BasketRecovery/Shared/Types/UtcTime.mqh>
#include <BasketRecovery/Shared/Types/Money.mqh>

class CBasketMetadata
  {
private:
   CUtcTime m_createdAtUtc;
   CUtcTime m_updatedAtUtc;
   CMoney   m_realizedProfit;
   string   m_closeReason;

public:
                     CBasketMetadata(void) {}

   CUtcTime          CreatedAtUtc(void) const { return m_createdAtUtc; }
   CUtcTime          UpdatedAtUtc(void) const { return m_updatedAtUtc; }
   CMoney            RealizedProfit(void) const { return m_realizedProfit; }
   string            CloseReason(void) const { return m_closeReason; }

   void              SetCreatedAtUtc(const CUtcTime &value) { m_createdAtUtc=value; }
   void              SetUpdatedAtUtc(const CUtcTime &value) { m_updatedAtUtc=value; }
   void              SetRealizedProfit(const CMoney &value) { m_realizedProfit=value; }
   void              SetCloseReason(const string value) { m_closeReason=value; }
  };

#endif
