#ifndef BRE_APP_IN_MEMORY_HOT_PATH_DIAGNOSTICS_MQH
#define BRE_APP_IN_MEMORY_HOT_PATH_DIAGNOSTICS_MQH

#include <BasketRecovery/Application/FastPath/FastPathSkipReason.mqh>

class CInMemoryHotPathDiagnostics
  {
private:
   ulong  m_lastDurationMs;
   int    m_lastEvaluations;
   int    m_lastDeferred;
   int    m_lastSkipped;
   string m_lastSymbol;
   ulong  m_lastQuoteSequence;
   double m_lastBid;
   double m_lastAsk;
   int    m_lastActiveBasketCount;
   ENUM_BRE_FAST_PATH_SKIP_REASON m_lastPrimaryReason;

   int    m_totalTicks;
   int    m_totalEvaluated;
   int    m_totalDeferred;
   int    m_totalSkipped;
   int    m_skipNoMatchingBasket;
   int    m_skipDuplicateQuote;
   int    m_skipMinInterval;
   int    m_skipStaleQuote;
   int    m_skipBudgetExhausted;
   int    m_skipTriggerPolicy;
   ulong  m_maxDurationMs;

   void              RecordSkipReason(const ENUM_BRE_FAST_PATH_SKIP_REASON reason)
     {
      switch(reason)
        {
         case BRE_FAST_SKIP_NO_MATCHING_BASKET: m_skipNoMatchingBasket++; break;
         case BRE_FAST_SKIP_DUPLICATE_QUOTE_SEQUENCE: m_skipDuplicateQuote++; break;
         case BRE_FAST_SKIP_MIN_INTERVAL_GATE: m_skipMinInterval++; break;
         case BRE_FAST_SKIP_STALE_QUOTE: m_skipStaleQuote++; break;
         case BRE_FAST_SKIP_BUDGET_EXHAUSTED: m_skipBudgetExhausted++; break;
         case BRE_FAST_SKIP_TRIGGER_POLICY: m_skipTriggerPolicy++; break;
         default: break;
        }
     }

public:
                     CInMemoryHotPathDiagnostics(void)
     {
      m_lastDurationMs=0;
      m_lastEvaluations=0;
      m_lastDeferred=0;
      m_lastSkipped=0;
      m_lastSymbol="";
      m_lastQuoteSequence=0;
      m_lastBid=0.0;
      m_lastAsk=0.0;
      m_lastActiveBasketCount=0;
      m_lastPrimaryReason=BRE_FAST_SKIP_NONE;
      m_totalTicks=0;
      m_totalEvaluated=0;
      m_totalDeferred=0;
      m_totalSkipped=0;
      m_skipNoMatchingBasket=0;
      m_skipDuplicateQuote=0;
      m_skipMinInterval=0;
      m_skipStaleQuote=0;
      m_skipBudgetExhausted=0;
      m_skipTriggerPolicy=0;
      m_maxDurationMs=0;
     }

   void              RecordBasketSkip(const ENUM_BRE_FAST_PATH_SKIP_REASON reason)
     {
      if(reason!=BRE_FAST_SKIP_NONE)
         RecordSkipReason(reason);
     }

   void              RecordTickRun(const string symbol,
                                   const ulong startMsc,
                                   const int evaluations,
                                   const int deferred,
                                   const int skipped,
                                   const int activeBasketCount,
                                   const ulong quoteSequence,
                                   const double bid,
                                   const double ask,
                                   const ENUM_BRE_FAST_PATH_SKIP_REASON primaryReason)
     {
      m_lastSymbol=symbol;
      m_lastEvaluations=evaluations;
      m_lastDeferred=deferred;
      m_lastSkipped=skipped;
      m_lastActiveBasketCount=activeBasketCount;
      m_lastQuoteSequence=quoteSequence;
      m_lastBid=bid;
      m_lastAsk=ask;
      m_lastPrimaryReason=primaryReason;
      ulong endMsc=GetTickCount64();
      m_lastDurationMs=(endMsc>startMsc) ? (endMsc-startMsc) : 0;
      if(m_lastDurationMs>m_maxDurationMs)
         m_maxDurationMs=m_lastDurationMs;

      m_totalTicks++;
      m_totalEvaluated+=evaluations;
      m_totalDeferred+=deferred;
      m_totalSkipped+=skipped;
      if(primaryReason!=BRE_FAST_SKIP_NONE)
         RecordSkipReason(primaryReason);
     }

   ulong             LastDurationMs(void) const { return m_lastDurationMs; }
   int               LastEvaluations(void) const { return m_lastEvaluations; }
   int               LastDeferred(void) const { return m_lastDeferred; }
   int               LastSkipped(void) const { return m_lastSkipped; }
   string            LastSymbol(void) const { return m_lastSymbol; }
   ulong             LastQuoteSequence(void) const { return m_lastQuoteSequence; }
   double            LastBid(void) const { return m_lastBid; }
   double            LastAsk(void) const { return m_lastAsk; }
   int               LastActiveBasketCount(void) const { return m_lastActiveBasketCount; }
   ENUM_BRE_FAST_PATH_SKIP_REASON LastPrimaryReason(void) const { return m_lastPrimaryReason; }

   int               TotalTicks(void) const { return m_totalTicks; }
   int               TotalEvaluated(void) const { return m_totalEvaluated; }
   int               TotalDeferred(void) const { return m_totalDeferred; }
   int               TotalSkipped(void) const { return m_totalSkipped; }
   int               SkipNoMatchingBasket(void) const { return m_skipNoMatchingBasket; }
   int               SkipDuplicateQuoteSequence(void) const { return m_skipDuplicateQuote; }
   int               SkipMinIntervalGate(void) const { return m_skipMinInterval; }
   int               SkipStaleQuote(void) const { return m_skipStaleQuote; }
   int               SkipBudgetExhausted(void) const { return m_skipBudgetExhausted; }
   int               SkipTriggerPolicy(void) const { return m_skipTriggerPolicy; }
   ulong             MaxDurationMs(void) const { return m_maxDurationMs; }
  };

#endif
