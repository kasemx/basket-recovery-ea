#ifndef BRE_APP_MANUAL_RECOVERY_CANDIDATE_REGISTRY_MQH
#define BRE_APP_MANUAL_RECOVERY_CANDIDATE_REGISTRY_MQH

#include <BasketRecovery/Domain/Execution/ValueObjects/ManualRecoveryCandidateEntry.mqh>
#include <BasketRecovery/Domain/Execution/Enums/ManualRecoveryCandidateRegistryStatus.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>

class CManualRecoveryCandidateRegistry
  {
private:
   CManualRecoveryCandidateEntry m_entries[];
   string                        m_indexByCandidateId[];

   int               FindIndex(const string candidateId) const
     {
      for(int i=0;i<ArraySize(m_entries);i++)
        {
         if(m_entries[i].CandidateId()==candidateId)
            return i;
        }
      return -1;
     }

   bool              HasActiveForStep(const CBasketId &basketId,const int stepIndex) const
     {
      for(int i=0;i<ArraySize(m_entries);i++)
        {
         if(m_entries[i].BasketId().Value()!=basketId.Value())
            continue;
         if(m_entries[i].RecoveryStepIndex()!=stepIndex)
            continue;
         ENUM_BRE_MANUAL_RECOVERY_CANDIDATE_REGISTRY_STATUS status=m_entries[i].Status();
         if(status==BRE_MANUAL_RECOVERY_CANDIDATE_AVAILABLE ||
            status==BRE_MANUAL_RECOVERY_CANDIDATE_SELECTED ||
            status==BRE_MANUAL_RECOVERY_CANDIDATE_SUBMITTED)
            return true;
        }
      return false;
     }

public:
   bool              TryRegister(const CManualRecoveryCandidateEntry &entry)
     {
      if(entry.CandidateId()=="")
         return false;
      if(FindIndex(entry.CandidateId())>=0)
         return false;
      if(HasActiveForStep(entry.BasketId(),entry.RecoveryStepIndex()))
         return false;

      int size=ArraySize(m_entries);
      ArrayResize(m_entries,size+1);
      m_entries[size]=entry;
      return true;
     }

   bool              TryGetByCandidateId(const string candidateId,CManualRecoveryCandidateEntry &entry) const
     {
      int index=FindIndex(candidateId);
      if(index<0)
         return false;
      entry=m_entries[index];
      return true;
     }

   bool              TryGetByExecutionRequestId(const string executionRequestId,CManualRecoveryCandidateEntry &entry) const
     {
      for(int i=0;i<ArraySize(m_entries);i++)
        {
         if(m_entries[i].ExecutionRequestId()==executionRequestId)
           {
            entry=m_entries[i];
            return true;
           }
        }
      return false;
     }

   bool              TryUpdateStatus(const string candidateId,
                                     const ENUM_BRE_MANUAL_RECOVERY_CANDIDATE_REGISTRY_STATUS status)
     {
      int index=FindIndex(candidateId);
      if(index<0)
         return false;
      m_entries[index].SetStatus(status);
      return true;
     }

   int               ExpireStale(const datetime nowUtc)
     {
      int expiredCount=0;
      for(int i=0;i<ArraySize(m_entries);i++)
        {
         if(m_entries[i].Status()!=BRE_MANUAL_RECOVERY_CANDIDATE_AVAILABLE &&
            m_entries[i].Status()!=BRE_MANUAL_RECOVERY_CANDIDATE_SELECTED)
            continue;
         if(!m_entries[i].IsExpired(nowUtc))
            continue;
         m_entries[i].SetStatus(BRE_MANUAL_RECOVERY_CANDIDATE_EXPIRED);
         expiredCount++;
        }
      return expiredCount;
     }

   int               CountAvailable(void) const
     {
      int count=0;
      for(int i=0;i<ArraySize(m_entries);i++)
        {
         if(m_entries[i].Status()==BRE_MANUAL_RECOVERY_CANDIDATE_AVAILABLE)
            count++;
        }
      return count;
     }

   void              Clear(void) { ArrayResize(m_entries,0); }
  };

#endif
