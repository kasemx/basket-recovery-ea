#ifndef BRE_APP_FAST_PATH_DIAGNOSTIC_REPORTER_MQH
#define BRE_APP_FAST_PATH_DIAGNOSTIC_REPORTER_MQH

#include <BasketRecovery/Application/Configuration/FastPathConfig.mqh>
#include <BasketRecovery/Application/FastPath/InMemoryHotPathDiagnostics.mqh>
#include <BasketRecovery/Application/FastPath/FastPathSkipReason.mqh>

class CFastPathDiagnosticReporter
  {
private:
   CFastPathConfig m_config;
   string          m_lastSymbol;
   ulong           m_lastPrintMsc;

   bool              IsEnabled(void) const
     {
      return m_config.EnableFastPathDiagnostics();
     }

   bool              ShouldEmit(const string symbol,const ENUM_BRE_FAST_PATH_SKIP_REASON primaryReason) const
     {
      if(!IsEnabled())
         return false;

      if(primaryReason==BRE_FAST_SKIP_NO_MATCHING_BASKET &&
         !m_config.EnableFastPathNoBasketHeartbeat())
         return false;

      if(m_lastSymbol==symbol &&
         m_lastPrintMsc>0 &&
         (GetTickCount64()-m_lastPrintMsc)<(ulong)m_config.FastPathDiagnosticIntervalMs())
         return false;

      return true;
     }

   void              MarkEmitted(const string symbol)
     {
      m_lastSymbol=symbol;
      m_lastPrintMsc=GetTickCount64();
     }

public:
                     CFastPathDiagnosticReporter(const CFastPathConfig &config)
     {
      m_config=config;
      m_lastSymbol="";
      m_lastPrintMsc=0;
     }

   bool              WouldEmitTickLine(const string symbol,
                                       const ENUM_BRE_FAST_PATH_SKIP_REASON primaryReason) const
     {
      return ShouldEmit(symbol,primaryReason);
     }

   void              NotifyTickLineEmitted(const string symbol)
     {
      MarkEmitted(symbol);
     }

   bool              WantsOutput(void) const { return IsEnabled(); }

   void              EmitStartupLine(const int symbolIndexBasketCount,
                                     const int fastTickBudget) const
     {
      Print(StringFormat("BRE fast-path startup | diagnostics=%s | interval_ms=%d | no_basket_heartbeat=%s | tick_budget=%d | symbol_index_baskets=%d",
                         IsEnabled() ? "on" : "off",
                         m_config.FastPathDiagnosticIntervalMs(),
                         m_config.EnableFastPathNoBasketHeartbeat() ? "on" : "off",
                         fastTickBudget,
                         symbolIndexBasketCount));
     }

   void              MaybeEmitTickLine(const string symbol,
                                       const CInMemoryHotPathDiagnostics &diagnostics,
                                       const ENUM_BRE_FAST_PATH_SKIP_REASON primaryReason)
     {
      if(!ShouldEmit(symbol,primaryReason))
         return;

      Print(StringFormat("BRE fast-path tick | symbol=%s | seq=%I64u | bid=%.5f | ask=%.5f | active=%d | evaluated=%d | skipped=%d | deferred=%d | reason=%s | elapsed_ms=%I64u",
                         symbol,
                         diagnostics.LastQuoteSequence(),
                         diagnostics.LastBid(),
                         diagnostics.LastAsk(),
                         diagnostics.LastActiveBasketCount(),
                         diagnostics.LastEvaluations(),
                         diagnostics.LastSkipped(),
                         diagnostics.LastDeferred(),
                         FastPathSkipReasonLabel(primaryReason),
                         diagnostics.LastDurationMs()));

      MarkEmitted(symbol);
     }

   void              EmitDeinitSummary(const CInMemoryHotPathDiagnostics &diagnostics,
                                       const int stagedCommandCount) const
     {
      Print(StringFormat("BRE fast-path deinit | ticks=%d | evaluated=%d | skips={no_basket:%d dup_seq:%d min_interval:%d stale:%d budget:%d trigger:%d} | deferred=%d | max_elapsed_ms=%I64u | staged=%d",
                         diagnostics.TotalTicks(),
                         diagnostics.TotalEvaluated(),
                         diagnostics.SkipNoMatchingBasket(),
                         diagnostics.SkipDuplicateQuoteSequence(),
                         diagnostics.SkipMinIntervalGate(),
                         diagnostics.SkipStaleQuote(),
                         diagnostics.SkipBudgetExhausted(),
                         diagnostics.SkipTriggerPolicy(),
                         diagnostics.TotalDeferred(),
                         diagnostics.MaxDurationMs(),
                         stagedCommandCount));
     }
  };

#endif
