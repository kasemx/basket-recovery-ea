#ifndef BRE_DOMAIN_EXECUTION_REQUEST_FINGERPRINT_MQH
#define BRE_DOMAIN_EXECUTION_REQUEST_FINGERPRINT_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Shared/Utils/Crc32.mqh>

class CExecutionRequestFingerprint
  {
private:
   string m_value;

public:
                     CExecutionRequestFingerprint(void) { m_value=""; }
                     CExecutionRequestFingerprint(const string value) { m_value=value; }

   string            Value(void) const { return m_value; }
   bool              IsEmpty(void) const { return m_value==""; }

   bool              operator==(const CExecutionRequestFingerprint &other) const { return m_value==other.m_value; }
   bool              operator!=(const CExecutionRequestFingerprint &other) const { return m_value!=other.m_value; }

   static CExecutionRequestFingerprint Compute(const CTradeExecutionRequest &request)
     {
      string payload=StringFormat("%s|%s|%s|%d|%d|%.4f|%.5f|%.5f|%.5f|%I64d",
                                  request.ExecutionRequestId(),
                                  request.IdempotencyKey(),
                                  request.Symbol(),
                                  (int)request.IntentType(),
                                  (int)request.Direction(),
                                  request.RequestedVolume(),
                                  request.RequestedPrice(),
                                  request.RequestedStopLoss(),
                                  request.RequestedTakeProfit(),
                                  request.ExpectedBasketVersion());
      uint crc=CCrc32::Compute(payload);
      CExecutionRequestFingerprint fingerprint(StringFormat("fp-%s",StringSubstr(CCrc32::ToHex(crc),0,8)));
      return fingerprint;
     }
  };

#endif
