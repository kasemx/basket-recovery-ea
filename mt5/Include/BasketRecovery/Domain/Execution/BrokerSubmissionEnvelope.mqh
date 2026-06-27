#ifndef BRE_DOMAIN_BROKER_SUBMISSION_ENVELOPE_MQH
#define BRE_DOMAIN_BROKER_SUBMISSION_ENVELOPE_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRequestFingerprint.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CBrokerSubmissionEnvelope
  {
private:
   string                        m_executionRequestId;
   string                        m_idempotencyKey;
   CBasketId                     m_basketId;
   int                           m_expectedBasketVersion;
   string                        m_strategyProfileHash;
   string                        m_symbol;
   ENUM_BRE_TRADE_EXECUTION_INTENT m_intentType;
   ENUM_BRE_TRADE_DIRECTION      m_direction;
   ulong                         m_ticket;
   double                        m_requestedVolume;
   double                        m_requestedPrice;
   double                        m_requestedStopLoss;
   double                        m_requestedTakeProfit;
   long                          m_magicNumber;
   string                        m_brokerComment;
   string                        m_correlationToken;
   CExecutionRequestFingerprint  m_fingerprint;
   datetime                      m_quoteTimestampUtc;
   datetime                      m_preparedAtUtc;
   datetime                      m_expirationUtc;

public:
                     CBrokerSubmissionEnvelope(void)
     {
      m_expectedBasketVersion=0;
      m_intentType=BRE_EXEC_INTENT_NONE;
      m_direction=BRE_DIRECTION_NONE;
      m_ticket=0;
      m_requestedVolume=0.0;
      m_requestedPrice=0.0;
      m_requestedStopLoss=0.0;
      m_requestedTakeProfit=0.0;
      m_magicNumber=0;
      m_quoteTimestampUtc=0;
      m_preparedAtUtc=0;
      m_expirationUtc=0;
     }

   string            ExecutionRequestId(void) const { return m_executionRequestId; }
   string            IdempotencyKey(void) const { return m_idempotencyKey; }
   CBasketId         BasketId(void) const { return m_basketId; }
   int               ExpectedBasketVersion(void) const { return m_expectedBasketVersion; }
   string            StrategyProfileHash(void) const { return m_strategyProfileHash; }
   string            Symbol(void) const { return m_symbol; }
   ENUM_BRE_TRADE_EXECUTION_INTENT IntentType(void) const { return m_intentType; }
   ENUM_BRE_TRADE_DIRECTION Direction(void) const { return m_direction; }
   ulong             Ticket(void) const { return m_ticket; }
   double            RequestedVolume(void) const { return m_requestedVolume; }
   double            RequestedPrice(void) const { return m_requestedPrice; }
   double            RequestedStopLoss(void) const { return m_requestedStopLoss; }
   double            RequestedTakeProfit(void) const { return m_requestedTakeProfit; }
   long              MagicNumber(void) const { return m_magicNumber; }
   string            BrokerComment(void) const { return m_brokerComment; }
   string            CorrelationToken(void) const { return m_correlationToken; }
   CExecutionRequestFingerprint Fingerprint(void) const { return m_fingerprint; }
   datetime          QuoteTimestampUtc(void) const { return m_quoteTimestampUtc; }
   datetime          PreparedAtUtc(void) const { return m_preparedAtUtc; }
   datetime          ExpirationUtc(void) const { return m_expirationUtc; }

   void              SetExecutionRequestId(const string value) { m_executionRequestId=value; }
   void              SetIdempotencyKey(const string value) { m_idempotencyKey=value; }
   void              SetBasketId(const CBasketId &value) { m_basketId=value; }
   void              SetExpectedBasketVersion(const int value) { m_expectedBasketVersion=value; }
   void              SetStrategyProfileHash(const string value) { m_strategyProfileHash=value; }
   void              SetSymbol(const string value) { m_symbol=value; }
   void              SetIntentType(const ENUM_BRE_TRADE_EXECUTION_INTENT value) { m_intentType=value; }
   void              SetDirection(const ENUM_BRE_TRADE_DIRECTION value) { m_direction=value; }
   void              SetTicket(const ulong value) { m_ticket=value; }
   void              SetRequestedVolume(const double value) { m_requestedVolume=value; }
   void              SetRequestedPrice(const double value) { m_requestedPrice=value; }
   void              SetRequestedStopLoss(const double value) { m_requestedStopLoss=value; }
   void              SetRequestedTakeProfit(const double value) { m_requestedTakeProfit=value; }
   void              SetMagicNumber(const long value) { m_magicNumber=value; }
   void              SetBrokerComment(const string value) { m_brokerComment=value; }
   void              SetCorrelationToken(const string value) { m_correlationToken=value; }
   void              SetFingerprint(const CExecutionRequestFingerprint &value) { m_fingerprint=value; }
   void              SetQuoteTimestampUtc(const datetime value) { m_quoteTimestampUtc=value; }
   void              SetPreparedAtUtc(const datetime value) { m_preparedAtUtc=value; }
   void              SetExpirationUtc(const datetime value) { m_expirationUtc=value; }

   bool              IsExpired(const datetime nowUtc) const
     {
      return m_expirationUtc>0 && nowUtc>=m_expirationUtc;
     }
  };

#endif
