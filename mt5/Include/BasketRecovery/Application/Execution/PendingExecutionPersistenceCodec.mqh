#ifndef BRE_APP_PENDING_EXECUTION_PERSISTENCE_CODEC_MQH
#define BRE_APP_PENDING_EXECUTION_PERSISTENCE_CODEC_MQH

#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionEnvelope.mqh>

class CPendingExecutionPersistenceCodec
  {
public:
   static string     EncodeEntry(const CPendingExecutionEntry &entry)
     {
      return StringFormat("%s\t%s\t%s\t%d\t%s\t%d\t%s\t%.4f\t%.4f\t%d\t%d\t%s\t%s\t%s\t%.5f\t%.5f\t%d\t%d\t%I64u\t%I64u\t%d",
                          entry.ExecutionRequestId(),
                          entry.IdempotencyKey(),
                          entry.BasketId().Value(),
                          entry.ExpectedBasketVersion(),
                          entry.StrategyProfileHash(),
                          (int)entry.IntentType(),
                          entry.Symbol(),
                          entry.RequestedVolume(),
                          entry.FilledVolume(),
                          (int)entry.Status(),
                          (int)entry.DeadlineUtc(),
                          entry.CorrelationToken(),
                          entry.BrokerComment(),
                          entry.RequestFingerprint(),
                          entry.PreparedBid(),
                          entry.PreparedAsk(),
                          (int)entry.PreparedAtUtc(),
                          (int)entry.PreparedQuoteTimestampUtc(),
                          entry.BrokerCorrelation().BrokerOrderId(),
                          entry.BrokerCorrelation().BrokerDealId(),
                          (int)entry.SubmittedAtUtc());
     }

   static bool       TryDecodeEntry(const string line,CPendingExecutionEntry &entry)
     {
      if(line=="")
         return false;
      string parts[];
      if(StringSplit(line,'\t',parts)<18)
         return false;

      entry=CPendingExecutionEntry();
      entry.SetExecutionRequestId(parts[0]);
      entry.SetIdempotencyKey(parts[1]);
      entry.SetBasketId(CBasketId(parts[2]));
      entry.SetExpectedBasketVersion((int)StringToInteger(parts[3]));
      entry.SetStrategyProfileHash(parts[4]);
      entry.SetIntentType((ENUM_BRE_TRADE_EXECUTION_INTENT)StringToInteger(parts[5]));
      entry.SetSymbol(parts[6]);
      entry.SetRequestedVolume(StringToDouble(parts[7]));
      entry.SetFilledVolume(StringToDouble(parts[8]));
      entry.SetStatus((ENUM_BRE_TRADE_EXECUTION_STATUS)StringToInteger(parts[9]));
      entry.SetDeadlineUtc((datetime)StringToInteger(parts[10]));
      entry.SetCorrelationToken(parts[11]);
      entry.SetBrokerComment(parts[12]);
      entry.SetRequestFingerprint(parts[13]);
      entry.SetPreparedBid(StringToDouble(parts[14]));
      entry.SetPreparedAsk(StringToDouble(parts[15]));
      entry.SetPreparedAtUtc((datetime)StringToInteger(parts[16]));
      entry.SetPreparedQuoteTimestampUtc((datetime)StringToInteger(parts[17]));
      if(ArraySize(parts)>=21)
        {
         CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
         broker.SetBrokerOrderId((ulong)StringToInteger(parts[18]));
         broker.SetBrokerDealId((ulong)StringToInteger(parts[19]));
         entry.SetBrokerCorrelation(broker);
         datetime submittedAt=(datetime)StringToInteger(parts[20]);
         if(submittedAt>0)
            entry.SetSubmittedAtUtc(submittedAt);
        }
      return entry.ExecutionRequestId()!="";
     }

   static string     EncodeEnvelope(const CBrokerSubmissionEnvelope &envelope)
     {
      return StringFormat("%s\t%s\t%s\t%d\t%s\t%d\t%s\t%d\t%d\t%.4f\t%.5f\t%.5f\t%.5f\t%I64d\t%s\t%s\t%s\t%d\t%d\t%d",
                          envelope.ExecutionRequestId(),
                          envelope.IdempotencyKey(),
                          envelope.BasketId().Value(),
                          envelope.ExpectedBasketVersion(),
                          envelope.StrategyProfileHash(),
                          (int)envelope.IntentType(),
                          envelope.Symbol(),
                          (int)envelope.Direction(),
                          (int)envelope.Ticket(),
                          envelope.RequestedVolume(),
                          envelope.RequestedPrice(),
                          envelope.RequestedStopLoss(),
                          envelope.RequestedTakeProfit(),
                          envelope.MagicNumber(),
                          envelope.BrokerComment(),
                          envelope.CorrelationToken(),
                          envelope.Fingerprint().Value(),
                          (int)envelope.QuoteTimestampUtc(),
                          (int)envelope.PreparedAtUtc(),
                          (int)envelope.ExpirationUtc());
     }

   static bool       TryDecodeEnvelope(const string line,CBrokerSubmissionEnvelope &envelope)
     {
      if(line=="")
         return false;
      string parts[];
      if(StringSplit(line,'\t',parts)<20)
         return false;

      envelope=CBrokerSubmissionEnvelope();
      envelope.SetExecutionRequestId(parts[0]);
      envelope.SetIdempotencyKey(parts[1]);
      envelope.SetBasketId(CBasketId(parts[2]));
      envelope.SetExpectedBasketVersion((int)StringToInteger(parts[3]));
      envelope.SetStrategyProfileHash(parts[4]);
      envelope.SetIntentType((ENUM_BRE_TRADE_EXECUTION_INTENT)StringToInteger(parts[5]));
      envelope.SetSymbol(parts[6]);
      envelope.SetDirection((ENUM_BRE_TRADE_DIRECTION)StringToInteger(parts[7]));
      envelope.SetTicket((ulong)StringToInteger(parts[8]));
      envelope.SetRequestedVolume(StringToDouble(parts[9]));
      envelope.SetRequestedPrice(StringToDouble(parts[10]));
      envelope.SetRequestedStopLoss(StringToDouble(parts[11]));
      envelope.SetRequestedTakeProfit(StringToDouble(parts[12]));
      envelope.SetMagicNumber(StringToInteger(parts[13]));
      envelope.SetBrokerComment(parts[14]);
      envelope.SetCorrelationToken(parts[15]);
      envelope.SetFingerprint(CExecutionRequestFingerprint(parts[16]));
      envelope.SetQuoteTimestampUtc((datetime)StringToInteger(parts[17]));
      envelope.SetPreparedAtUtc((datetime)StringToInteger(parts[18]));
      envelope.SetExpirationUtc((datetime)StringToInteger(parts[19]));
      return envelope.ExecutionRequestId()!="";
     }
  };

#endif
