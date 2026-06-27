#ifndef BRE_DOMAIN_SUBMISSION_GATEWAY_RESULT_MQH
#define BRE_DOMAIN_SUBMISSION_GATEWAY_RESULT_MQH

#include <BasketRecovery/Domain/Execution/SubmissionGatewayStatus.mqh>

class CSubmissionGatewayResult
  {
private:
   ENUM_BRE_SUBMISSION_GATEWAY_STATUS m_status;
   ulong                              m_brokerRequestId;
   string                             m_detail;
   bool                               m_duplicateReplay;

public:
                     CSubmissionGatewayResult(void)
     {
      m_status=BRE_SUBMISSION_GW_NONE;
      m_brokerRequestId=0;
      m_detail="";
      m_duplicateReplay=false;
     }

   ENUM_BRE_SUBMISSION_GATEWAY_STATUS Status(void) const { return m_status; }
   ulong             BrokerRequestId(void) const { return m_brokerRequestId; }
   string            Detail(void) const { return m_detail; }
   bool              IsDuplicateReplay(void) const { return m_duplicateReplay; }
   bool              IsAccepted(void) const { return m_status==BRE_SUBMISSION_GW_ACCEPTED; }
   bool              IsRejected(void) const { return m_status==BRE_SUBMISSION_GW_REJECTED; }
   bool              IsUnknown(void) const { return m_status==BRE_SUBMISSION_GW_UNKNOWN; }

   static CSubmissionGatewayResult Accepted(const ulong brokerRequestId,const string detail="")
     {
      CSubmissionGatewayResult result;
      result.m_status=BRE_SUBMISSION_GW_ACCEPTED;
      result.m_brokerRequestId=brokerRequestId;
      result.m_detail=detail;
      return result;
     }

   static CSubmissionGatewayResult Rejected(const string detail)
     {
      CSubmissionGatewayResult result;
      result.m_status=BRE_SUBMISSION_GW_REJECTED;
      result.m_detail=detail;
      return result;
     }

   static CSubmissionGatewayResult Unknown(const string detail)
     {
      CSubmissionGatewayResult result;
      result.m_status=BRE_SUBMISSION_GW_UNKNOWN;
      result.m_detail=detail;
      return result;
     }

   static CSubmissionGatewayResult DuplicateReplay(const CSubmissionGatewayResult &original)
     {
      CSubmissionGatewayResult result=original;
      result.m_duplicateReplay=true;
      return result;
     }
  };

#endif
