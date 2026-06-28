#ifndef BRE_DOMAIN_POSITION_REDUCTION_INSTRUCTION_MQH
#define BRE_DOMAIN_POSITION_REDUCTION_INSTRUCTION_MQH

class CPositionReductionInstruction
  {
private:
   ulong  m_ticket;
   double m_proposedCloseVolume;
   double m_estimatedCloseMoney;

public:
                     CPositionReductionInstruction(void)
     {
      m_ticket=0;
      m_proposedCloseVolume=0.0;
      m_estimatedCloseMoney=0.0;
     }

                     CPositionReductionInstruction(const CPositionReductionInstruction &other)
     {
      m_ticket=other.m_ticket;
      m_proposedCloseVolume=other.m_proposedCloseVolume;
      m_estimatedCloseMoney=other.m_estimatedCloseMoney;
     }

   ulong             Ticket(void) const { return m_ticket; }
   double            ProposedCloseVolume(void) const { return m_proposedCloseVolume; }
   double            EstimatedCloseMoney(void) const { return m_estimatedCloseMoney; }

   static CPositionReductionInstruction Create(const ulong ticket,
                                               const double proposedCloseVolume,
                                               const double estimatedCloseMoney)
     {
      CPositionReductionInstruction instruction;
      instruction.m_ticket=ticket;
      instruction.m_proposedCloseVolume=proposedCloseVolume;
      instruction.m_estimatedCloseMoney=estimatedCloseMoney;
      return instruction;
     }
  };

#endif
