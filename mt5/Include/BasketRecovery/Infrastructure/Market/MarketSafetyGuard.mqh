#ifndef BRE_INF_MARKET_SAFETY_GUARD_MQH
#define BRE_INF_MARKET_SAFETY_GUARD_MQH

#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Market/AccountContextSnapshot.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class CMarketSafetyGuard
  {
private:
   CMarketSafetyConfig m_config;
   string              m_lastWarningKey;
   ulong               m_lastWarningTickMs;

   bool              ShouldEmitWarning(const string key) const
     {
      if(key==m_lastWarningKey && m_config.WarningDedupeWindowMs()>0)
        {
         ulong elapsedMs=(ulong)GetTickCount()-m_lastWarningTickMs;
         if(elapsedMs<(ulong)m_config.WarningDedupeWindowMs())
            return false;
        }
      return true;
     }

   void              RememberWarning(const string key)
     {
      m_lastWarningKey=key;
      m_lastWarningTickMs=(ulong)GetTickCount();
     }

public:
                     CMarketSafetyGuard(void)
     {
      m_config=CMarketSafetyConfig();
      m_lastWarningKey="";
      m_lastWarningTickMs=0;
     }

                     CMarketSafetyGuard(const CMarketSafetyConfig &config)
     {
      m_config=config;
      m_lastWarningKey="";
      m_lastWarningTickMs=0;
     }

   CVoidResult       ValidateQuote(const CMarketQuote &quote) const
     {
      if(quote.Symbol()=="")
         return CVoidResult::Fail(BRE_ERR_SYMBOL_UNAVAILABLE,"Symbol unavailable");

      if(quote.Bid()<=0.0 || quote.Ask()<=0.0)
         return CVoidResult::Fail(BRE_ERR_SYMBOL_UNAVAILABLE,"Quote prices unavailable");

      if(quote.FreshnessAgeMs()>m_config.QuoteStaleThresholdMs())
         return CVoidResult::Fail(BRE_ERR_MARKET_QUOTE_STALE,"Quote is stale");

      if(quote.SpreadPoints()>m_config.MaxSpreadPoints())
         return CVoidResult::Fail(BRE_ERR_MARKET_SPREAD_TOO_WIDE,"Spread exceeds threshold");

      if(quote.SessionStatus()==BRE_TRADING_SESSION_CLOSED)
         return CVoidResult::Fail(BRE_ERR_MARKET_CLOSED,"Market session closed");

      return CVoidResult::Ok();
     }

   CVoidResult       ValidateAccount(const CAccountContextSnapshot &account) const
     {
      if(!account.TradeAllowed())
         return CVoidResult::Fail(BRE_ERR_ACCOUNT_TRADE_DISABLED,"Account trading disabled");
      return CVoidResult::Ok();
     }

   CMarketSafetyConfig Config(void) const { return m_config; }

   CVoidResult       ValidateForEvaluation(const CMarketQuote &quote,
                                           const CAccountContextSnapshot &account,
                                           string &outWarningKey)
     {
      outWarningKey="";
      CVoidResult accountResult=ValidateAccount(account);
      if(accountResult.IsFail())
        {
         outWarningKey="account:"+IntegerToString((long)accountResult.ErrorCode());
         if(ShouldEmitWarning(outWarningKey))
            RememberWarning(outWarningKey);
         return accountResult;
        }

      CVoidResult quoteResult=ValidateQuote(quote);
      if(quoteResult.IsFail())
        {
         outWarningKey=quote.Symbol()+":"+IntegerToString((long)quoteResult.ErrorCode());
         if(ShouldEmitWarning(outWarningKey))
            RememberWarning(outWarningKey);
         return quoteResult;
        }

      return CVoidResult::Ok();
     }
  };

#endif
