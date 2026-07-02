#ifndef BRE_APP_PROFIT_CLOSE_FILLED_PENDING_COMPLETION_SERVICE_MQH
#define BRE_APP_PROFIT_CLOSE_FILLED_PENDING_COMPLETION_SERVICE_MQH

#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Basket/BasketProfitLevelProgress.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Shared/Types/Money.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

#define BRE_PROFIT_CLOSE_PERSISTED_PENDING_COMPLETION_BUILD_MARKER "S8C_PROFIT_CLOSE_PERSISTED_PENDING_COMPLETION_V1"

enum ENUM_BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_RESULT
  {
   BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_REJECTED=0,
   BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_COMPLETED,
   BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_ALREADY_COMPLETED
  };

struct SProfitClosePersistedIdempotencyParse
  {
   bool              valid;
   string            basketId;
   string            profitLevelId;
   long              quoteSequence;
   string            reason;
  };

struct SProfitClosePersistedCompletionOutcome
  {
   ENUM_BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_RESULT result;
   string            reason;
   string            profitLevelId;
  };

class CProfitCloseFilledPendingCompletionService
  {
private:
   static bool       IsAsciiDigitsOnly(const string value)
     {
      if(value=="")
         return false;
      for(int i=0;i<StringLen(value);i++)
        {
         ushort character=StringGetCharacter(value,i);
         if(character<'0' || character>'9')
            return false;
        }
      return true;
     }

   static string     CompletionResultToString(const ENUM_BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_RESULT result)
     {
      switch(result)
        {
         case BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_COMPLETED:
            return "COMPLETED";
         case BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_ALREADY_COMPLETED:
            return "ALREADY_COMPLETED";
         default:
            return "REJECTED";
        }
     }

   static void       LogPersistedCompletionAttempt(const CPendingExecutionEntry &entry,
                                                   const string profitLevelId,
                                                   const ENUM_BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_RESULT result,
                                                   const string reason,
                                                   const string completionPath)
     {
      Print("profit_close_persisted_completion_build_marker=",BRE_PROFIT_CLOSE_PERSISTED_PENDING_COMPLETION_BUILD_MARKER);
      Print("profit_close_persisted_completion_attempted=true");
      Print("profit_close_persisted_completion_execution_request_id=",entry.ExecutionRequestId());
      Print("profit_close_persisted_completion_basket_id=",entry.BasketId().Value());
      Print("profit_close_persisted_completion_profit_level_id=",profitLevelId);
      Print("profit_close_persisted_completion_result=",CompletionResultToString(result));
      Print("profit_close_persisted_completion_reason=",reason);
      if(result==BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_COMPLETED ||
         result==BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_ALREADY_COMPLETED)
        {
         Print("profit_level_completed=true");
         Print("profit_level_current_state=COMPLETED");
         Print("profit_close_reconcile_completion_path=",completionPath);
        }
     }

public:
   static bool       TryParseProfitClosePersistedIdempotency(const string idempotencyKey,
                                                             SProfitClosePersistedIdempotencyParse &parsedOut)
     {
      parsedOut.valid=false;
      parsedOut.basketId="";
      parsedOut.profitLevelId="";
      parsedOut.quoteSequence=0;
      parsedOut.reason="";

      const string prefix="profit-level-close:";
      if(StringFind(idempotencyKey,prefix)!=0)
        {
         parsedOut.reason="Invalid idempotency prefix";
         return false;
        }

      string remainder=StringSubstr(idempotencyKey,StringLen(prefix));
      const string levelMarker=":level:";
      int levelPos=StringFind(remainder,levelMarker);
      if(levelPos<=0)
        {
         parsedOut.reason="Missing level marker";
         return false;
        }

      parsedOut.basketId=StringSubstr(remainder,0,levelPos);
      string afterLevel=StringSubstr(remainder,levelPos+StringLen(levelMarker));
      const string quoteMarker=":q:";
      int quotePos=StringFind(afterLevel,quoteMarker);
      if(quotePos<=0)
        {
         parsedOut.reason="Missing quote sequence marker";
         return false;
        }

      parsedOut.profitLevelId=StringSubstr(afterLevel,0,quotePos);
      string quotePart=StringSubstr(afterLevel,quotePos+StringLen(quoteMarker));
      if(parsedOut.basketId=="" || parsedOut.profitLevelId=="")
        {
         parsedOut.reason="Empty basket or profit level id";
         return false;
        }
      if(!IsAsciiDigitsOnly(quotePart))
        {
         parsedOut.reason="Invalid quote sequence";
         return false;
        }

      parsedOut.quoteSequence=StringToInteger(quotePart);
      parsedOut.valid=true;
      return true;
     }

   static bool       PassesPersistedCompletionSafety(const CPendingExecutionEntry &entry,string &reasonOut)
     {
      reasonOut="";
      if(entry.Status()!=BRE_TRADE_EXEC_STATUS_FILLED)
        {
         reasonOut="Pending status is not FILLED";
         return false;
        }
      if(entry.IntentType()!=BRE_EXEC_INTENT_CLOSE_POSITION)
        {
         reasonOut="Pending intent is not CLOSE_POSITION";
         return false;
        }
      if(!entry.BrokerCorrelation().HasBrokerDealId())
        {
         reasonOut="Broker deal evidence is not verified";
         return false;
        }
      if(entry.BasketId().Value()=="")
        {
         reasonOut="Persisted basket_id is missing";
         return false;
        }
      if(!entry.BrokerCorrelation().HasPositionTicket())
        {
         reasonOut="Persisted ticket is missing";
         return false;
        }
      if(entry.RequestedVolume()<=0.0)
        {
         reasonOut="Persisted requested close volume is missing";
         return false;
        }
      return true;
     }

   static bool       TryCompleteFilledProfitCloseFromPending(const CPendingExecutionEntry &entry,
                                                             IBasketRepository *basketRepository,
                                                             SProfitClosePersistedCompletionOutcome &outcomeOut,
                                                             IClock *clock=NULL,
                                                             IUniqueIdGenerator *idGenerator=NULL,
                                                             const string completionPath="startup_persisted_pending")
     {
      outcomeOut.result=BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_REJECTED;
      outcomeOut.reason="";
      outcomeOut.profitLevelId="";

      string safetyReason="";
      if(!PassesPersistedCompletionSafety(entry,safetyReason))
        {
         outcomeOut.reason=safetyReason;
         LogPersistedCompletionAttempt(entry,outcomeOut.profitLevelId,outcomeOut.result,outcomeOut.reason,completionPath);
         return false;
        }

      if(basketRepository==NULL)
        {
         outcomeOut.reason="Basket repository unavailable";
         LogPersistedCompletionAttempt(entry,outcomeOut.profitLevelId,outcomeOut.result,outcomeOut.reason,completionPath);
         return false;
        }

      SProfitClosePersistedIdempotencyParse parsed;
      if(!TryParseProfitClosePersistedIdempotency(entry.IdempotencyKey(),parsed))
        {
         outcomeOut.reason=parsed.reason;
         LogPersistedCompletionAttempt(entry,outcomeOut.profitLevelId,outcomeOut.result,outcomeOut.reason,completionPath);
         return false;
        }

      outcomeOut.profitLevelId=parsed.profitLevelId;
      if(parsed.basketId!=entry.BasketId().Value())
        {
         outcomeOut.reason="Parsed basket_id does not match persisted basket_id";
         LogPersistedCompletionAttempt(entry,outcomeOut.profitLevelId,outcomeOut.result,outcomeOut.reason,completionPath);
         return false;
        }

      CResult<CBasketAggregate> loaded=basketRepository.Load(entry.BasketId());
      if(loaded.IsFail())
        {
         outcomeOut.reason="Basket aggregate load failed";
         LogPersistedCompletionAttempt(entry,outcomeOut.profitLevelId,outcomeOut.result,outcomeOut.reason,completionPath);
         return false;
        }

      CBasketAggregate basket;
      if(!loaded.TryGetValue(basket))
        {
         outcomeOut.reason="Basket aggregate unavailable";
         LogPersistedCompletionAttempt(entry,outcomeOut.profitLevelId,outcomeOut.result,outcomeOut.reason,completionPath);
         return false;
        }

      CBasketProfitLevelProgress progress;
      if(basket.FindProfitLevelProgress(parsed.profitLevelId,progress) && progress.CloseCompleted())
        {
         outcomeOut.result=BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_ALREADY_COMPLETED;
         outcomeOut.reason="";
         LogPersistedCompletionAttempt(entry,outcomeOut.profitLevelId,outcomeOut.result,outcomeOut.reason,completionPath);
         return true;
        }

      datetime nowUtc=clock!=NULL ? clock.Now() : TimeCurrent();
      CEventId eventId;
      if(idGenerator!=NULL)
         eventId=CEventId(idGenerator.NewGuid());
      else
         eventId=CEventId("profit-close-persisted-pending");

      if(!basket.FindProfitLevelProgress(parsed.profitLevelId,progress) || !progress.Reached())
         basket.ApplyProfitLevelReached(parsed.profitLevelId,CUtcTime(nowUtc),CCommandId(""),eventId);

      CVoidResult completed=basket.ApplyProfitLevelCloseCompleted(parsed.profitLevelId,
                                                                  CMoney(0.0),
                                                                  CCommandId(""),
                                                                  eventId,
                                                                  CUtcTime(nowUtc));
      if(completed.IsFail())
        {
         outcomeOut.reason=completed.ErrorMessage();
         LogPersistedCompletionAttempt(entry,outcomeOut.profitLevelId,outcomeOut.result,outcomeOut.reason,completionPath);
         return false;
        }

      basketRepository.Save(basket);
      outcomeOut.result=BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_COMPLETED;
      outcomeOut.reason="";
      LogPersistedCompletionAttempt(entry,outcomeOut.profitLevelId,outcomeOut.result,outcomeOut.reason,completionPath);
      return true;
     }
  };

#endif
