#ifndef BRE_DOMAIN_RISK_REDUCTION_PLAN_ENTRY_MQH
#define BRE_DOMAIN_RISK_REDUCTION_PLAN_ENTRY_MQH

class CRiskReductionPlanEntry
  {
private:
   ulong  m_ticket;
   double m_requestedVolume;
   double m_estimatedRiskReductionMoney;

public:
                     CRiskReductionPlanEntry(void)
     {
      m_ticket=0;
      m_requestedVolume=0.0;
      m_estimatedRiskReductionMoney=0.0;
     }

   ulong             Ticket(void) const { return m_ticket; }
   double            RequestedVolume(void) const { return m_requestedVolume; }
   double            EstimatedRiskReductionMoney(void) const { return m_estimatedRiskReductionMoney; }

   static CRiskReductionPlanEntry Create(const ulong ticket,
                                         const double requestedVolume,
                                         const double estimatedRiskReductionMoney)
     {
      CRiskReductionPlanEntry entry;
      entry.m_ticket=ticket;
      entry.m_requestedVolume=requestedVolume;
      entry.m_estimatedRiskReductionMoney=estimatedRiskReductionMoney;
      return entry;
     }
  };

#endif
