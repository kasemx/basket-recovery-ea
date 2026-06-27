#ifndef BRE_INF_MT5_TRADE_CHECK_RESULT_MAPPER_MQH
#define BRE_INF_MT5_TRADE_CHECK_RESULT_MAPPER_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionResult.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionFailureReason.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5RequestTranslationResult.mqh>

class CMt5TradeCheckResultMapper
  {
public:
   static bool       IsTimeoutRetcode(const uint retcode)
     {
      return retcode==TRADE_RETCODE_TIMEOUT;
     }

   static bool       IsMarketUnavailableRetcode(const uint retcode)
     {
      switch(retcode)
        {
         case TRADE_RETCODE_CONNECTION:
         case TRADE_RETCODE_PRICE_OFF:
         case TRADE_RETCODE_MARKET_CLOSED:
         case TRADE_RETCODE_TRADE_DISABLED:
            return true;
         default:
            return false;
        }
     }

   static CTradeExecutionResult MapAcceptedDryRun(const CMt5RequestTranslationResult &translation,
                                                  const MqlTradeCheckResult &checkResult,
                                                  const datetime completedAtUtc)
     {
      CTradeExecutionResult result;
      result.SetStatus(BRE_TRADE_EXEC_STATUS_ACCEPTED);
      result.SetRequestedVolume(translation.Request().volume);
      result.SetFillPrice(translation.Request().price);
      result.SetCheckedStopLoss(translation.Request().sl);
      result.SetCheckedTakeProfit(translation.Request().tp);
      result.SetIsDryRun(true);
      result.SetMt5Retcode(checkResult.retcode);
      result.SetRequestSummary(translation.Summary());
      result.SetOrderCheckInvoked(true);
      result.SetMessage(StringFormat("OrderCheck dry-run accepted | retcode=%u | %s",
                                     checkResult.retcode,
                                     checkResult.comment));
      result.SetCompletedAtUtc(completedAtUtc);
      return result;
     }

   static CTradeExecutionResult MapRejected(const CMt5RequestTranslationResult &translation,
                                            const uint retcode,
                                            const string diagnostic,
                                            const datetime completedAtUtc)
     {
      CTradeExecutionResult result=CTradeExecutionResult::Rejected(BRE_EXEC_FAIL_BROKER_REJECTED,diagnostic,
                                                                   translation.Request().volume);
      result.SetFillPrice(translation.Request().price);
      result.SetCheckedStopLoss(translation.Request().sl);
      result.SetCheckedTakeProfit(translation.Request().tp);
      result.SetIsDryRun(true);
      result.SetMt5Retcode(retcode);
      result.SetRequestSummary(translation.Summary());
      result.SetOrderCheckInvoked(true);
      result.SetCompletedAtUtc(completedAtUtc);
      return result;
     }

   static CTradeExecutionResult MapLocalRejected(const ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON reason,
                                                 const string message,
                                                 const datetime completedAtUtc,
                                                 const double requestedVolume=0.0)
     {
      CTradeExecutionResult result=CTradeExecutionResult::Rejected(reason,message,requestedVolume);
      result.SetIsDryRun(true);
      result.SetOrderCheckInvoked(false);
      result.SetCompletedAtUtc(completedAtUtc);
      return result;
     }

   static CTradeExecutionResult MapOrderCheckOutcome(const CMt5RequestTranslationResult &translation,
                                                     const bool checkSucceeded,
                                                     const MqlTradeCheckResult &checkResult,
                                                     const datetime completedAtUtc)
     {
      if(!checkSucceeded)
        {
         if(IsTimeoutRetcode(checkResult.retcode))
           {
            CTradeExecutionResult result;
            result.SetStatus(BRE_TRADE_EXEC_STATUS_TIMED_OUT);
            result.SetFailureReason(BRE_EXEC_FAIL_TIMEOUT);
            result.SetMessage(StringFormat("OrderCheck timeout | retcode=%u",checkResult.retcode));
            result.SetRequestedVolume(translation.Request().volume);
            result.SetIsDryRun(true);
            result.SetMt5Retcode(checkResult.retcode);
            result.SetRequestSummary(translation.Summary());
            result.SetOrderCheckInvoked(true);
            result.SetCompletedAtUtc(completedAtUtc);
            return result;
           }
         if(IsMarketUnavailableRetcode(checkResult.retcode))
           {
            CTradeExecutionResult result;
            result.SetStatus(BRE_TRADE_EXEC_STATUS_FAILED);
            result.SetFailureReason(BRE_EXEC_FAIL_MARKET_UNAVAILABLE);
            result.SetMessage(StringFormat("OrderCheck market unavailable | retcode=%u | %s",
                                           checkResult.retcode,checkResult.comment));
            result.SetRequestedVolume(translation.Request().volume);
            result.SetIsDryRun(true);
            result.SetMt5Retcode(checkResult.retcode);
            result.SetRequestSummary(translation.Summary());
            result.SetOrderCheckInvoked(true);
            result.SetCompletedAtUtc(completedAtUtc);
            return result;
           }
         return MapRejected(translation,checkResult.retcode,
                            StringFormat("OrderCheck rejected | retcode=%u | %s",checkResult.retcode,checkResult.comment),
                            completedAtUtc);
        }

      if(checkResult.retcode==TRADE_RETCODE_DONE ||
         checkResult.retcode==TRADE_RETCODE_PLACED ||
         checkResult.retcode==TRADE_RETCODE_DONE_PARTIAL ||
         (checkResult.retcode==0 && checkResult.comment=="Done"))
         return MapAcceptedDryRun(translation,checkResult,completedAtUtc);

      if(checkResult.retcode==TRADE_RETCODE_REJECT ||
         checkResult.retcode==TRADE_RETCODE_INVALID_STOPS ||
         checkResult.retcode==TRADE_RETCODE_INVALID_VOLUME ||
         checkResult.retcode==TRADE_RETCODE_INVALID_PRICE ||
         checkResult.retcode==TRADE_RETCODE_INVALID_FILL)
         return MapRejected(translation,checkResult.retcode,
                            StringFormat("OrderCheck broker validation failed | retcode=%u | %s",
                                         checkResult.retcode,checkResult.comment),
                            completedAtUtc);

      CTradeExecutionResult unknown;
      unknown.SetStatus(BRE_TRADE_EXEC_STATUS_UNKNOWN);
      unknown.SetFailureReason(BRE_EXEC_FAIL_UNKNOWN_BROKER);
      unknown.SetMessage(StringFormat("OrderCheck ambiguous | retcode=%u | %s",checkResult.retcode,checkResult.comment));
      unknown.SetRequestedVolume(translation.Request().volume);
      unknown.SetIsDryRun(true);
      unknown.SetMt5Retcode(checkResult.retcode);
      unknown.SetRequestSummary(translation.Summary());
      unknown.SetOrderCheckInvoked(true);
      unknown.SetCompletedAtUtc(completedAtUtc);
      return unknown;
     }
  };

#endif
