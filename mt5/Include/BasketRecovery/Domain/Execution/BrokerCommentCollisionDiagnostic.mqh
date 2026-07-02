#ifndef BRE_DOMAIN_BROKER_COMMENT_COLLISION_DIAGNOSTIC_MQH
#define BRE_DOMAIN_BROKER_COMMENT_COLLISION_DIAGNOSTIC_MQH

class CBrokerCommentCollisionDiagnostic
  {
private:
   bool              m_hasCollision;
   bool              m_isSameAuthorizedRequest;
   string            m_source;
   string            m_matchedComment;
   string            m_matchedRequestId;
   ulong             m_matchedTicket;
   string            m_matchedStatus;

public:
                     CBrokerCommentCollisionDiagnostic(void)
     {
      m_hasCollision=false;
      m_isSameAuthorizedRequest=false;
      m_source="";
      m_matchedComment="";
      m_matchedRequestId="";
      m_matchedTicket=0;
      m_matchedStatus="";
     }

   bool              HasCollision(void) const { return m_hasCollision; }
   bool              IsSameAuthorizedRequest(void) const { return m_isSameAuthorizedRequest; }
   string            Source(void) const { return m_source; }
   string            MatchedComment(void) const { return m_matchedComment; }
   string            MatchedRequestId(void) const { return m_matchedRequestId; }
   ulong             MatchedTicket(void) const { return m_matchedTicket; }
   string            MatchedStatus(void) const { return m_matchedStatus; }

   void              SetHasCollision(const bool value) { m_hasCollision=value; }
   void              SetIsSameAuthorizedRequest(const bool value) { m_isSameAuthorizedRequest=value; }
   void              SetSource(const string value) { m_source=value; }
   void              SetMatchedComment(const string value) { m_matchedComment=value; }
   void              SetMatchedRequestId(const string value) { m_matchedRequestId=value; }
   void              SetMatchedTicket(const ulong value) { m_matchedTicket=value; }
   void              SetMatchedStatus(const string value) { m_matchedStatus=value; }

   static string     SourceUnresolvedForeignPending(void)
     {
      return "unresolved foreign pending record";
     }

   string            FailureMessage(void) const
     {
      if(!m_hasCollision)
         return "";
      if(m_source==SourceUnresolvedForeignPending())
         return "Broker comment collision: unresolved foreign pending record";
      return "Broker comment collision: "+m_source;
     }
  };

class CBrokerCommentSubmitDiagnostics
  {
private:
   string                            m_factoryBuildMarker;
   string                            m_executionRequestId;
   ulong                             m_targetTicket;
   double                            m_requestedVolume;
   string                            m_brokerComment;
   string                            m_brokerCommentFingerprint;
   string                            m_collisionCheckResult;
   CBrokerCommentCollisionDiagnostic m_collisionDiagnostic;
   bool                              m_resolutionAttempted;
   string                            m_finalComment;

public:
                     CBrokerCommentSubmitDiagnostics(void)
     {
      Clear();
     }

   void              Clear(void)
     {
      m_factoryBuildMarker="";
      m_executionRequestId="";
      m_targetTicket=0;
      m_requestedVolume=0.0;
      m_brokerComment="";
      m_brokerCommentFingerprint="";
      m_collisionCheckResult="";
      m_collisionDiagnostic=CBrokerCommentCollisionDiagnostic();
      m_resolutionAttempted=false;
      m_finalComment="";
     }

   string            FactoryBuildMarker(void) const { return m_factoryBuildMarker; }
   string            ExecutionRequestId(void) const { return m_executionRequestId; }
   ulong             TargetTicket(void) const { return m_targetTicket; }
   double            RequestedVolume(void) const { return m_requestedVolume; }
   string            BrokerComment(void) const { return m_brokerComment; }
   string            BrokerCommentFingerprint(void) const { return m_brokerCommentFingerprint; }
   string            CollisionCheckResult(void) const { return m_collisionCheckResult; }
   CBrokerCommentCollisionDiagnostic CollisionDiagnostic(void) const { return m_collisionDiagnostic; }
   bool              ResolutionAttempted(void) const { return m_resolutionAttempted; }
   string            FinalComment(void) const { return m_finalComment; }

   void              SetFactoryBuildMarker(const string value) { m_factoryBuildMarker=value; }
   void              SetExecutionRequestId(const string value) { m_executionRequestId=value; }
   void              SetTargetTicket(const ulong value) { m_targetTicket=value; }
   void              SetRequestedVolume(const double value) { m_requestedVolume=value; }
   void              SetBrokerComment(const string value) { m_brokerComment=value; }
   void              SetBrokerCommentFingerprint(const string value) { m_brokerCommentFingerprint=value; }
   void              SetCollisionCheckResult(const string value) { m_collisionCheckResult=value; }
   void              SetCollisionDiagnostic(const CBrokerCommentCollisionDiagnostic &value) { m_collisionDiagnostic=value; }
   void              SetResolutionAttempted(const bool value) { m_resolutionAttempted=value; }
   void              SetFinalComment(const string value) { m_finalComment=value; }
  };

#endif
