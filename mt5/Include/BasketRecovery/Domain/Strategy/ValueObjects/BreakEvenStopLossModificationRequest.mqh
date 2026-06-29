#ifndef BRE_DOMAIN_BREAK_EVEN_STOP_LOSS_MODIFICATION_REQUEST_MQH
#define BRE_DOMAIN_BREAK_EVEN_STOP_LOSS_MODIFICATION_REQUEST_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/BreakEvenCandidateTriggerType.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/BreakEvenModificationRequestStatus.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/BreakEvenModificationFailureReason.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/BreakEvenModificationExecutionIntent.mqh>

enum ENUM_BRE_BREAK_EVEN_TICKET_MODIFICATION_STATUS
  {
   BRE_BREAK_EVEN_TICKET_MOD_APPLY_REQUIRED=0,
   BRE_BREAK_EVEN_TICKET_MOD_NO_CHANGE_REQUIRED,
   BRE_BREAK_EVEN_TICKET_MOD_UNSAFE
  };

class CBreakEvenStopLossModificationRequest
  {
private:
   string                                        m_executionRequestId;
   CBasketId                                     m_basketId;
   string                                        m_strategyProfileHash;
   long                                          m_basketVersion;
   ulong                                         m_quoteSequence;
   string                                        m_correlationId;
   string                                        m_idempotencyKey;
   string                                        m_symbol;
   ENUM_BRE_TRADE_DIRECTION                      m_direction;
   ulong                                         m_boundTickets[];
   double                                        m_priorStopLossByTicket[];
   ENUM_BRE_BREAK_EVEN_TICKET_MODIFICATION_STATUS m_ticketStatusByTicket[];
   double                                        m_proposedStopLossPrice;
   double                                        m_weightedAverageEntry;
   double                                        m_totalActiveVolume;
   string                                        m_triggerRuleId;
   ENUM_BRE_BREAK_EVEN_CANDIDATE_TRIGGER_TYPE    m_triggerType;
   double                                        m_triggerValue;
   double                                        m_spreadComponent;
   double                                        m_safetyBufferComponent;
   bool                                          m_recoveryDisableRecommendation;
   bool                                          m_lockRecommendation;
   datetime                                      m_createdUtc;
   bool                                          m_dryRunOnly;
   string                                        m_sourceCandidateId;
   ENUM_BRE_BREAK_EVEN_MODIFICATION_REQUEST_STATUS m_status;
   ENUM_BRE_BREAK_EVEN_MODIFICATION_FAILURE_REASON m_failureReason;
   ENUM_BRE_BREAK_EVEN_MODIFICATION_EXECUTION_INTENT m_executionIntent;
   ENUM_BRE_BREAK_EVEN_MODIFICATION_APPLY_POLICY m_applyPolicy;
   bool                                          m_brokerMutationPerformed;

public:
                     CBreakEvenStopLossModificationRequest(void)
     {
      m_basketVersion=0;
      m_quoteSequence=0;
      m_direction=BRE_DIRECTION_NONE;
      m_proposedStopLossPrice=0.0;
      m_weightedAverageEntry=0.0;
      m_totalActiveVolume=0.0;
      m_triggerType=BRE_BE_CANDIDATE_TRIGGER_NONE;
      m_triggerValue=0.0;
      m_spreadComponent=0.0;
      m_safetyBufferComponent=0.0;
      m_recoveryDisableRecommendation=false;
      m_lockRecommendation=false;
      m_createdUtc=0;
      m_dryRunOnly=true;
      m_status=BRE_BREAK_EVEN_MOD_REQ_NONE;
      m_failureReason=BRE_BREAK_EVEN_MOD_FAIL_NONE;
      m_executionIntent=BRE_BREAK_EVEN_MOD_INTENT_DRY_RUN_ONLY;
      m_applyPolicy=BRE_BREAK_EVEN_MOD_POLICY_ALL_OR_NOTHING;
      m_brokerMutationPerformed=false;
      ArrayResize(m_boundTickets,0);
      ArrayResize(m_priorStopLossByTicket,0);
      ArrayResize(m_ticketStatusByTicket,0);
     }

   string            ExecutionRequestId(void) const { return m_executionRequestId; }
   CBasketId         BasketId(void) const { return m_basketId; }
   string            StrategyProfileHash(void) const { return m_strategyProfileHash; }
   long              BasketVersion(void) const { return m_basketVersion; }
   ulong             QuoteSequence(void) const { return m_quoteSequence; }
   string            CorrelationId(void) const { return m_correlationId; }
   string            IdempotencyKey(void) const { return m_idempotencyKey; }
   string            Symbol(void) const { return m_symbol; }
   ENUM_BRE_TRADE_DIRECTION Direction(void) const { return m_direction; }
   int               TicketCount(void) const { return ArraySize(m_boundTickets); }
   double            ProposedStopLossPrice(void) const { return m_proposedStopLossPrice; }
   double            WeightedAverageEntry(void) const { return m_weightedAverageEntry; }
   double            TotalActiveVolume(void) const { return m_totalActiveVolume; }
   string            TriggerRuleId(void) const { return m_triggerRuleId; }
   ENUM_BRE_BREAK_EVEN_CANDIDATE_TRIGGER_TYPE TriggerType(void) const { return m_triggerType; }
   double            TriggerValue(void) const { return m_triggerValue; }
   double            SpreadComponent(void) const { return m_spreadComponent; }
   double            SafetyBufferComponent(void) const { return m_safetyBufferComponent; }
   bool              RecoveryDisableRecommendation(void) const { return m_recoveryDisableRecommendation; }
   bool              LockRecommendation(void) const { return m_lockRecommendation; }
   datetime          CreatedUtc(void) const { return m_createdUtc; }
   bool              DryRunOnly(void) const { return m_dryRunOnly; }
   string            SourceCandidateId(void) const { return m_sourceCandidateId; }
   ENUM_BRE_BREAK_EVEN_MODIFICATION_REQUEST_STATUS Status(void) const { return m_status; }
   ENUM_BRE_BREAK_EVEN_MODIFICATION_FAILURE_REASON FailureReason(void) const { return m_failureReason; }
   ENUM_BRE_BREAK_EVEN_MODIFICATION_EXECUTION_INTENT ExecutionIntent(void) const { return m_executionIntent; }
   ENUM_BRE_BREAK_EVEN_MODIFICATION_APPLY_POLICY ApplyPolicy(void) const { return m_applyPolicy; }
   bool              BrokerMutationPerformed(void) const { return m_brokerMutationPerformed; }

   bool              TicketAt(const int index,
                              ulong &ticket,
                              double &priorStopLoss,
                              ENUM_BRE_BREAK_EVEN_TICKET_MODIFICATION_STATUS &ticketStatus) const
     {
      if(index<0 || index>=ArraySize(m_boundTickets))
         return false;
      ticket=m_boundTickets[index];
      priorStopLoss=m_priorStopLossByTicket[index];
      ticketStatus=m_ticketStatusByTicket[index];
      return true;
     }

   int               CountTicketsByStatus(const ENUM_BRE_BREAK_EVEN_TICKET_MODIFICATION_STATUS status) const
     {
      int count=0;
      for(int i=0;i<ArraySize(m_ticketStatusByTicket);i++)
        {
         if(m_ticketStatusByTicket[i]==status)
            count++;
        }
      return count;
     }

   bool              IsDryRunReady(void) const
     {
      return m_status==BRE_BREAK_EVEN_MOD_REQ_DRY_RUN_READY &&
             m_failureReason==BRE_BREAK_EVEN_MOD_FAIL_NONE &&
             !m_brokerMutationPerformed &&
             m_dryRunOnly;
     }

   static CBreakEvenStopLossModificationRequest Create(const string executionRequestId,
                                                       const CBasketId &basketId,
                                                       const string strategyProfileHash,
                                                       const long basketVersion,
                                                       const ulong quoteSequence,
                                                       const string correlationId,
                                                       const string idempotencyKey,
                                                       const string symbol,
                                                       const ENUM_BRE_TRADE_DIRECTION direction,
                                                       const ulong &boundTickets[],
                                                       const double &priorStopLossByTicket[],
                                                       const ENUM_BRE_BREAK_EVEN_TICKET_MODIFICATION_STATUS &ticketStatusByTicket[],
                                                       const double proposedStopLossPrice,
                                                       const double weightedAverageEntry,
                                                       const double totalActiveVolume,
                                                       const string triggerRuleId,
                                                       const ENUM_BRE_BREAK_EVEN_CANDIDATE_TRIGGER_TYPE triggerType,
                                                       const double triggerValue,
                                                       const double spreadComponent,
                                                       const double safetyBufferComponent,
                                                       const bool recoveryDisableRecommendation,
                                                       const bool lockRecommendation,
                                                       const datetime createdUtc,
                                                       const bool dryRunOnly,
                                                       const string sourceCandidateId,
                                                       const ENUM_BRE_BREAK_EVEN_MODIFICATION_REQUEST_STATUS status,
                                                       const ENUM_BRE_BREAK_EVEN_MODIFICATION_FAILURE_REASON failureReason)
     {
      CBreakEvenStopLossModificationRequest request;
      request.m_executionRequestId=executionRequestId;
      request.m_basketId=basketId;
      request.m_strategyProfileHash=strategyProfileHash;
      request.m_basketVersion=basketVersion;
      request.m_quoteSequence=quoteSequence;
      request.m_correlationId=correlationId;
      request.m_idempotencyKey=idempotencyKey;
      request.m_symbol=symbol;
      request.m_direction=direction;
      request.m_proposedStopLossPrice=proposedStopLossPrice;
      request.m_weightedAverageEntry=weightedAverageEntry;
      request.m_totalActiveVolume=totalActiveVolume;
      request.m_triggerRuleId=triggerRuleId;
      request.m_triggerType=triggerType;
      request.m_triggerValue=triggerValue;
      request.m_spreadComponent=spreadComponent;
      request.m_safetyBufferComponent=safetyBufferComponent;
      request.m_recoveryDisableRecommendation=recoveryDisableRecommendation;
      request.m_lockRecommendation=lockRecommendation;
      request.m_createdUtc=createdUtc;
      request.m_dryRunOnly=dryRunOnly;
      request.m_sourceCandidateId=sourceCandidateId;
      request.m_status=status;
      request.m_failureReason=failureReason;
      request.m_executionIntent=BRE_BREAK_EVEN_MOD_INTENT_DRY_RUN_ONLY;
      request.m_applyPolicy=BRE_BREAK_EVEN_MOD_POLICY_ALL_OR_NOTHING;
      request.m_brokerMutationPerformed=false;

      int ticketCount=ArraySize(boundTickets);
      ArrayResize(request.m_boundTickets,ticketCount);
      ArrayResize(request.m_priorStopLossByTicket,ticketCount);
      ArrayResize(request.m_ticketStatusByTicket,ticketCount);
      for(int i=0;i<ticketCount;i++)
        {
         request.m_boundTickets[i]=boundTickets[i];
         request.m_priorStopLossByTicket[i]=priorStopLossByTicket[i];
         request.m_ticketStatusByTicket[i]=ticketStatusByTicket[i];
        }
      return request;
     }
  };

#endif
