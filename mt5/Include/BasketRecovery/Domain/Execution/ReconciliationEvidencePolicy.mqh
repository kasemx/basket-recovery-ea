#ifndef BRE_DOMAIN_RECONCILIATION_EVIDENCE_POLICY_MQH

#define BRE_DOMAIN_RECONCILIATION_EVIDENCE_POLICY_MQH



#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>



class CReconciliationEvidencePolicy

  {

public:

   static int        DefaultEvidenceWindowSecondsAfter(void) { return 86400; }



   static int        DefaultBoundedFingerprintSecondsAfter(void) { return 600; }



   static datetime   ReconciliationAnchorUtc(const CPendingExecutionEntry &entry)

     {

      if(entry.SubmittedAtUtc()>0)

         return entry.SubmittedAtUtc();

      if(entry.PreparedAtUtc()>0)

         return entry.PreparedAtUtc();

      return entry.CreatedAtUtc();

     }



   static bool       IsEvidenceWindowElapsed(const CPendingExecutionEntry &entry,

                                             const datetime nowUtc,

                                             const int windowSecondsAfter)

     {

      datetime anchor=ReconciliationAnchorUtc(entry);

      if(anchor<=0)

         return false;



      int effectiveWindow=(windowSecondsAfter<=0 ? DefaultEvidenceWindowSecondsAfter() : windowSecondsAfter);

      datetime end=anchor+(datetime)effectiveWindow;

      if(entry.DeadlineUtc()>0)

        {

         datetime deadlineEnd=entry.DeadlineUtc()+(datetime)effectiveWindow;

         if(deadlineEnd>end)

            end=deadlineEnd;

        }

      return nowUtc>=end;

     }

   static void       ResolveHistorySelectWindow(const CPendingExecutionEntry &entry,
                                                const datetime nowUtc,
                                                const int windowSecondsBefore,
                                                const int windowSecondsAfter,
                                                datetime &fromOut,
                                                datetime &toOut)
     {
      datetime anchor=ReconciliationAnchorUtc(entry);
      if(anchor<=0)
         anchor=nowUtc;

      int before=(windowSecondsBefore<=0 ? 604800 : windowSecondsBefore);
      int after=(windowSecondsAfter<=0 ? DefaultEvidenceWindowSecondsAfter() : windowSecondsAfter);

      fromOut=anchor-(datetime)before;
      toOut=anchor+(datetime)after;
      if(nowUtc+(datetime)after>toOut)
         toOut=nowUtc+(datetime)after;
      if(entry.DeadlineUtc()>0)
        {
         datetime deadlineTail=entry.DeadlineUtc()+(datetime)after;
         if(deadlineTail>toOut)
            toOut=deadlineTail;
        }

      datetime rollingFrom=nowUtc-(datetime)before;
      if(rollingFrom<fromOut)
         fromOut=rollingFrom;
     }

  };

#endif
