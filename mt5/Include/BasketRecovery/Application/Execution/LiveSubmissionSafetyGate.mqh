#ifndef BRE_APP_LIVE_SUBMISSION_SAFETY_GATE_MQH
#define BRE_APP_LIVE_SUBMISSION_SAFETY_GATE_MQH

#include <BasketRecovery/Application/Execution/LiveSubmissionSafetyGateContext.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationPolicy.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionTransitionRules.mqh>
#include <BasketRecovery/Domain/Execution/LiveSubmissionSafetyRejectionReason.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>

class CLiveSubmissionSafetyGate
  {
private:
   static bool       BasketHasBlockingPendingState(CPendingExecutionRegistry *registry,
                                                     const CBasketId &basketId,
                                                     const string executionRequestId)
     {
      if(registry==NULL)
         return false;
      for(int i=0;i<registry.Count();i++)
        {
         CPendingExecutionEntry other;
         if(!registry.TryGetEntry(i,other))
            continue;
         if(other.BasketId().Value()!=basketId.Value())
            continue;
         if(other.ExecutionRequestId()==executionRequestId)
            continue;
         if(other.Status()==BRE_TRADE_EXEC_STATUS_QUEUED ||
            other.Status()==BRE_TRADE_EXEC_STATUS_SUBMITTED ||
            other.Status()==BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED)
            return true;
         if(CPendingExecutionTransitionRules::BlocksBlindResend(other.Status()))
            return true;
        }
      return false;
     }

   static bool       BasketHasReconcilingBlock(CPendingExecutionRegistry *registry,const CBasketId &basketId)
     {
      if(registry==NULL)
         return false;
      for(int i=0;i<registry.Count();i++)
        {
         CPendingExecutionEntry entry;
         if(!registry.TryGetEntry(i,entry))
            continue;
         if(entry.BasketId().Value()!=basketId.Value())
            continue;
         if(entry.Status()==BRE_TRADE_EXEC_STATUS_UNKNOWN ||
            entry.Status()==BRE_TRADE_EXEC_STATUS_RECONCILING ||
            entry.Status()==BRE_TRADE_EXEC_STATUS_TIMED_OUT)
            return true;
        }
      return false;
     }

public:
   static bool       Evaluate(CLiveSubmissionSafetyGateContext &context,
                              CPendingExecutionRegistry *registry,
                              ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON &reason,
                              string &detail)
     {
      reason=BRE_LIVE_SAFETY_NONE;
      detail="";

      if(context.Config().GlobalExecutionKillSwitch())
        {
         reason=BRE_LIVE_SAFETY_GLOBAL_KILL_SWITCH;
         detail="Global execution kill switch is enabled";
         return false;
        }

      if(CExecutionAuthorizationPolicy::IsBasketKillSwitchActive(context.Config(),context.Entry().BasketId().Value()))
        {
         reason=BRE_LIVE_SAFETY_BASKET_KILL_SWITCH;
         detail="Basket execution kill switch is active";
         return false;
        }

      CAccountExecutionEligibilitySnapshot eligibility=context.Eligibility();
      if(!eligibility.IsExplicitDemo())
        {
         if(eligibility.Classification()==BRE_ACCOUNT_ELIGIBILITY_REAL)
           {
            reason=BRE_LIVE_SAFETY_ACCOUNT_NOT_DEMO;
            detail="Real/live account rejected";
           }
         else
           {
            reason=BRE_LIVE_SAFETY_ACCOUNT_UNKNOWN;
            detail="Unknown account classification rejected";
           }
         return false;
        }

      if(!eligibility.AccountTradeAllowed())
        {
         reason=BRE_LIVE_SAFETY_ACCOUNT_TRADE_DISABLED;
         detail="Account trade permission disabled";
         return false;
        }

      if(!eligibility.TerminalTradeAllowed())
        {
         reason=BRE_LIVE_SAFETY_TERMINAL_ALGO_DISABLED;
         detail="Terminal Algo Trading disabled";
         return false;
        }

      if(!eligibility.ChartExpertTradeAllowed())
        {
         reason=BRE_LIVE_SAFETY_CHART_EA_TRADE_DISABLED;
         detail="Chart-level EA trading permission disabled";
         return false;
        }

      ENUM_BRE_BASKET_LIFECYCLE_STATE lifecycle=context.Basket().LifecycleState();
      if(lifecycle==BRE_STATE_SUSPENDED || lifecycle==BRE_STATE_CLOSING ||
         lifecycle==BRE_STATE_FINISHED || lifecycle==BRE_STATE_ERROR)
        {
         reason=BRE_LIVE_SAFETY_BASKET_LOCKED;
         detail="Basket is locked, suspended, closing, or finished";
         return false;
        }

      if(lifecycle!=BRE_STATE_ACTIVE)
        {
         reason=BRE_LIVE_SAFETY_BASKET_NOT_ACTIVE;
         detail="Basket lifecycle is not ACTIVE";
         return false;
        }

      if(context.Entry().StrategyProfileHash()!=context.Basket().StrategyProfileHash())
        {
         reason=BRE_LIVE_SAFETY_PROFILE_HASH_MISMATCH;
         detail="Strategy profile hash mismatch";
         return false;
        }

      if(context.Entry().ExpectedBasketVersion()!=(int)context.Basket().Version())
        {
         reason=BRE_LIVE_SAFETY_BASKET_VERSION_MISMATCH;
         detail="Expected basket version mismatch";
         return false;
        }

      if(context.Entry().Status()!=BRE_TRADE_EXEC_STATUS_QUEUED || !context.Entry().IsPreparedQueued())
        {
         reason=BRE_LIVE_SAFETY_NOT_QUEUED_PREPARED;
         detail="Request must be QUEUED with preparation metadata";
         return false;
        }

      if(context.Envelope().IsExpired(context.NowUtc()))
        {
         reason=BRE_LIVE_SAFETY_ENVELOPE_EXPIRED;
         detail="Prepared envelope expired";
         return false;
        }

      if(context.Quote().FreshnessAgeMs()>context.MarketSafety().QuoteStaleThresholdMs())
        {
         reason=BRE_LIVE_SAFETY_STALE_QUOTE;
         detail="Quote freshness threshold exceeded";
         return false;
        }

      if(context.Quote().SpreadPoints()>context.MarketSafety().MaxSpreadPoints())
        {
         reason=BRE_LIVE_SAFETY_WIDE_SPREAD;
         detail="Spread exceeds configured threshold";
         return false;
        }

      if(context.Quote().SessionStatus()!=BRE_TRADING_SESSION_OPEN)
        {
         reason=BRE_LIVE_SAFETY_MARKET_UNAVAILABLE;
         detail="Market/session unavailable";
         return false;
        }

      CSymbolTradingConstraints constraints=context.Quote().Constraints();
      double requestedVolume=context.Entry().RequestedVolume();
      if(requestedVolume<constraints.VolumeMin() || requestedVolume>constraints.VolumeMax())
        {
         reason=BRE_LIVE_SAFETY_VOLUME_INVALID;
         detail="Requested volume violates symbol constraints";
         return false;
        }

      if(constraints.StopsLevel()<0 || constraints.FreezeLevel()<0)
        {
         reason=BRE_LIVE_SAFETY_STOP_FREEZE_INVALID;
         detail="Stop/freeze constraints invalid";
         return false;
        }

      if(BasketHasBlockingPendingState(registry,context.Entry().BasketId(),context.Entry().ExecutionRequestId()))
        {
         reason=BRE_LIVE_SAFETY_CONFLICTING_PENDING;
         detail="Conflicting pending execution request exists";
         return false;
        }

      if(BasketHasReconcilingBlock(registry,context.Entry().BasketId()))
        {
         reason=BRE_LIVE_SAFETY_BASKET_RECONCILING_BLOCK;
         detail="Basket has UNKNOWN/RECONCILING pending execution";
         return false;
        }

      if(!CExecutionAuthorizationPolicy::PassesDailyLossPlaceholder())
        {
         reason=BRE_LIVE_SAFETY_DAILY_LOSS_GATE;
         detail="Daily loss gate placeholder failed";
         return false;
        }

      if(!CExecutionAuthorizationPolicy::PassesMaxConcurrentPlaceholder())
        {
         reason=BRE_LIVE_SAFETY_MAX_CONCURRENT_GATE;
         detail="Max concurrent gate placeholder failed";
         return false;
        }

      return true;
     }
  };

#endif
