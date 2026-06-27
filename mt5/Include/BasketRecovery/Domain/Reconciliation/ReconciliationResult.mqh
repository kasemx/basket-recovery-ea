#ifndef BRE_DOMAIN_RECONCILIATION_RESULT_MQH
#define BRE_DOMAIN_RECONCILIATION_RESULT_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Reconciliation/OrphanPositionReport.mqh>
#include <BasketRecovery/Domain/Reconciliation/MissingPositionReport.mqh>
#include <BasketRecovery/Domain/Reconciliation/PositionMismatchReport.mqh>

class CReconciliationResult
  {
private:
   CBasketId                  m_basketId;
   COrphanPositionReport      m_orphans[];
   CMissingPositionReport     m_missing[];
   CPositionMismatchReport    m_mismatches[];
   bool                       m_requiresSuspension;

public:
                     CReconciliationResult(void) { m_requiresSuspension=false; }

   CBasketId                  BasketId(void) const { return m_basketId; }
   int                        OrphanCount(void) const { return ArraySize(m_orphans); }
   int                        MissingCount(void) const { return ArraySize(m_missing); }
   int                        MismatchCount(void) const { return ArraySize(m_mismatches); }
   bool                       RequiresSuspension(void) const { return m_requiresSuspension; }
   bool                       HasIssues(void) const
     {
      return OrphanCount()>0 || MissingCount()>0 || MismatchCount()>0;
     }

   bool                       OrphanAt(const int index,COrphanPositionReport &outReport) const
     {
      if(index<0 || index>=OrphanCount())
         return false;
      outReport=m_orphans[index];
      return true;
     }

   bool                       MissingAt(const int index,CMissingPositionReport &outReport) const
     {
      if(index<0 || index>=MissingCount())
         return false;
      outReport=m_missing[index];
      return true;
     }

   bool                       MismatchAt(const int index,CPositionMismatchReport &outReport) const
     {
      if(index<0 || index>=MismatchCount())
         return false;
      outReport=m_mismatches[index];
      return true;
     }

   void                       AddOrphan(const COrphanPositionReport &report)
     {
      int count=OrphanCount();
      ArrayResize(m_orphans,count+1);
      m_orphans[count]=report;
     }

   void                       AddMissing(const CMissingPositionReport &report)
     {
      int count=MissingCount();
      ArrayResize(m_missing,count+1);
      m_missing[count]=report;
     }

   void                       AddMismatch(const CPositionMismatchReport &report)
     {
      int count=MismatchCount();
      ArrayResize(m_mismatches,count+1);
      m_mismatches[count]=report;
     }

   void                       SetRequiresSuspension(const bool value) { m_requiresSuspension=value; }

   static CReconciliationResult Create(const CBasketId &basketId)
     {
      CReconciliationResult result;
      result.m_basketId=basketId;
      return result;
     }
  };

#endif
